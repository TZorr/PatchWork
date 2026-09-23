//
//  MIDIEngine.swift
//  PatchWork
//
//  The CoreMIDI side: the client, the ports, which endpoints exist, and
//  putting bytes on the wire. Direct CoreMIDI, no wrapper library - which is
//  the whole reason this port exists.
//
//  Three roles, and **two separate input ports** for the two listening ones:
//
//      Output      where everything goes.
//      Input       one device, the one being edited. Never forwarded.
//      Controller  any number of keyboards or fader boxes. Forwarded to the
//                  Output, which is why they exist.
//
//  Two ports rather than one with a role check, because the routing rule is
//  what the whole arrangement is *for* (see MIDIThru): the input read block
//  contains no forwarding call at all, so In → Out is not a path that is
//  disabled somewhere - it is a path that does not exist. A check could be
//  got wrong by a later edit; a missing call cannot.
//
//  Uses Observation rather than SwiftUI so the whole engine can be compiled
//  and driven by a test harness that talks to virtual endpoints - which is
//  how both directions get verified on a machine with no MIDI hardware.
//

import CoreAudio
import CoreMIDI
import Foundation
import Observation
import os

/// The clock CoreMIDI schedules against.
///
/// A `MIDITimeStamp` is mach absolute time - the same monotonic tick
/// `AudioGetCurrentHostTime` reads - not seconds and not a wall clock. A
/// packet stamped with a future one is *delivered* at that moment by the
/// driver rather than when it was handed over, which is what lets the file
/// player put a run of events on the wire ahead of time and still have them
/// sound when the file says (see MIDIPlayer).
///
/// Its own type rather than two loose calls, because the conversion is the
/// one place a factor-of-a-billion mistake would be silent: everything else
/// in this app measures time in seconds.
nonisolated enum MIDIHostClock {
    /// Now, in the units a timestamp is expressed in.
    static var now: MIDITimeStamp { AudioGetCurrentHostTime() }

    /// `seconds` as a number of ticks to add to a timestamp. Negative
    /// intervals come back as zero: a packet cannot be scheduled into the
    /// past, and wrapping an unsigned subtraction round would schedule it
    /// roughly twenty-four thousand years into the future instead.
    static func ticks(_ seconds: TimeInterval) -> MIDITimeStamp {
        guard seconds > 0 else { return 0 }
        return AudioConvertNanosToHostTime(UInt64(seconds * 1_000_000_000))
    }

    /// How long it is from `origin` until now, in seconds - negative while
    /// `origin` is still ahead, which it is for the lead-in.
    ///
    /// Signed, and that is the point: timestamps are unsigned, so the
    /// subtraction has to be done in the right order and the sign put back
    /// afterwards. Done the other way round, a moment a millisecond early
    /// reads as several thousand years late.
    static func elapsed(since origin: MIDITimeStamp) -> TimeInterval {
        let now = self.now
        let magnitude = TimeInterval(
            AudioConvertHostTimeToNanos(now >= origin ? now &- origin : origin &- now)
        ) / 1_000_000_000
        return now >= origin ? magnitude : -magnitude
    }
}

/// Where raw bytes go, and the port they leave by - resolved once and then
/// carried, rather than looked up per message.
///
/// `MIDIPortRef` and `MIDIEndpointRef` are both `MIDIObjectRef`, which is a
/// `UInt32`, so this is two integers: trivially Sendable, and safe to hand to
/// a task that will use it for the length of a file. The *resolution* is what
/// is main-actor work - `destinations` is engine state - and doing it once per
/// event meant doing that work on the thread that draws the panel.
nonisolated struct MIDIOutput: Sendable, Equatable {
    let port: MIDIPortRef
    let endpoint: MIDIEndpointRef
}

/// Bytes onto the wire, from wherever the caller happens to be.
///
/// A `nonisolated enum` for the same reason as MIDIHostClock above: this is
/// not engine *state*, it is what one does with a port and an endpoint, and
/// the file player's refill task has as much business doing it as the main
/// actor has. `MIDISend` is thread-safe by CoreMIDI's own contract.
///
/// The one thing in here that was not safe to do from anywhere is how it
/// complained: `fail` writes `lastError`, which is main-actor state. So a
/// failure stops being a call and becomes a return value, and whoever is on
/// the main actor decides what to do with it. The strings are the ones the
/// engine has always produced - nothing a person reads changes with this.
nonisolated enum MIDIWire {
    /// How much of a long message goes in one packet, and so in one send.
    ///
    /// This used to be 256, the old hard ceiling - wrong about real gear
    /// rather than cautious. A microKORG patch is 297 bytes, a minilogue All
    /// Dump's longest message 522, a microKORG LFO store one message of
    /// 37,163; every one was rejected, and a .mid carrying a bulk dump took
    /// the file player down with it.
    ///
    /// The declared 256 is not a real limit - `MIDIPacket.data` is a
    /// variable-length trailing array - but `MIDIPacket.length` (`UInt16`)
    /// is, and it is not enforced: 100,000 bytes handed to
    /// `MIDIPacketListAdd` in chunks returns success every time and leaves a
    /// packet claiming 34,464 bytes, the length silently wrapped, two thirds
    /// of the dump gone with no error. 4096 is far below that and a
    /// comfortable unit of work; a 37KB store goes out as ten sends.
    ///
    /// The layout's own Chunk setting is a smaller unit for the device's
    /// sake (see SysExTransfer); this is the ceiling neither it nor anything
    /// else may pass, the same number by definition, not coincidence.
    static let packetBytes = SysExTransfer.maxChunkBytes

    /// Why a send did not happen, in the words the engine has always used.
    enum Failure: Error, Sendable {
        case nothingToSend
        case oversizedNonSysEx(Int)
        case couldNotPack(Int)
        case sendFailed(OSStatus)

        var complaint: String {
            switch self {
            case .nothingToSend:
                "Nothing to send."
            case .oversizedNonSysEx(let count):
                "A \(count)-byte message that is not SysEx cannot be sent."
            case .couldNotPack(let count):
                "Could not pack \(count) bytes for sending."
            case .sendFailed(let status):
                "MIDISend failed (OSStatus \(status))."
            }
        }
    }

    /// One message -> the packets it goes out as.
    ///
    /// **Splitting is for SysEx and nothing else**, whatever the limit says.
    /// Every other MIDI message is at most three bytes; one that arrived here
    /// longer than a packet would not be a message to split but a bug to
    /// report, and cutting it in half would put a fragment on the wire rather
    /// than say so.
    static func chunked(_ bytes: [UInt8], limit: Int) throws(Failure) -> [[UInt8]] {
        guard !bytes.isEmpty else { throw .nothingToSend }
        guard bytes.first == SysEx.start else {
            guard bytes.count <= packetBytes else { throw .oversizedNonSysEx(bytes.count) }
            return [bytes]
        }
        guard bytes.count > limit else { return [bytes] }
        return stride(from: 0, to: bytes.count, by: limit).map {
            Array(bytes[$0..<min($0 + limit, bytes.count)])
        }
    }

    /// Puts one message on the wire, in as many packets as it takes.
    ///
    /// One `MIDISend` per chunk rather than one list of several, because
    /// CoreMIDI *coalesces* same-timestamp packets within a list - adding in
    /// pieces just rebuilds the one oversized packet the `UInt16` cannot
    /// describe. Separate sends are what actually keeps them apart. They carry
    /// the same timestamp, since the message is one event however many packets
    /// carry it, and they arrive in order because they are issued in order on
    /// one port by one caller.
    static func send(_ bytes: [UInt8], to output: MIDIOutput,
                     at timeStamp: MIDITimeStamp) throws(Failure) {
        for unit in try chunked(bytes, limit: packetBytes) {
            try sendOnePacket(unit, to: output, at: timeStamp)
        }
    }

    /// Sends, and answers the complaint rather than throwing it.
    ///
    /// What a caller with no `lastError` to write wants: the file player's
    /// task has nowhere to put an error and only something to say. Here rather
    /// than written out at the call site because typed throws are not inferred
    /// through a closure whose type is still being worked out.
    static func complaint(sending bytes: [UInt8], to output: MIDIOutput,
                          at timeStamp: MIDITimeStamp) -> String? {
        do {
            try send(bytes, to: output, at: timeStamp)
            return nil
        } catch {
            return error.complaint
        }
    }

    /// One packet, in one `MIDISend`.
    ///
    /// Built through `MIDIPacketListAdd` into a buffer sized for the job,
    /// rather than `MIDIPacketList(numPackets:packet:)`, whose initialiser
    /// copies into the struct's own inline storage - exactly where the old
    /// 256 came from.
    ///
    /// **A stack allocation, not a heap one.** A dense window of a file is
    /// hundreds of events, and this used to be a malloc and a free for each,
    /// on the main thread; for the three-byte messages a file is almost
    /// entirely made of, the block now costs nothing.
    ///
    /// A single buffer reused for a whole run would save the same work, but
    /// it would have to be threaded through every signature and could not be
    /// Sendable - the compiler cannot prove only one task writes to it. This
    /// promises nothing because it shares nothing.
    static func sendOnePacket(_ bytes: [UInt8], to output: MIDIOutput,
                              at timeStamp: MIDITimeStamp) throws(Failure) {
        guard bytes.count <= packetBytes else { throw .oversizedNonSysEx(bytes.count) }
        // Generously: the packet costs a timestamp, a length and whatever
        // padding the layout wants, and over-allocating a few dozen bytes for
        // one send is not worth being clever about.
        let capacity = MemoryLayout<MIDIPacketList>.size + bytes.count + 64
        let status: OSStatus? = withUnsafeTemporaryAllocation(
            byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment
        ) { buffer -> OSStatus? in
            let list = buffer.baseAddress!.bindMemory(to: MIDIPacketList.self, capacity: 1)
            let start = MIDIPacketListInit(list)
            let packet = MIDIPacketListAdd(list, capacity, start, timeStamp, bytes.count, bytes)
            // A full buffer comes back as a null pointer, which this SDK
            // imports as non-optional - so the bit pattern is what says
            // whether it took.
            guard UInt(bitPattern: packet) != 0 else { return nil }
            return MIDISend(output.port, output.endpoint, list)
        }
        guard let status else { throw .couldNotPack(bytes.count) }
        guard status == noErr else { throw .sendFailed(status) }
    }
}

/// Which listening role a message arrived in. A set, because one device can
/// be both: a synth chosen as the Input *and* as a Controller is heard once
/// and wearing two hats.
///
/// It travels with the message because the two roles no longer differ in what
/// they do with it - both move the controls it addresses - only in what else
/// happens: a Controller reaches the Output, and only a Controller feeds Learn.
nonisolated struct MIDIRoles: OptionSet, Sendable {
    let rawValue: Int
    static let input = MIDIRoles(rawValue: 1 << 0)
    static let controller = MIDIRoles(rawValue: 1 << 1)
}

/// One thing we can send to or listen to. The same shape either way -
/// CoreMIDI endpoints differ in direction, not in how they are identified.
struct MIDIEndpointInfo: Identifiable, Hashable {
    /// CoreMIDI's own unique id, which survives re-enumeration where an
    /// index does not - a device unplugged mid-session would otherwise
    /// silently shift every port after it.
    let id: Int32
    let name: String
    let endpoint: MIDIEndpointRef
}

@Observable
final class MIDIEngine {
    /// Everything currently connected. Re-read rather than cached across
    /// changes; CoreMIDI notifies us and we ask again.
    private(set) var destinations: [MIDIEndpointInfo] = []
    /// Everything we could listen to. One list, for both listening roles -
    /// a source is not an Input or a Controller by nature, it becomes one by
    /// being chosen as one.
    private(set) var sources: [MIDIEndpointInfo] = []
    /// Which one we send to, by unique id. Nil is a real state, not an
    /// error: a fresh layout has nothing chosen.
    private(set) var selectedDestinationID: Int32?
    /// The device being edited. One, because "the device this panel is for"
    /// is one device.
    private(set) var selectedSourceID: Int32?
    /// The controllers, all of them at once. A set rather than one id: a
    /// keyboard and a fader box are a perfectly ordinary pair, and neither
    /// is more the controller than the other.
    private(set) var selectedControllerIDs: Set<Int32> = []
    /// The noticeboard every display element reads.
    /// The shared noticeboard.
    ///
    /// Handed in rather than made here: the MIDI Monitor lives in a window of
    /// its own, which can reach no editor's `@State`, so the app owns one
    /// board and gives it to whoever needs it. Defaulted, so every existing
    /// caller - previews, the verification harness - is unchanged.
    let activity: MIDIActivity
    /// The one file player, for the same reason.
    let player = MIDIPlayer()
    /// What went wrong last, if anything - surfaced rather than swallowed,
    /// since a silent MIDI failure is the worst kind.
    private(set) var lastError: String?
    /// How fast bytes may leave - see SysExTransfer.
    ///
    /// Held by the engine rather than by the view because sending is what it
    /// governs, and read back out by ContentView when a layout is saved: it
    /// belongs to the panel, exactly as the chosen ports do.
    var transfer = SysExTransfer()

    /// The chosen destination's name, or nil. The Status element's OUT row.
    var selectedDestinationName: String? {
        destinations.first { $0.id == selectedDestinationID }?.name
    }

    /// The chosen input's name, or nil. The Status element's IN row.
    var selectedSourceName: String? {
        sources.first { $0.id == selectedSourceID }?.name
    }

    /// Every chosen controller's name, in the order the sources are listed
    /// so the CTRL row does not reshuffle itself as they connect.
    var selectedControllerNames: [String] {
        sources.filter { selectedControllerIDs.contains($0.id) }.map(\.name)
    }

    /// Everything the display elements read, in one value to hand down the
    /// canvas. See MIDIStatus.
    var status: MIDIStatus {
        MIDIStatus(
            outputName: selectedDestinationName,
            inputName: selectedSourceName,
            controllerNames: selectedControllerNames,
            activity: activity,
            player: player
        )
    }

    /// Called on the main actor with everything one callback decoded, after
    /// the noticeboard has it, tagged with the role or roles it arrived in.
    ///
    /// A callback rather than a published "latest messages" property: what
    /// arrives is an *event*, and a control moved by it is a write into the
    /// layout - storing the last batch where a view could observe it would
    /// let a redraw re-apply it.
    ///
    /// **Not a routing path.** A Controller reaches the Output only through
    /// the raw thru inside `receiveController`; this is for reading a value
    /// or address off a message, and sending from here would be a second,
    /// decoded route to the Out - what the thru is written to avoid.
    ///
    /// One callback for both roles: both move the elements they address, so
    /// the panel follows either one.
    @ObservationIgnored var onDecoded: (([IncomingMessage], MIDIRoles) -> Void)?

    /// Called when a handshake transfer gives up part-way through.
    ///
    /// A callback rather than `lastError` alone, because this failure arrives
    /// *after* `send` has already returned true: the first chunk went out
    /// fine and the device stopped answering three chunks later. Nobody is
    /// looking at a return value by then, so the transfer has to speak up.
    @ObservationIgnored var onTransferFailed: ((String) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var outputPort = MIDIPortRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var controllerPort = MIDIPortRef()

    /// One source connected to one port. Keyed by both, because the same
    /// device may legitimately be chosen as Input *and* Controller (that is
    /// the one-device setup) and the two connections are then independent
    /// streams that must not share a parser.
    private struct StreamKey: Hashable {
        let source: Int32
        let port: MIDIPortRef
    }

    private struct Connection {
        let endpoint: MIDIEndpointRef
        /// The parser and decoder for this stream, and this stream only.
        ///
        /// A message can straddle packets and running status makes a data-only
        /// packet meaningful because of what came before, so two devices
        /// sharing one parser would complete each other's half-messages. The
        /// decoder is per-stream for the same kind of reason: it remembers an
        /// NRPN address, and two devices sending trios into one decoder would
        /// hand each other the wrong halves.
        var parser: MIDIStreamParser
        var decoder: MIDIDecoder
    }

    @ObservationIgnored private var connections: [StreamKey: Connection] = [:]

    /// The `srcConnRefCon` handed to CoreMIDI per source, so a read block can
    /// tell which device it is hearing. One per source, shared by both ports -
    /// the port already says which role it is.
    ///
    /// **Never freed.** A read block may be running on a CoreMIDI thread with
    /// this pointer in hand at the moment a source is disconnected, and
    /// deallocating it there would be a use-after-free to save four bytes. It
    /// is allocated once per source the app ever connects to, and reused.
    @ObservationIgnored private var tokens: [Int32: UnsafeMutablePointer<Int32>] = [:]

    @ObservationIgnored private let log = Logger(subsystem: "TZorr.PatchWork", category: "midi")

    init(activity: MIDIActivity = MIDIActivity()) {
        self.activity = activity
        start()
        refreshEndpoints()
    }

    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if controllerPort != 0 { MIDIPortDispose(controllerPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Creates the client and the three ports.
    ///
    /// Logged either way, and deliberately so: this app is sandboxed, and
    /// whether CoreMIDI is reachable from inside that sandbox is exactly
    /// the kind of thing that fails quietly and looks like "no devices".
    /// The log line distinguishes "nothing plugged in" from "not allowed".
    private func start() {
        let clientStatus = MIDIClientCreateWithBlock("PatchWork" as CFString, &client) { [weak self] notification in
            // **Which** notification matters. CoreMIDI sends far more than
            // "something was plugged in": a property written anywhere in the
            // system, a thru connection changed, a serial port changing hands.
            // Re-enumerating on all of them meant a DAW writing properties to
            // its own ports made this app walk every endpoint on the machine.
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
                break
            default:
                return
            }
            // CoreMIDI calls this on the run loop that created the client, so
            // hopping to the main actor is about our own state, not about
            // thread safety here.
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        guard clientStatus == noErr else {
            fail("Could not create the MIDI client (OSStatus \(clientStatus)).")
            return
        }

        let portStatus = MIDIOutputPortCreate(client, "PatchWork Out" as CFString, &outputPort)
        guard portStatus == noErr else {
            fail("Could not create the MIDI output port (OSStatus \(portStatus)).")
            return
        }

        // Both read blocks run on a CoreMIDI thread, so everything they touch
        // hops to the main actor - and each hops ONCE per callback with the
        // whole packet list, rather than once per message: a fader sweep is a
        // burst, and a hop each would be a lot of scheduling to no purpose.
        //
        // The Input's block. Note what is not in it: any call that sends.
        let inputStatus = MIDIInputPortCreateWithBlock(client, "PatchWork In" as CFString, &inputPort) { [weak self] list, refCon in
            guard let source = refCon?.load(as: Int32.self) else { return }
            let bytes = list.midiBytes
            guard !bytes.isEmpty else { return }
            Task { @MainActor [weak self] in self?.receiveInput(bytes, from: source) }
        }
        guard inputStatus == noErr else {
            fail("Could not create the MIDI input port (OSStatus \(inputStatus)).")
            return
        }

        // The Controller's block - the mirror image, and the only one that
        // reaches the Output.
        let controllerStatus = MIDIInputPortCreateWithBlock(client, "PatchWork Ctrl" as CFString, &controllerPort) { [weak self] list, refCon in
            guard let source = refCon?.load(as: Int32.self) else { return }
            let bytes = list.midiBytes
            guard !bytes.isEmpty else { return }
            Task { @MainActor [weak self] in self?.receiveController(bytes, from: source) }
        }
        guard controllerStatus == noErr else {
            fail("Could not create the MIDI controller port (OSStatus \(controllerStatus)).")
            return
        }

        log.info("CoreMIDI client and three ports created (out, in, ctrl)")
    }

    // ── Listening ────────────────────────────────────────────────────────

    /// The Input: the device being edited, reporting itself back.
    ///
    /// **Forwards nothing on its own** - routing is the Controller's
    /// assignment and only that. Choosing a Controller says "send this
    /// device's playing to the Output"; leaving it unchosen says do not, and
    /// an Input that quietly forwarded anyway would take that switch away.
    ///
    /// When the same device is *also* a Controller there is one connection,
    /// not two (see `connect`), so the Controller's half of the job happens
    /// here: same rule, same filter, just arriving down the one wire there is.
    private func receiveInput(_ bytes: [UInt8], from source: Int32) {
        let key = StreamKey(source: source, port: inputPort)
        recordRealtime(bytes, from: source, direction: .rx)
        let raw = parse(bytes, from: key)
        guard !raw.isEmpty else { return }

        let shared = selectedControllerIDs.contains(source)
        // Before the decode, exactly as in the Controller's own path: the
        // order is the rule, not the place it is written.
        if shared { forwardToOutput(raw) }

        // **Any SysEx counts as the reply a handshake is waiting for.**
        // Reading it properly would mean telling a Roland ACK from a Kawai
        // one from a Yamaha "rejected", and the byte that would say which is
        // gone by the next line anyway - the decoder keeps a SysEx's length
        // and throws its contents away (see MIDIInput). What is actually
        // being waited on is the device coming back up for air, and that it
        // said anything at all is that answer. A device that answers with a
        // complaint is a device that answered, and it is the retry count and
        // the timeout that catch one which does not.
        if ackContinuation != nil, raw.contains(where: \.isSystemExclusive) {
            resumeACK(true)
        }

        let decoded = decoded(raw, on: key)
        guard !decoded.isEmpty else { return }
        // The noticeboard first, and unconditionally: logging it, counting it
        // and lighting the lamp write nothing into the layout, and knowing
        // the cable works is most useful exactly while a panel is still
        // being built. Whether anything *moves* is the mode's business.
        //
        // Once, not once per role - counting a shared device twice and
        // showing every message of it twice is exactly what one connection
        // is for.
        activity.recordReceived(decoded)
        // And the Monitor window's own record, which wants both readings and
        // the bytes - see MIDIEvent. Skipped entirely when no window is open,
        // so the line above is still all this path costs by default.
        if activity.isCapturing {
            let name = sources.first { $0.id == source }?.name
            activity.record(raw.map { .raw($0, direction: .rx, device: name) }
                            + decoded.map { .decoded($0, direction: .rx, device: name) })
        }
        onDecoded?(decoded, shared ? [.input, .controller] : [.input])
    }

    /// The Controller: forwarded to the Output, then shown.
    ///
    /// Forwarded **first, and independently of any decoding**, which is the
    /// one thing this must not get wrong: a decoder swallows CC 99 and
    /// CC 98 because they carry an address rather than a value, so
    /// a thru hanging off a decoder's result would send an NRPN's data entry
    /// with no address in front of it - landing the value on whatever
    /// parameter the device happened to have selected. What is forwarded here
    /// is what arrived, in the order it arrived.
    private func receiveController(_ bytes: [UInt8], from source: Int32) {
        let key = StreamKey(source: source, port: controllerPort)
        recordRealtime(bytes, from: source, direction: .ctrl)
        let raw = parse(bytes, from: key)
        guard !raw.isEmpty else { return }
        // The thru first, and from the raw messages - before anything is
        // decoded and independent of what decoding makes of them. See
        // MIDIThru: a decoder swallows an NRPN's address pair, so a thru
        // taken from its output would send the value with no address in
        // front of it.
        forwardToOutput(raw)
        activity.recordController(raw)
        // Then, separately, decoded - for Learn, which wants one NRPN rather
        // than the three Control Changes that carried it, and for the controls
        // it addresses.
        if activity.isCapturing {
            let name = sources.first { $0.id == source }?.name
            activity.record(raw.map { .raw($0, direction: .ctrl, device: name) })
        }
        guard onDecoded != nil || activity.isCapturing else { return }
        let decoded = decoded(raw, on: key)
        if activity.isCapturing {
            let name = sources.first { $0.id == source }?.name
            activity.record(decoded.map { .decoded($0, direction: .ctrl, device: name) })
        }
        if !decoded.isEmpty { onDecoded?(decoded, [.controller]) }
    }

    /// Clock, Start/Stop and Active Sensing, for the Monitor window only.
    ///
    /// Taken off the byte stream *before* the parser, because the parser drops
    /// everything from 0xF8 up on purpose (see MIDIStreamParser.feed) - they
    /// arrive constantly and would drown a six-line Monitor tile. That
    /// judgement stands for the panel and for the thru, both of which are
    /// untouched here. A tool window is the one place the question "is clock
    /// arriving at all" can be asked, and it has a filter to switch them off
    /// again - which is where they start.
    ///
    /// Nothing but a boolean when no window is open, like every other
    /// recording call on this path.
    private func recordRealtime(_ bytes: [UInt8], from source: Int32,
                                direction: MIDIEvent.Direction) {
        guard activity.isCapturing else { return }
        let realtime = bytes.filter { $0 >= 0xF8 }
        guard !realtime.isEmpty else { return }
        let name = sources.first { $0.id == source }?.name
        activity.record(realtime.map { .realtime($0, direction: direction, device: name) })
    }

    /// The Monitor window's record of what went out.
    ///
    /// Its own method because both send paths reach it and because of the
    /// guard: a live knob turn calls the sender sixty times a second, and with
    /// no window open this must cost a boolean and nothing else. Same reason
    /// the paced-only `log.info` beside the callers exists.
    private func recordSentEvents(_ messages: [MIDIMessage], to destination: MIDIEndpointInfo) {
        guard activity.isCapturing else { return }
        activity.record(messages.flatMap { MIDIEventParts.sent($0, device: destination.name) })
    }

    /// Feeds one stream's own parser. Bytes for a connection that is already
    /// gone are dropped: a callback can be in flight while a source is being
    /// disconnected, and a message that arrives after that should not be
    /// forwarded on the strength of having been sent slightly earlier.
    private func parse(_ bytes: [UInt8], from key: StreamKey) -> [RawMIDIMessage] {
        // Through the subscript rather than lifted out and put back. Copying
        // the Connection into a local leaves the dictionary holding the same
        // parser buffers, so the first append to a part-built SysEx copies the
        // whole thing - and a bulk dump arrives over dozens of callbacks.
        // Measured, that copying is not what dominates at the sizes real gear
        // sends; the accumulation stays linear either way. It is done in place
        // because `Dictionary.subscript` offers `_modify` and there is no
        // reason to take the copy, not because it was ever the bottleneck.
        guard connections[key] != nil else { return [] }
        return connections[key]!.parser.feed(bytes)
    }

    /// What the messages meant, through this stream's own decoder.
    private func decoded(_ raw: [RawMIDIMessage], on key: StreamKey) -> [IncomingMessage] {
        guard connections[key] != nil else { return [] }
        return raw.compactMap { connections[key]!.decoder.decode($0) }
    }

    /// Controller → Out.
    ///
    /// Errors are logged, not surfaced: a failed send means the device is
    /// gone, and a keyboard being played would otherwise stack up a dialog
    /// per note.
    private func forwardToOutput(_ messages: [RawMIDIMessage]) {
        // Resolved once for the batch, not per message.
        guard let output = currentOutput else { return }
        // Asked per message rather than once for the lot: what may go out is
        // a property of each message, so a batch carrying a note, a CC and a
        // SysEx is filtered rather than accepted or refused as a whole.
        for message in messages where MIDIThru.forwards(message) {
            // Straight to the packet. A forwarded message is a channel message
            // - three bytes at most, never a SysEx - so the chunking step has
            // nothing to decide and would only allocate an array to hold one.
            do {
                try MIDIWire.sendOnePacket(message.bytes, to: output, at: 0)
            } catch {
                fail(error.complaint)
                return
            }
        }
    }

    // ── Endpoints ────────────────────────────────────────────────────────

    /// The names the user picked, which is not the same as what is open.
    ///
    /// A device that is unplugged keeps being *wanted* - only its connection
    /// goes - so plugging it back in picks it up again without anyone
    /// touching a menu. Names rather than unique ids because that is what is
    /// remembered between sessions (see AppSettings) and what a person would
    /// recognise.
    private(set) var wantedOutputName: String?
    private(set) var wantedInputName: String?
    private(set) var wantedControllerNames: Set<String> = []

    /// Whether a refresh is already on its way, so a burst of notifications
    /// costs one enumeration rather than one each.
    @ObservationIgnored private var refreshPending = false

    /// Asks for a refresh, coalescing a burst into one.
    ///
    /// A DAW starting publishes its ports one at a time, so this arrives ten or
    /// twenty times in a row - and every one of them used to walk every
    /// endpoint on the machine, twice, on the thread that draws the panel.
    /// Whatever the last notification in a burst would have found, one refresh
    /// after the burst finds too.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { @MainActor [weak self] in
            self?.refreshPending = false
            self?.refreshEndpoints()
        }
    }

    /// Re-reads what is connected, then opens exactly the ports the roles
    /// need. CoreMIDI tells us something changed and we ask again.
    func refreshEndpoints() {
        let foundDestinations = endpoints(count: MIDIGetNumberOfDestinations(), at: MIDIGetDestination)
        let foundSources = endpoints(count: MIDIGetNumberOfSources(), at: MIDIGetSource)
        // Assigned only when they differ. Observation has no equality check of
        // its own, and ContentView's body reads both lists - so re-assigning an
        // identical list repainted the whole canvas. Most notifications in a
        // busy setup change nothing that this app can see.
        let changed = foundDestinations != destinations || foundSources != sources
        if changed {
            destinations = foundDestinations
            sources = foundSources
        }
        // Reconciled either way, and deliberately: the Rescan button in the
        // port menus comes through here, and it is pressed precisely when
        // something *should* be connected and is not. Skipping this when the
        // list happens to be unchanged would make that button do nothing.
        // It is cheap when there is nothing to do - every assignment inside it
        // sits behind a test.
        reconcile()
        guard changed else { return }
        log.info("MIDI out: \(self.destinations.count, privacy: .public) [\(self.destinations.map(\.name).joined(separator: ", "), privacy: .public)] in: \(self.sources.count, privacy: .public) [\(self.sources.map(\.name).joined(separator: ", "), privacy: .public)]")
    }

    /// Brings what is open into line with what is wanted.
    ///
    /// Incremental rather than a teardown and rebuild: this runs on every
    /// CoreMIDI notification, including ones caused by other applications'
    /// ports appearing, and
    /// rebuilding every connection each time would throw away a half-read
    /// message and a half-built NRPN address for something that had nothing
    /// to do with us.
    private func reconcile() {
        if let id = selectedDestinationID, !destinations.contains(where: { $0.id == id }) {
            // The device the file was playing to has gone. Stopped without
            // silencing, deliberately: there is no endpoint left to say it to,
            // and trying would only complain about the output being missing.
            // See `select` for the case where the device is still there and it
            // is the choice that changed.
            player.stop()
            selectedDestinationID = nil
        }
        if selectedDestinationID == nil, let name = wantedOutputName {
            selectedDestinationID = destinations.first { $0.name == name }?.id
        }

        if let id = selectedSourceID, !sources.contains(where: { $0.id == id }) {
            disconnect(source: id, from: inputPort)
            selectedSourceID = nil
        }
        if selectedSourceID == nil, let name = wantedInputName,
           let found = sources.first(where: { $0.name == name }) {
            connectInput(found)
        }

        for id in selectedControllerIDs where !sources.contains(where: { $0.id == id }) {
            disconnect(source: id, from: controllerPort)
            selectedControllerIDs.remove(id)
        }
        for name in wantedControllerNames {
            guard let found = sources.first(where: { $0.name == name }),
                  !selectedControllerIDs.contains(found.id) else { continue }
            if openControllerConnection(found.id) {
                selectedControllerIDs.insert(found.id)
            }
        }
    }

    private func endpoints(count: Int, at index: (Int) -> MIDIEndpointRef) -> [MIDIEndpointInfo] {
        (0..<count).compactMap { position in
            let endpoint = index(position)
            guard endpoint != 0 else { return nil }
            var uid: Int32 = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid) == noErr else { return nil }
            return MIDIEndpointInfo(id: uid, name: displayName(of: endpoint), endpoint: endpoint)
        }
    }

    func select(_ destination: MIDIEndpointInfo?) {
        // Before the selection moves, not after: the flush and the panic have
        // to reach the endpoint the file was actually playing to. Changing the
        // output mid-file used to split the stream between two devices and
        // leave every note the first one was holding held for good, because
        // the note-offs that would have ended them went to the second.
        if player.playing, destination?.id != selectedDestinationID {
            stopPlayback()
        }
        wantedOutputName = destination?.name
        selectedDestinationID = destination?.id
        lastError = nil
        log.info("MIDI output selected: \(destination?.name ?? "none", privacy: .public)")
    }

    /// Chooses the device being edited, disconnecting whatever it was.
    /// Passing nil just disconnects.
    func selectSource(_ source: MIDIEndpointInfo?) {
        if let current = selectedSourceID {
            disconnect(source: current, from: inputPort)
            // Cleared *before* reopening: openControllerConnection refuses a
            // source that is still the Input, so leaving it set here would
            // have it guard against the very thing being undone.
            selectedSourceID = nil
            // It was riding on this port; now it needs one of its own again.
            if selectedControllerIDs.contains(current) {
                openControllerConnection(current)
            }
        }
        selectedSourceID = nil
        wantedInputName = source?.name
        lastError = nil

        guard let source else {
            log.info("MIDI input selected: none")
            return
        }
        connectInput(source)
        log.info("MIDI input selected: \(source.name, privacy: .public)")
    }

    /// Opens the input's connection, taking the device off the controller
    /// port first if it was there.
    ///
    /// One endpoint, one connection: connecting the same source to both ports
    /// makes CoreMIDI deliver every message to both read blocks, and the app
    /// would then log it twice, count it twice and flash the lamp twice for
    /// one turn of one knob. The input port carries both roles instead - see
    /// `receiveInput`. Done in both directions (see `selectSource`) so the
    /// result cannot depend on which menu was touched first.
    private func connectInput(_ source: MIDIEndpointInfo) {
        disconnect(source: source.id, from: controllerPort)
        guard connect(source, to: inputPort, role: "input") else { return }
        selectedSourceID = source.id
    }

    /// Whether the Controller role is riding on the Input's own connection.
    var controllerSharesInput: Bool {
        guard let input = selectedSourceID else { return false }
        return selectedControllerIDs.contains(input)
    }

    /// Opens a controller connection for `id` unless the input port is
    /// already carrying it.
    @discardableResult
    private func openControllerConnection(_ id: Int32) -> Bool {
        guard id != selectedSourceID else { return true }
        guard let source = sources.first(where: { $0.id == id }) else { return false }
        return connect(source, to: controllerPort, role: "controller")
    }

    /// Adds or removes one controller, leaving the others alone.
    ///
    /// Per controller rather than "here is the new set", because that is what
    /// the menu does: a set-at-once API would make toggling one entry mean
    /// rebuilding the whole selection, and a stale copy of it would silently
    /// disconnect a device somebody else had just added.
    func setController(_ id: Int32, connected: Bool) {
        let name = sources.first { $0.id == id }?.name
        guard connected else {
            disconnect(source: id, from: controllerPort)
            selectedControllerIDs.remove(id)
            if let name { wantedControllerNames.remove(name) }
            log.info("MIDI controller disconnected: \(name ?? "unknown", privacy: .public)")
            return
        }
        guard !selectedControllerIDs.contains(id), let name else { return }
        // Nothing to open when it is already the Input: that connection
        // carries both roles. See controllerSharesInput.
        guard openControllerConnection(id) else { return }
        selectedControllerIDs.insert(id)
        wantedControllerNames.insert(name)
        lastError = nil
        let shared = id == selectedSourceID
        log.info("MIDI controller connected: \(name, privacy: .public)\(shared ? " (sharing the input's connection)" : "")")
    }

    func disconnectAllControllers() {
        for id in selectedControllerIDs { disconnect(source: id, from: controllerPort) }
        selectedControllerIDs.removeAll()
        wantedControllerNames.removeAll()
        log.info("MIDI controllers disconnected: all")
    }

    /// Wires one source to one port, tagged with the source's unique id so
    /// the read block knows which device it is hearing.
    private func connect(_ source: MIDIEndpointInfo, to port: MIDIPortRef, role: String) -> Bool {
        guard port != 0 else {
            fail("No MIDI \(role) port.")
            return false
        }
        let token = tokens[source.id] ?? {
            let fresh = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            fresh.initialize(to: source.id)
            tokens[source.id] = fresh
            return fresh
        }()
        let key = StreamKey(source: source.id, port: port)
        // The parser goes in before the connection is made, not after: a
        // message can arrive between those two moments, and one that found no
        // parser would be dropped.
        connections[key] = Connection(
            endpoint: source.endpoint, parser: MIDIStreamParser(), decoder: MIDIDecoder()
        )
        let status = MIDIPortConnectSource(port, source.endpoint, token)
        guard status == noErr else {
            connections[key] = nil
            fail("Could not listen to \(source.name) (OSStatus \(status)).")
            return false
        }
        return true
    }

    private func disconnect(source: Int32, from port: MIDIPortRef) {
        let key = StreamKey(source: source, port: port)
        guard let connection = connections.removeValue(forKey: key) else { return }
        MIDIPortDisconnectSource(port, connection.endpoint)
    }

    // ── Remembering ──────────────────────────────────────────────────────

    /// The port names to write into the settings.
    var portSettings: (output: String?, input: String?, controllers: [String]) {
        // Sorted so the stored list does not reshuffle itself between
        // sessions for no reason a diff could explain.
        (wantedOutputName, wantedInputName, wantedControllerNames.sorted())
    }

    /// Takes the remembered names and opens whatever of them is plugged in.
    ///
    /// Names that are not there are *kept*, not dropped: a rig that is
    /// switched on after the app is still the rig, and `reconcile` picks each
    /// device up as it appears.
    func restorePorts(output: String?, input: String?, controllers: [String]) {
        wantedOutputName = output
        wantedInputName = input
        wantedControllerNames = Set(controllers)
        reconcile()
        log.info("MIDI ports restored: out \(output ?? "none", privacy: .public), in \(input ?? "none", privacy: .public), ctrl [\(controllers.joined(separator: ", "), privacy: .public)]")
    }

    // ── Sending ──────────────────────────────────────────────────────────

    /// Sends the planned messages to the chosen destination, at the pace the
    /// layout asks for - see SysExTransfer.
    ///
    /// Everything is cut into units first: a long SysEx into chunks, every
    /// other message into one unit of its own. The break then falls between
    /// units, which is what makes a hundred-message Send All as gentle on a
    /// small buffer as one split dump.
    ///
    /// **`paced` is about what kind of send this is, not how big it is.** A
    /// live gesture passes false: a knob dragged across its range calls this
    /// sixty times a second, and spacing those out would build a backlog that
    /// went on arriving long after the hand had stopped. Such a send still has
    /// its own chunks spaced - one message's worth of gaps is bounded by that
    /// message - it simply gets no gap between messages and does not queue
    /// behind anything.
    ///
    /// Fixed Delay does its waiting with **timestamps rather than sleeps**,
    /// the same trick and for the same reason as the file player (see
    /// MIDIPlayer): every packet is handed over now, stamped with when it is
    /// due, and the driver releases them on time. So this stays synchronous,
    /// nothing blocks the main thread, and the Bool still means what it always
    /// meant. Handshake cannot work that way - it has to hear back between
    /// units - so that one runs as a task and reports late failures through
    /// `onTransferFailed`.
    @discardableResult
    func send(_ messages: [MIDIMessage], paced: Bool = true) -> Bool {
        guard !messages.isEmpty else { return true }
        guard outputPort != 0 else {
            fail("No MIDI output port.")
            return false
        }
        guard let destination = destinations.first(where: { $0.id == selectedDestinationID }) else {
            fail(destinations.isEmpty
                 ? "No MIDI outputs are available on this system."
                 : "No MIDI output is selected.")
            return false
        }

        // Which slot each unit waits for. Counted across the whole batch when
        // paced, and restarted at each message when not - that difference is
        // the whole of the live-gesture rule above.
        var units: [(bytes: [UInt8], slot: Int)] = []
        var slots = 0
        for message in messages {
            guard let chunks = chunked(message.bytes, limit: transfer.chunk) else { return false }
            for (index, chunk) in chunks.enumerated() {
                units.append((chunk, paced ? slots + index : index))
            }
            slots += chunks.count
        }

        if paced, transfer.strategy == .handshake, units.count > 1 {
            guard startHandshake(units.map(\.bytes), to: destination) else { return false }
            activity.recordSent(messages)
            recordSentEvents(messages, to: destination)
            log.info("handshake transfer started: \(units.count, privacy: .public) unit(s) to \(destination.name, privacy: .public)")
            return true
        }

        let gap = transfer.breakSeconds
        if gap <= 0 || (units.count == 1 && !paced) {
            // Nothing to pace: no gap asked for, or a single packet from a
            // live gesture. Straight out, which is what a knob turn wants and
            // what this did before any of these settings existed.
            //
            // A single packet from a *paced* send still goes through the
            // scheduling below, even though it has no gap of its own to wait
            // out: it has to queue behind whatever is still due, or a one-
            // element Send All would overtake the bulk transfer running ahead
            // of it and arrive out of order.
            for unit in units {
                guard sendOnePacket(unit.bytes, to: destination.endpoint, at: 0) else { return false }
            }
        } else {
            // Queued behind whatever is still due, so that two Send Alls in
            // quick succession follow each other rather than interleave -
            // which would hand the device exactly the burst the pacing is
            // there to prevent.
            let origin = paced ? max(MIDIHostClock.now, scheduledUntil) : MIDIHostClock.now
            for unit in units {
                let due = origin &+ MIDIHostClock.ticks(Double(unit.slot) * gap)
                guard sendOnePacket(unit.bytes, to: destination.endpoint, at: due) else { return false }
            }
            if paced { scheduledUntil = origin &+ MIDIHostClock.ticks(Double(slots) * gap) }
        }

        activity.recordSent(messages)
        recordSentEvents(messages, to: destination)
        // Logged only for the paced path - a Send All, a dump, the things worth
        // finding in a log afterwards. A live gesture calls this sixty times a
        // second, and a line each is a great deal of writing about a knob being
        // turned. The playback path is unlogged for the same reason.
        if paced {
            log.info("sent \(messages.count, privacy: .public) message(s) in \(units.count, privacy: .public) unit(s) to \(destination.name, privacy: .public)")
        }
        return true
    }

    /// Drops a handshake transfer in progress and clears the queue a paced
    /// send would otherwise line up behind.
    ///
    /// What Panic calls before it sends. A stop that waited for a bulk
    /// transfer to finish would not be a stop.
    ///
    /// It does not flush what CoreMIDI already holds: those packets are
    /// scheduled, and the same call that dropped them would drop the file
    /// player's lookahead window with them. See `flushOutput`, which the
    /// player's own stop uses for exactly that reason.
    func cancelTransfer() {
        handshakeTask?.cancel()
        // Resumed by hand, because a task suspended on this continuation is
        // not woken by cancellation - it would sit there for good, holding the
        // transfer open against every later send.
        resumeACK(false)
        scheduledUntil = 0
    }

    /// The output as it stands, or nil when there is nothing to send to.
    ///
    /// One place that resolves, where the same `first(where:)` used to be
    /// written out at each call site - including inside the file player's
    /// per-event path, which is the reason it was worth giving a name.
    var currentOutput: MIDIOutput? {
        guard outputPort != 0,
              let destination = destinations.first(where: { $0.id == selectedDestinationID })
        else { return nil }
        return MIDIOutput(port: outputPort, endpoint: destination.endpoint)
    }

    /// Puts bytes on the wire as they are.
    ///
    /// The one path that does not go through the planner: these were not
    /// built from an element, and re-deriving them would only risk getting
    /// them wrong. Not logged to the noticeboard either - the thru is
    /// thousands of messages an evening, and a Monitor showing all of them
    /// would show nothing else.
    ///
    /// `at` is when it should sound, on CoreMIDI's own clock (MIDIHostClock);
    /// zero means now. The file player used to come through here too, one
    /// message at a time with the destination resolved on each - it takes
    /// `playbackSink` below instead now, the same work done once.
    @discardableResult
    func sendRaw(_ bytes: [UInt8], at timeStamp: MIDITimeStamp = 0) -> Bool {
        guard let output = currentOutput else { return false }
        return send(bytes, to: output.endpoint, at: timeStamp)
    }

    /// A send for the file player's own task: port and endpoint looked up
    /// **once**, here, where `destinations` lives - not once per event on
    /// the thread that draws the panel.
    ///
    /// Nil back is a refusal to start - better than before, when a press
    /// with nothing selected began playing and only reported "sending
    /// failed" at its first event.
    ///
    /// The closure answers nil when the bytes went out and the complaint
    /// when they did not - not a Bool, since the reason used to reach
    /// `lastError` directly and now has to be carried back (see MIDIWire,
    /// `noteFailure` below).
    func playbackSink() -> (@Sendable ([UInt8], MIDITimeStamp) -> String?)? {
        guard let output = currentOutput else { return nil }
        // Captures nothing but two integers, which is what lets it be handed
        // to a task and used there for the length of a file.
        return { bytes, timeStamp in
            MIDIWire.complaint(sending: bytes, to: output, at: timeStamp)
        }
    }

    /// What stopping the file player has to do on the wire, in this order.
    ///
    /// The player schedules ahead - up to `MIDIPlayer.lookahead` of the file
    /// is already with CoreMIDI when a stop arrives - so the flush is what
    /// makes the stop immediate rather than a fifth of a second later. The
    /// panic then silences whatever the file was in the middle of, and has to
    /// come *after*: sent before the flush, it would be flushed away with the
    /// rest.
    ///
    /// Here rather than in ContentView, where this used to live, because the
    /// engine is what notices an output being changed or unplugged mid-file -
    /// and the panel is in no position to know that the wire needs silencing.
    func stopPlayback() {
        player.stop(silence: { [weak self] in self?.silencePlayback() })
    }

    /// The wire half of that, on its own.
    ///
    /// Separate from `stopPlayback` because the player needs to call it from
    /// inside its own stop, and from the end of a run that failed - both
    /// moments where stopping the player again would be stopping something
    /// that has already stopped.
    func silencePlayback() {
        // Only when the player actually has packets waiting. See
        // MIDIPlayer.hasPendingSchedule: `MIDIFlushOutput` takes a destination
        // and says nothing about whose packets it drops, and this app is
        // routinely pointed at a device a DAW is also using.
        if player.hasPendingSchedule { flushOutput() }
        // Ahead of whatever is queued: a silence that waited its turn behind a
        // bulk transfer would not be a silence.
        cancelTransfer()
        send(MIDIPlanner.panic(), paced: false)
    }

    /// Something failed away from here - the file player's own task, which
    /// does its sending off the main actor and cannot write this.
    ///
    /// Without it a playback failure would reach the alert and stop there,
    /// leaving `lastError` - which the Status element shows - still describing
    /// whatever had gone wrong before it.
    func noteFailure(_ complaint: String) { fail(complaint) }

    /// Drops everything scheduled but not yet sounded.
    ///
    /// The counterpart of scheduling ahead: the file player hands CoreMIDI a
    /// window of events *before* they are due, so stopping it has to take
    /// those back, or a stop would go quiet only once that window played
    /// itself out.
    ///
    /// **`MIDIFlushOutput` is endpoint-wide, and CoreMIDI offers no finer
    /// grain.** Stopping the player during a Fixed Delay transfer drops the
    /// rest of that transfer too, leaving the device half-programmed.
    /// `cancelTransfer` is built the other way round - it clears the queue
    /// *without* flushing, so it cannot take the player's window with it -
    /// but there is no way to tell the two apart from CoreMIDI's side.
    func flushOutput() {
        guard let output = currentOutput else { return }
        MIDIFlushOutput(output.endpoint)
    }


    /// Puts one message on the wire, in as many packets as it takes.
    ///
    /// **Splitting is for SysEx and nothing else.** A SysEx may be carried
    /// by any number of packets and is reassembled from the byte stream, so
    /// where the breaks fall does not matter. Every other MIDI message is at
    /// most three bytes; one longer than a packet is a bug to report, not a
    /// message to split.
    ///
    /// One `MIDISend` per chunk rather than one list, because CoreMIDI
    /// *coalesces* same-timestamp packets within a list - adding in pieces
    /// just rebuilds the one oversized packet the `UInt16` cannot describe.
    /// Separate sends keep them apart; they carry the same timestamp, since
    /// the message is one event, and arrive in order because they are
    /// issued in order on one port from the main actor.
    ///
    /// The raw path, and so unpaced: this carries the file player's own
    /// timing and the controller thru, neither the layout's to slow down.
    /// The planned path is `send(_:paced:)` above.
    ///
    /// The work is MIDIWire's, `nonisolated` so the file player can do
    /// exactly this from a task of its own. What stays here is turning a
    /// failure back into `lastError`, which only the main actor may write.
    private func send(_ bytes: [UInt8], to endpoint: MIDIEndpointRef,
                      at timeStamp: MIDITimeStamp = 0) -> Bool {
        guard outputPort != 0 else {
            fail("No MIDI output port.")
            return false
        }
        do {
            try MIDIWire.send(bytes, to: MIDIOutput(port: outputPort, endpoint: endpoint),
                              at: timeStamp)
            return true
        } catch {
            fail(error.complaint)
            return false
        }
    }

    /// One message -> the packets it goes out as, or nil for a message that
    /// cannot be sent at all (which has already been complained about).
    ///
    /// **Splitting is for SysEx and nothing else**, whatever the limit says.
    /// Every other MIDI message is at most three bytes; one that arrived here
    /// longer than a packet would not be a message to split but a bug to
    /// report, and cutting it in half would put a fragment on the wire rather
    /// than say so.
    private func chunked(_ bytes: [UInt8], limit: Int) -> [[UInt8]]? {
        do { return try MIDIWire.chunked(bytes, limit: limit) }
        catch { fail(error.complaint); return nil }
    }

    /// One packet, in one `MIDISend`.
    ///
    /// The building of it is MIDIWire's - nonisolated, because the file player
    /// does the same from its own task now. This is the main actor's way in,
    /// and what it adds is `fail`: the reason a send did not happen comes back
    /// as a value and is put where the Status element can read it.
    private func sendOnePacket(_ bytes: [UInt8], to endpoint: MIDIEndpointRef,
                               at timeStamp: MIDITimeStamp) -> Bool {
        guard outputPort != 0 else {
            fail("No MIDI output port.")
            return false
        }
        do {
            try MIDIWire.sendOnePacket(bytes, to: MIDIOutput(port: outputPort, endpoint: endpoint),
                                       at: timeStamp)
            return true
        } catch {
            fail(error.complaint)
            return false
        }
    }

    // ── Handshake ────────────────────────────────────────────────────────

    /// When the last paced send finishes putting its units on the wire, so the
    /// next one can queue behind it instead of on top of it.
    @ObservationIgnored private var scheduledUntil: MIDITimeStamp = 0
    /// The transfer in progress, if the strategy is Handshake. Fixed Delay
    /// needs no task: its whole timing is in the timestamps.
    @ObservationIgnored private var handshakeTask: Task<Void, Never>?
    /// The transfer waiting to hear back, if one is. Resumed by an arriving
    /// SysEx, by the timeout, or by `cancelTransfer`.
    @ObservationIgnored private var ackContinuation: CheckedContinuation<Bool, Never>?

    /// Starts a handshaking transfer, or explains why it cannot.
    ///
    /// Refused up front when there is no Input, rather than discovered one
    /// timeout at a time: the reply arrives on the Input port and nowhere
    /// else, so without one this would sit through every retry of every chunk
    /// before reporting a problem that was knowable at the first byte.
    private func startHandshake(_ units: [[UInt8]], to destination: MIDIEndpointInfo) -> Bool {
        guard selectedSourceID != nil else {
            fail("Handshake needs a MIDI Input: that is where the device's reply arrives.")
            return false
        }
        guard handshakeTask == nil else {
            fail("A handshake transfer is already running.")
            return false
        }
        let settings = transfer
        let endpoint = destination.endpoint
        handshakeTask = Task { @MainActor [weak self] in
            await self?.runHandshake(units, to: endpoint, settings: settings)
            // Cleared by the task itself and by nothing else, which is what
            // makes "one at a time" true: a cancel only asks it to stop, and
            // until it has, the guard above keeps the next one out.
            self?.handshakeTask = nil
        }
        return true
    }

    /// Unit, reply, unit - and the retries when the reply does not come.
    private func runHandshake(_ units: [[UInt8]], to endpoint: MIDIEndpointRef,
                              settings: SysExTransfer) async {
        let clock = ContinuousClock()
        for (index, unit) in units.enumerated() {
            var attempt = 0
            while true {
                if Task.isCancelled { return }
                guard sendOnePacket(unit, to: endpoint, at: 0) else {
                    onTransferFailed?(lastError ?? "The transfer failed.")
                    return
                }
                if await waitForACK(timeout: settings.timeout) { break }
                if Task.isCancelled { return }
                attempt += 1
                guard attempt <= settings.retryLimit else {
                    let complaint = "No reply after chunk \(index + 1) of \(units.count)"
                        + " - \(settings.retryLimit) retr\(settings.retryLimit == 1 ? "y" : "ies")"
                        + " of \(settings.timeoutMS) ms each."
                    fail(complaint)
                    onTransferFailed?(complaint)
                    return
                }
            }
            // After the reply rather than instead of it: with a handshake the
            // reply is what says the device is ready, and the break is only
            // the extra breathing space a protocol may still want. Which is
            // why its default of 10 ms is nearly nothing here, and why 0 is a
            // perfectly ordinary setting in this mode.
            if settings.breakSeconds > 0, index < units.count - 1 {
                try? await clock.sleep(for: .seconds(settings.breakSeconds))
            }
        }
    }

    /// Waits for the device to say something, or for the timeout.
    ///
    /// The wait and the deadline race each other, and `resumeACK` is what
    /// makes that safe: it hands the continuation back exactly once, whoever
    /// gets there first. Everything here is on the main actor, so "first" is
    /// a real order rather than a hope.
    private func waitForACK(timeout: Duration) async -> Bool {
        let deadline = Task { @MainActor [weak self] in
            try? await ContinuousClock().sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resumeACK(false)
        }
        let acknowledged = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            ackContinuation = continuation
        }
        deadline.cancel()
        return acknowledged
    }

    private func resumeACK(_ acknowledged: Bool) {
        guard let waiting = ackContinuation else { return }
        ackContinuation = nil
        waiting.resume(returning: acknowledged)
    }

    private func displayName(of endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr,
              let name = value?.takeRetainedValue() as String? else {
            return "Unknown"
        }
        return name
    }

    private func fail(_ message: String) {
        lastError = message
        log.error("\(message, privacy: .public)")
    }
}

extension UnsafePointer where Pointee == MIDIPacketList {
    /// Every byte in the list, in order, as one stream.
    ///
    /// One stream and not one array per packet, because a packet boundary
    /// means nothing: CoreMIDI coalesces messages sent close together into
    /// one packet and may split one across two. The parser finds the
    /// messages again.
    ///
    /// Read **through pointers, never through a copy of the packet**
    /// (formerly `var packet = pointee.packet` then
    /// `withUnsafeBytes(of: packet.data)`). A `MIDIPacket` value carries
    /// only the 256 bytes its struct declares, while a real packet's data
    /// runs on past that - so a message longer than 256 bytes was quietly
    /// cut and the rest of the list walked from the wrong place. A microKORG
    /// answering a dump request with 37,163 bytes was the case that found
    /// it.
    ///
    /// `nonisolated` because this runs on a CoreMIDI thread, inside a read
    /// block, before anything has hopped to the main actor.
    nonisolated var midiBytes: [UInt8] {
        var bytes: [UInt8] = []
        // Sized first. A multi-packet list otherwise grows the buffer as it
        // goes, reallocating and copying what it has each time - on a CoreMIDI
        // thread, where the whole job is to get out of the way quickly.
        var total = 0
        var counting = UnsafeRawPointer(self).advanced(by: MIDIPacketList.packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<pointee.numPackets {
            total += Int(counting.pointee.length)
            counting = UnsafePointer<MIDIPacket>(MIDIPacketNext(counting))
        }
        bytes.reserveCapacity(total)

        var packet = UnsafeRawPointer(self).advanced(by: MIDIPacketList.packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<pointee.numPackets {
            let length = Int(packet.pointee.length)
            let data = UnsafeRawPointer(packet).advanced(by: MIDIPacket.dataOffset)
            bytes.append(contentsOf: UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self), count: length
            ))
            // Spelled out, because inside this extension a bare
            // `UnsafePointer(...)` means a pointer to a MIDIPacketList.
            packet = UnsafePointer<MIDIPacket>(MIDIPacketNext(packet))
        }
        return bytes
    }
}

extension MIDIPacket {
    /// Where a packet's bytes start within it - past the timestamp and the
    /// length. Read off the layout rather than written as 10, so it stays
    /// right whatever the platform packs the struct to.
    nonisolated static let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
}

extension MIDIPacketList {
    /// Where the first packet starts within the list - past `numPackets`.
    nonisolated static let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
}
