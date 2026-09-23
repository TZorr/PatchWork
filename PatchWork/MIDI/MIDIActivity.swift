//
//  MIDIActivity.swift
//  PatchWork
//
//  What the display elements show. Status, Monitor and LED are elements on
//  the canvas, but what they display is not theirs: there is one set of
//  ports and one stream of messages, and every Status on a panel is looking
//  at the same one.
//
//  So it lives here rather than in each element's properties - a per-element
//  copy would be saved to disk as though it were part of the design, and
//  two Monitors would disagree about what just happened.
//

import Foundation
import Observation

@Observable
final class MIDIActivity {
    /// How many lines the Monitor keeps, whatever a given element chooses
    /// to show. Enough to scroll back through a burst of NRPN trios
    /// without keeping a log nobody reads.
    static let historyLimit = 200

    /// How long the input lamp stays lit after a message. Long enough to
    /// see a single one, short enough that a stream reads as flicker rather
    /// than as a lamp that is simply on.
    static let flashDuration: Duration = .milliseconds(120)

    /// How many SENT lines the Status element has room for. One logical
    /// send is often several messages - an NRPN is four - and showing only
    /// the last would say "Data Entry (fine)" with no hint of what it was
    /// fine-tuning.
    static let sentLineLimit = 3

    /// How far above the limit the history is allowed to run before it is cut
    /// back down to it.
    ///
    /// Trimming to the limit on every message means a `removeFirst(1)` - and
    /// so a shift of two hundred elements - for each one, forever, once the
    /// history is full. Letting it overshoot and then cutting in one go makes
    /// that a shift per fifty-six messages instead. Nothing reads more than
    /// `historyLimit`, so the overshoot is invisible.
    static let historySlack = 56

    /// How many events the MIDI Monitor window keeps. Far above
    /// `historyLimit` because the two are different things: that one feeds a
    /// six-line tile on a panel, this one is a log somebody scrolls back
    /// through after a device misbehaved.
    static let eventLimit = 5000

    /// Newest last, the way a log reads - so a Monitor showing one line
    /// shows the newest, which is what a one-line monitor is for.
    private(set) var lines: [String] = []
    /// The Monitor window's own record - see MIDIEvent, and `beginCapture`
    /// for why it is usually empty.
    private(set) var events: [MIDIEvent] = []
    /// The last thing sent, one line per message.
    private(set) var sentLines: [String] = []
    /// Counts rather than only a lamp: they answer "is anything getting
    /// through at all" without a timer, and they do not lie when traffic is
    /// too fast to see.
    ///
    /// **Not observed**, though they are very much kept: no view reads them -
    /// the Status element shows `sentLines`, not a total - while the
    /// verification harness reads `receivedCount` at a dozen places to know
    /// that something arrived. Tracking them would mean an observation
    /// notification per message for a number nothing on screen shows.
    @ObservationIgnored private(set) var sentCount = 0
    @ObservationIgnored private(set) var receivedCount = 0
    /// Whether the input lamp is lit right now.
    private(set) var inputLit = false

    @ObservationIgnored private var flashTask: Task<Void, Never>?

    // ── The Monitor window's record ──────────────────────────────────────

    /// How many Monitor windows are open. **Nothing is recorded while this is
    /// zero**, and with no window open this class behaves exactly as it did
    /// before events existed.
    ///
    /// Not thrift for its own sake. Everything else in this file is written
    /// against one cost - a notification per message, with every Monitor and
    /// LED on the canvas re-evaluating for each: the counters are
    /// `@ObservationIgnored`, lines are appended in one batch per burst, the
    /// lamp waits in a single task rather than a task per flash. An observed
    /// array growing by every Clock byte would undo all of that, for a window
    /// nobody has open.
    @ObservationIgnored private var captureCount = 0
    @ObservationIgnored private var nextEventID: UInt64 = 0

    var isCapturing: Bool { captureCount > 0 }

    func beginCapture() { captureCount += 1 }

    /// Balanced with `beginCapture`. The events are dropped with the last
    /// window: keeping five thousand of them alive for a window that is gone
    /// would be a leak with a tidy name.
    func endCapture() {
        captureCount = max(0, captureCount - 1)
        if captureCount == 0 { events.removeAll() }
    }

    /// Files a batch, in one mutation, for the same reason `append` does.
    ///
    /// Takes the parts and mints the ids here so that a caller cannot hand out
    /// two events with the same one.
    func record(_ parts: [MIDIEventParts]) {
        guard isCapturing, !parts.isEmpty else { return }
        let now = Date()
        let new = parts.map { part -> MIDIEvent in
            nextEventID &+= 1
            return MIDIEvent(
                id: nextEventID, time: now,
                direction: part.direction, form: part.form, kind: part.kind,
                channel: part.channel, device: part.device,
                text: part.text, bytes: part.bytes
            )
        }
        events.append(contentsOf: new)
        // Same overshoot-then-cut as `lines`, and for the same reason - see
        // historySlack.
        if events.count > Self.eventLimit + Self.historySlack {
            events.removeFirst(events.count - Self.eventLimit)
        }
    }

    /// Empties the Monitor's log and nothing else.
    ///
    /// Deliberately not `clear()`: `lines` and the counts belong to the canvas
    /// Monitor element and to the verification harness, and a tool window
    /// should not quietly wipe something on the panel behind it.
    func clearEvents() {
        events.removeAll()
    }

    /// The last `count` lines, oldest first. Short of that, whatever there
    /// is - a monitor that padded itself with blanks would look broken
    /// rather than empty.
    func recent(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        return Array(lines.suffix(count))
    }

    func recordSent(_ messages: [MIDIMessage]) {
        guard !messages.isEmpty else { return }
        sentLines = messages.prefix(Self.sentLineLimit).map(\.description)
        append(messages.map { "TX  \($0.description)" })
        sentCount += messages.count
    }

    /// A Controller's messages, shown raw.
    ///
    /// Prefixed "CTRL" the way the others say RX and TX, so a line always
    /// says where it came from. They are shown at all because a controller
    /// set to Local Off gives no feedback of its own, so
    /// the app is the only place left to see that a key or knob got through.
    ///
    /// Raw, one line per message including an NRPN's CC 99 / CC 98 / CC 6 -
    /// this is a log of what was forwarded, and what was forwarded was what
    /// arrived. Not counted as sent: `sentCount` and the Status element's
    /// SENT rows are the panel's own sends, and a forwarded keystroke is not
    /// the panel saying anything.
    func recordController(_ messages: [RawMIDIMessage]) {
        guard !messages.isEmpty else { return }
        append(messages.map { "CTRL \($0.description)" })
        flash()
    }

    func recordReceived(_ messages: [IncomingMessage]) {
        guard !messages.isEmpty else { return }
        append(messages.map { "RX  \($0.description)" })
        receivedCount += messages.count
        flash()
    }

    /// Lights the lamp and schedules it out again.
    ///
    /// A cancelled-and-replaced task rather than a timestamp others poll:
    /// nothing here runs on a clock, and SwiftUI needs the change announced
    /// to redraw. Cancelling the previous one is what makes a stream read as
    /// one continuous glow rather than flickering off between messages.
    private func flash() {
        // Only when it is actually dark. Observation does no equality check of
        // its own, so `inputLit = true` on an already-lit lamp is still a
        // notification - and at two hundred messages a second that is two
        // hundred redraws of every LED element for a value that never changed.
        if !inputLit { inputLit = true }
        // The deadline moves; the task does not. Cancelling and allocating a
        // fresh task per message was a pair of allocations for every byte of a
        // fader sweep. One task now waits, sees the deadline has moved, and
        // waits again - so a stream keeps the lamp on with a task per flash
        // rather than a task per message.
        litUntil = .now + Self.flashDuration
        guard flashTask == nil else { return }
        flashGeneration &+= 1
        let token = flashGeneration
        flashTask = Task { [weak self] in
            while let deadline = self?.litUntil, .now < deadline {
                try? await Task.sleep(until: deadline)
                if Task.isCancelled { break }
            }
            // Only if this is still the flash in charge. `clear` can cancel
            // this one and a message can start another before this line is
            // reached, and tidying up then would put out the new one's lamp
            // and drop its handle.
            guard let self, token == flashGeneration else { return }
            flashTask = nil
            inputLit = false
        }
    }

    /// Which flash is in charge - see the check at the end of the task.
    @ObservationIgnored private var flashGeneration = 0

    /// When the lamp is next due to go out. Pushed forward by each message; the
    /// one waiting task reads it rather than being replaced.
    @ObservationIgnored private var litUntil: ContinuousClock.Instant = .now

    /// Adds a batch of lines in **one** mutation.
    ///
    /// One at a time is one observation notification per message, and every
    /// Monitor and LED on the canvas re-evaluates for each of them. A burst
    /// arrives together and may as well be announced together.
    private func append(_ newLines: [String]) {
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > Self.historyLimit + Self.historySlack {
            lines.removeFirst(lines.count - Self.historyLimit)
        }
    }

    func clear() {
        lines.removeAll()
        events.removeAll()
        sentLines.removeAll()
        sentCount = 0
        receivedCount = 0
        flashTask?.cancel()
        // Cleared as well as cancelled: `flash` starts a task only when there
        // is none, so leaving a dead one here would keep the lamp from ever
        // lighting again. The generation moves too, so the cancelled task
        // cannot tidy up after whatever starts next.
        flashTask = nil
        flashGeneration &+= 1
        inputLit = false
    }
}

/// One event before it has an id or a timestamp - what the engine hands
/// `MIDIActivity.record`.
///
/// A separate type rather than a half-filled `MIDIEvent`: the id is a running
/// number and the time is read once per batch, and both are the recorder's
/// business rather than the caller's.
nonisolated struct MIDIEventParts: Sendable {
    let direction: MIDIEvent.Direction
    let form: MIDIEvent.Form
    let kind: MIDIEvent.Kind
    let channel: Int?
    let device: String?
    let text: String
    var bytes: [UInt8] = []
}

extension MIDIEventParts {
    /// A message as it arrived on the wire.
    ///
    /// The text is `RawMIDIMessage`'s own, with one exception: a SysEx is
    /// spelled out in hex here, where that description says only "SysEx 42
    /// bytes". Both are right for their reader - a six-line tile on a panel
    /// cannot carry a forty-two byte dump, and a log window is exactly where
    /// someone has gone looking for one - so the window renders it rather
    /// than changing what the tile shows.
    static func raw(_ message: RawMIDIMessage,
                    direction: MIDIEvent.Direction,
                    device: String?) -> MIDIEventParts {
        MIDIEventParts(
            direction: direction, form: .raw,
            kind: .of(status: message.status),
            channel: message.channel, device: device,
            text: message.isSystemExclusive ? hex(message.bytes) : message.description,
            bytes: message.bytes
        )
    }

    /// A message as the decoder read it.
    ///
    /// No bytes: a reassembled NRPN was never on the wire in this shape, and
    /// attaching the bytes of the last of the four Control Changes that made
    /// it would be worse than attaching none.
    static func decoded(_ message: IncomingMessage,
                        direction: MIDIEvent.Direction,
                        device: String?) -> MIDIEventParts {
        MIDIEventParts(
            direction: direction, form: .decoded,
            kind: .of(incoming: message.kind),
            // A SysEx carries no channel; `IncomingMessage` stores 0 there,
            // and printing that as "CH0" would name a channel that does not
            // exist - MIDI counts from 1.
            channel: message.kind == .systemExclusive ? nil : message.channel,
            device: device,
            text: message.description
        )
    }

    /// Something the panel sent, in both forms.
    ///
    /// Outbound has the same two readings as inbound, arrived at from the
    /// other side: the bytes that actually went out, and the planner's own
    /// labelled account of them - "CC 74 = 100  (Cutoff)", where the label is
    /// the part worth reading. Both, so that neither view of the window is
    /// silently missing half the traffic.
    static func sent(_ message: MIDIMessage, device: String?) -> [MIDIEventParts] {
        let bytes = message.bytes
        let kind = bytes.first.map { MIDIEvent.Kind.of(status: $0) } ?? .other
        var parts: [MIDIEventParts] = []
        if let status = bytes.first {
            // Rebuilt as a raw message so the wire form is described by the
            // one function that describes wire forms.
            parts.append(.raw(RawMIDIMessage(status: status, data: Array(bytes.dropFirst())),
                              direction: .tx, device: device))
        }
        parts.append(MIDIEventParts(
            direction: .tx, form: .decoded, kind: kind,
            channel: message.channel, device: device,
            text: message.description
        ))
        return parts
    }

    /// A System Real Time byte, which the stream parser drops before anything
    /// downstream can see it. Raw by nature: there is nothing to decode.
    static func realtime(_ status: UInt8,
                         direction: MIDIEvent.Direction,
                         device: String?) -> MIDIEventParts {
        MIDIEventParts(
            direction: direction, form: .raw, kind: .realtime,
            channel: nil, device: device,
            text: MIDIEvent.realtimeName(status), bytes: [status]
        )
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
