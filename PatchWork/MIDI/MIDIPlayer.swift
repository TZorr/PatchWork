//
//  MIDIPlayer.swift
//  PatchWork
//
//  The MIDI Player element's playback: one file, looping, on the shared
//  output.
//
//  One player for the whole panel, like MIDIActivity is one noticeboard for
//  every Status and Monitor: place more than one MIDI Player element and
//  they all show the same file and play/stop state, since there is one
//  output and one thing going out of it at a time.
//
//  It knows nothing about ports or endpoints - it is handed something that
//  sends, something that silences, something to complain to. What it needs
//  from CoreMIDI is its *clock*: a MIDITimeStamp is when a packet should
//  sound, and scheduling is the whole design (see MIDIHostClock).
//
//  **Timestamps, not sleeps.** The next `lookahead` seconds of events go out
//  in one batch, each stamped with when it is due, and CoreMIDI's driver
//  delivers them then. Sleep-for-each-gap-and-send would make the sleep
//  *be* the timing; here the sleep only decides when to top the window up,
//  and may run late by a whole scheduling quantum without a note moving.
//
//  **The refill runs off the main actor.** A `Task` started from a
//  main-actor method inherits it by default, so every packet used to be
//  built and sent on the thread that draws the panel - and any stall longer
//  than `lookahead` (a window resize, a menu held open) meant the next
//  refill found several events already due and CoreMIDI released them as a
//  burst. Timestamps make short stalls harmless but not one longer than the
//  window, so `run` below is static, nonisolated, takes everything by
//  value, and starts with `Task.detached` - the main actor plays no part
//  between the press and the end of the run.
//
//  **The file is parsed once, at load, and the events are kept.**
//  Re-reading on every loop pass would put the filesystem in the playback
//  path; reading once fails fast, before anything plays, and for a
//  sandboxed app is one fewer thing that can be revoked mid-stream.
//
//  **A stop lands between messages by itself.** Task cancellation already
//  interrupts `sleep`, so there is nothing to poll. Scheduling ahead adds
//  the other half: what is already committed has to be taken back, which
//  is what `silence` is for.
//
import CoreMIDI
import Foundation
import Observation

/// The latest moment the player has handed to CoreMIDI.
///
/// Shared between the main actor and the run's own task, which is why it is a
/// locked box rather than a property: the run is what learns the number and the
/// stop is what needs it.
nonisolated final class MIDISchedule: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: MIDITimeStamp = 0

    func note(_ stamp: MIDITimeStamp) {
        lock.withLock { if stamp > latest { latest = stamp } }
    }

    /// Whether anything of ours is still waiting to sound.
    var pending: Bool {
        lock.withLock { latest > MIDIHostClock.now }
    }
}

@Observable
final class MIDIPlayer {
    /// How far ahead of the playhead events are handed to CoreMIDI.
    ///
    /// The one number that trades two things off. Longer means fewer wake-ups
    /// and more slack before a busy machine could starve the wire; shorter
    /// means less to take back on a stop, and less committed to a device that
    /// might be unplugged. 200ms is comfortably more than a scheduling
    /// quantum and comfortably less than anyone notices in a stop, which is
    /// flushed anyway.
    ///
    /// `nonisolated` here and below because `run` reads them, and `run` is not
    /// on this actor.
    nonisolated static let lookahead: TimeInterval = 0.2

    /// How long after the run starts the file's own zero is placed.
    ///
    /// Without it the first events would be stamped with a moment already
    /// passing, which CoreMIDI treats as "now" - correct, but timed by when
    /// the press was handled rather than by the file. A lead-in puts every
    /// event, including the first, on the schedule.
    ///
    /// 50ms rather than the 10 this began with. The window has to be *built*
    /// inside the lead-in, and a first window is not always three note-ons: a
    /// .mid carrying a bulk dump is one 37KB message that goes out as ten
    /// sends (see MIDIWire.packetBytes), and 10ms was easily gone by the time
    /// they had. Whatever is left over is latency nobody can hear on a press.
    nonisolated static let leadIn: TimeInterval = 0.05

    /// The loaded file's name, or nil. What the element shows, and what
    /// outlives a stop: a bare press with no fresh drop resumes this.
    private(set) var name: String?
    private(set) var playing = false

    /// How long the file runs - its own length, not the moment of its last
    /// note. See MIDIFileContents: the difference is a trailing rest, and
    /// looping on the last note instead drops it every pass.
    private(set) var duration: TimeInterval = 0

    /// The parsed file. Not observed - it changes only with `name`, which is,
    /// and a few thousand events are not something a view should be diffed on.
    @ObservationIgnored private var events: [MIDIFileEvent] = []
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// Which run is the current one.
    ///
    /// A run that has been stopped and replaced must not tidy up after the run
    /// that replaced it. The old code let it: a cancelled loop still fell out
    /// of the bottom and set `playing = false`, and `load` does a stop
    /// immediately followed by a play, so the new run's state was the state it
    /// cleared. Serialisation on the main actor made that very unlikely; a
    /// detached task makes the window milliseconds wide.
    @ObservationIgnored private var generation = 0

    /// How far ahead the current run has committed, for `hasPendingSchedule`.
    @ObservationIgnored private var schedule = MIDISchedule()

    /// Whether CoreMIDI is still holding packets of ours.
    ///
    /// Read before flushing. `MIDIFlushOutput` names a destination and nothing
    /// else - the SDK's own words are "all pending events scheduled to be sent
    /// to this destination" - with no mention of the calling client. On a rig
    /// where a DAW is pointed at the same device, a flush with nothing of ours
    /// outstanding is a risk taken for no reason at all. So it is only taken
    /// when there is something to take back.
    var hasPendingSchedule: Bool { schedule.pending }

    /// How a run ended, carried back to the main actor in one hop rather than
    /// one per event.
    nonisolated enum Outcome: Sendable {
        case finished
        case cancelled
        case failed(String)
    }

    /// Reads a file and keeps it, replacing whatever was loaded. Throws before
    /// anything is playing if it cannot be read.
    ///
    /// Stops first: one file plays at a time, on the one output. Silencing
    /// what the last one was in the middle of is the caller's - see
    /// MIDIEngine.stopPlayback, which is what ContentView calls before this.
    func load(_ url: URL) throws {
        stop()
        // Security-scoped because this app is sandboxed and the URL arrived
        // from a drop. Bracketed tightly: once parsed, the file is not needed
        // again.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let parsed = try MIDIFile.parse(try Data(contentsOf: url))
        events = parsed.events
        duration = parsed.duration
        name = url.lastPathComponent
    }

    /// Loops the loaded file until stopped.
    ///
    /// `send` is handed the bytes and the moment they are due, and answers nil
    /// or the reason it could not; the first failure ends the run rather than
    /// spending the rest of the file failing once per message - a failed send
    /// means the device is gone. It is `@Sendable` because it is used from the
    /// run's own task, and it carries its endpoint already resolved, so there
    /// is no lookup in the per-event path.
    ///
    /// The shape is one pass over the events, refilled: everything already
    /// inside the window is stamped and handed over, and only then is there
    /// anything to wait for. A file whose events all land together is
    /// therefore one batch and no sleep at all.
    func play(send: @escaping @Sendable ([UInt8], MIDITimeStamp) -> String?,
              silence: @escaping @Sendable @MainActor () -> Void,
              onError: @escaping @Sendable @MainActor (String) -> Void) {
        stop()
        guard !events.isEmpty else {
            onError("There is nothing to play in \(name ?? "that file").")
            return
        }
        playing = true
        generation &+= 1
        let token = generation
        let events = self.events            // one copy, crossing once
        let span = duration
        let loops = span > 0
        // A fresh watermark per run: what the last one committed has either
        // sounded or been flushed, and either way it is not this run's.
        schedule = MIDISchedule()
        let schedule = self.schedule

        // `Task.detached`, and not `Task { }`: a plain Task started from a
        // main-actor method inherits the main actor, which is the whole thing
        // this is undoing. Nor would marking `run` nonisolated be enough on
        // its own - with approachable concurrency that means it runs on the
        // *caller's* executor, and the caller here is the main actor.
        loop = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = await Self.run(events: events, span: span,
                                         loops: loops, send: send, schedule: schedule)
            // A cancelled run says nothing: `stop` has already put `playing`
            // back, and may already have started the next file.
            if case .cancelled = outcome { return }
            await self?.finish(token, outcome: outcome, silence: silence, onError: onError)
        }
    }

    /// The refill loop, off every actor.
    ///
    /// `static` and `nonisolated` on purpose: it touches no property of the
    /// player at all, only values it was handed. That is what lets it run on
    /// the global executor while `playing` and `name` stay on the main actor
    /// where SwiftUI observes them - the two halves meet only at the one hop
    /// when the run ends.
    private nonisolated static func run(
        events: [MIDIFileEvent], span: TimeInterval, loops: Bool,
        send: @Sendable ([UInt8], MIDITimeStamp) -> String?,
        schedule: MIDISchedule
    ) async -> Outcome {
        let clock = ContinuousClock()
        // One anchor, on CoreMIDI's own clock, and everything is measured
        // against it - both what goes out and how long to wait next. Read
        // here rather than at the press, so that the lead-in is measured from
        // when the run actually began: whatever delayed the task's start, no
        // event can be stamped into the past because of it.
        //
        // Deliberately not a second anchor on the ContinuousClock: the two
        // do not tick alike. ContinuousClock keeps running while the machine
        // is asleep and a host timestamp does not, so a lid closed mid-file
        // would leave them hours apart, and a horizon read off the wrong one
        // would then call the entire rest of the file due at once. `clock`
        // below is only ever asked to wait *for* a length of time, never to
        // say what time it is.
        let origin = MIDIHostClock.now &+ MIDIHostClock.ticks(leadIn)

        var pass = 0
        repeat {
            // Where this pass's copy of the file starts, in the file's own
            // seconds from `origin`. A loop is the same events again, one
            // span later - not a fresh start, which would let each pass
            // inherit the last one's scheduling slack.
            let passOffset = TimeInterval(pass) * span
            var index = 0

            while index < events.count {
                // Checked here, at the top, and not merely before the sleep
                // further down: a sleep that finished *just* as the stop
                // arrived comes back without throwing, and the next thing
                // this loop does is hand a whole window over. That window
                // would then be scheduled after the press that was meant to
                // end it.
                if Task.isCancelled { return .cancelled }
                let elapsed = MIDIHostClock.elapsed(since: origin)
                let horizon = elapsed + lookahead
                // Everything due inside the window, in one go, each stamped
                // with the moment it is for.
                while index < events.count, passOffset + events[index].time <= horizon {
                    // And again per event, not only per window. A stop is
                    // answered by a flush on the main actor, and a packet
                    // handed over after that flush is one the flush cannot
                    // take back. Checking here is what holds that down to a
                    // single message in flight; `stop` silences a second time
                    // to catch even that one.
                    if Task.isCancelled { return .cancelled }
                    let due = passOffset + events[index].time
                    let stamp = origin &+ MIDIHostClock.ticks(due)
                    if let complaint = send(events[index].bytes, stamp) {
                        return .failed("Playback stopped: \(complaint)")
                    }
                    schedule.note(stamp)
                    index += 1
                }
                guard index < events.count else { break }
                // Nothing else is due yet. Wake when the next event comes
                // within the window - late is harmless, since what has gone
                // out is already timed, and waking late only makes the next
                // window a little shorter.
                //
                // `wait` cannot actually be negative here: an event that was
                // not pushed above is one past the horizon, which is the same
                // statement. Guarded rather than asserted because the cost is
                // a comparison and the alternative is a negative sleep.
                let wait = passOffset + events[index].time - lookahead - elapsed
                guard wait > 0 else { continue }
                do {
                    try await clock.sleep(for: .seconds(wait))
                } catch {
                    return .cancelled                   // cancelled mid-wait
                }
            }
            pass += 1
            // A file whose events all land at the same instant has no time to
            // loop through - repeating it would be a busy loop rather than a
            // repeat.
        } while loops && !Task.isCancelled
        return Task.isCancelled ? .cancelled : .finished
    }

    /// Stops, and silences whatever the file was in the middle of.
    ///
    /// `silence` has two jobs, and both are needed: **drop what is scheduled
    /// but not yet sounded**, and then **panic**. Cancelling the task only
    /// stops us handing over *more* - up to `lookahead` of the file is already
    /// with CoreMIDI and would otherwise play on for a fifth of a second after
    /// the press. And a stop can still land between a note on and its note
    /// off, which is what the panic is for; it goes out after the flush, or
    /// the flush would take it back too.
    ///
    /// **Twice, and not out of caution.** The refill is not on this actor any
    /// more, so a send can be in flight at the very moment the flush happens
    /// here, and a packet handed over after a flush is one the flush could not
    /// take back. The first silence is what makes the stop immediate; the
    /// second, once the run has actually let go, is what makes it complete.
    /// Silencing is idempotent - a flush with nothing scheduled and an All
    /// Notes Off to a quiet device are both nothing - so the second costs 32
    /// inaudible messages.
    ///
    /// One closure rather than two, because there is no moment where a caller
    /// wants one without the other - see MIDIEngine.stopPlayback, the only one.
    func stop(silence: (@Sendable @MainActor () -> Void)? = nil) {
        let running = loop
        loop = nil
        // Nothing from the run being stopped may `finish` after this.
        generation &+= 1
        let token = generation
        running?.cancel()
        if playing, let silence {
            silence()
            if let running {
                Task { @MainActor [weak self] in
                    await running.value
                    // Only if nothing has started in the meantime. Dropping a
                    // file on a playing element stops it and starts the next
                    // one within the same turn of the main actor, so this
                    // second silence would otherwise arrive *after* the new
                    // run had committed its first window - and flush it away,
                    // then panic over the top of it.
                    guard self?.generation == token else { return }
                    silence()
                }
            }
        }
        playing = false
    }

    /// The run ended on its own - it played out, or a send failed.
    private func finish(_ token: Int, outcome: Outcome,
                        silence: @Sendable @MainActor () -> Void,
                        onError: @Sendable @MainActor (String) -> Void) {
        // A run that has already been replaced tidies up nothing: `play` has
        // bumped the generation, and the state on this actor now belongs to
        // the run after it.
        guard token == generation else { return }
        loop = nil
        let wasPlaying = playing
        playing = false
        guard case .failed(let complaint) = outcome else { return }
        // A run that ended because a send failed can have left a note on: the
        // failure lands between a note on and its note off exactly as a stop
        // can, and nothing else is going to take that note back. This used to
        // report and stop there, holding the note for as long as whatever
        // still heard it was listening.
        if wasPlaying { silence() }
        onError(complaint)
    }

    /// What a press on the element does: stop if playing, or resume the file
    /// still loaded. A press carries no file of its own.
    ///
    /// A nil `send` is nothing chosen to send *to*, and is refused here rather
    /// than at the first event: a run that starts and then reports a failed
    /// send is a worse way of saying the same thing.
    func toggle(send: (@Sendable ([UInt8], MIDITimeStamp) -> String?)?,
                silence: @escaping @Sendable @MainActor () -> Void,
                onError: @escaping @Sendable @MainActor (String) -> Void) {
        if playing {
            stop(silence: silence)
        } else if name != nil {
            guard let send else {
                onError("No MIDI output is selected.")
                return
            }
            play(send: send, silence: silence, onError: onError)
        }
    }
}
