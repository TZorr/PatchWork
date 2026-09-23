//
//  Verification/main.swift
//  PatchWork
//
//  A verification harness for the MIDI layer, kept because there is no
//  test target and because what it checks is not obvious by reading:
//  every planner case against checked-in reference output, the stream
//  parser and NRPN decoder against hand-built byte streams, and real bytes
//  through CoreMIDI in both directions - into a virtual destination and out
//  of a virtual source that the harness creates for itself, which is the
//  only way to test either direction on a machine with no MIDI hardware
//  attached.
//
//  The reference values throughout are captured output, embedded here
//  rather than recomputed: a number this harness works out for itself is a
//  number that agrees with whatever the code currently does.
//
//  Not part of the app target. Run it by compiling it with the sources it
//  exercises:
//
//      swiftc -default-isolation MainActor -strict-concurrency=complete \
//          -o /tmp/verify_midi \
//          Verification/main.swift \
//          PatchWork/MIDI/MIDIMessage.swift \
//          PatchWork/MIDI/MIDIEngine.swift \
//          PatchWork/MIDI/MIDIThru.swift \
//          PatchWork/MIDI/MIDIInput.swift \
//          PatchWork/MIDI/MIDIActivity.swift \
//          PatchWork/MIDI/MIDIStatus.swift \
//          PatchWork/MIDI/IncomingControl.swift \
//          PatchWork/MIDI/ElementMessages.swift \
//          PatchWork/MIDI/ElementLearn.swift \
//          PatchWork/MIDI/ElementValueLearn.swift \
//          PatchWork/MIDI/MIDIEvent.swift \
//          PatchWork/MIDI/SysExTemplate.swift \
//          PatchWork/MIDI/SysExTransfer.swift \
//          PatchWork/MIDI/MIDIFile.swift \
//          PatchWork/MIDI/MIDIPlayer.swift \
//          PatchWork/Canvas/ControlOperation.swift \
//          PatchWork/Canvas/ElementRandom.swift \
//          PatchWork/Document/PatchWorkDocument.swift \
//          PatchWork/Document/AppSettings.swift \
//          PatchWork/Document/AppAppearance.swift \
//          PatchWork/Widgets/EnvelopeDrawing.swift \
//          PatchWork/Widgets/PadDrawing.swift \
//          PatchWork/Widgets/ValueReadout.swift \
//          PatchWork/Canvas/ElementParameter.swift \
//          PatchWork/Canvas/CanvasElement.swift \
//          PatchWork/Canvas/ElementSchema.swift
//      /tmp/verify_midi
//
//  It has to be called main.swift: top-level statements are only allowed
//  in a file with that name. It sits outside PatchWork/PatchWork/, so the
//  app target's synchronized group does not pick it up.
//
import CoreMIDI
import Foundation

// ─── 1. The planner, against captured reference output ───────────────────
// Reference data, not hand-written:
// (kind, channel, data1, data2, label)
struct Expected { let kind: String; let ch: Int; let d1: Int; let d2: Int; let label: String }

func describe(_ m: MIDIMessage) -> Expected {
    Expected(
        kind: m.kind == .controlChange ? "cc" : m.kind == .programChange ? "program" : "sysex",
        ch: m.channel,
        d1: m.data1, d2: m.data2, label: m.label
    )
}
func check(_ name: String, _ got: [MIDIMessage], _ want: [Expected]) {
    let g = got.map(describe)
    guard g.count == want.count else {
        fatalError("\(name): expected \(want.count) message(s), got \(g.count)")
    }
    for (a, b) in zip(g, want) {
        guard a.kind == b.kind, a.ch == b.ch, a.d1 == b.d1, a.d2 == b.d2, a.label == b.label else {
            fatalError("\(name): expected \(b), got \(a)")
        }
    }
    print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)) ✓  \(got.map(\.description).joined(separator: " | "))")
}

func param(cc: Int = 0, msb: Int = 0, lsb: Int = 0, bankMSB: Int = 0, bankLSB: Int = 0,
           sysex: String = "") -> ElementParameter {
    var p = ElementParameter()
    p.cc = cc; p.paramMSB = msb; p.paramLSB = lsb; p.bankMSB = bankMSB; p.bankLSB = bankLSB
    p.sysex = sysex
    return p
}

print("planner vs the reference output:")
check("CC 7-bit",
      MIDIPlanner.messages(output: .cc, channel: 1, ceiling: 127, parameter: param(cc: 74), value: 100),
      [Expected(kind: "cc", ch: 1, d1: 74, d2: 100, label: "")])
check("CC ch16",
      MIDIPlanner.messages(output: .cc, channel: 16, ceiling: 127, parameter: param(cc: 7), value: 127),
      [Expected(kind: "cc", ch: 16, d1: 7, d2: 127, label: "")])
// A 14-bit value is clamped to 7 bits on plain CC - there is no low half to send.
check("CC 14-bit",
      MIDIPlanner.messages(output: .cc, channel: 1, ceiling: 16383, parameter: param(cc: 74), value: 9000),
      [Expected(kind: "cc", ch: 1, d1: 74, d2: 127, label: "")])
check("NRPN M/L 7-bit",
      MIDIPlanner.messages(output: .nrpnMSBLSB, channel: 2, ceiling: 127, parameter: param(msb: 1, lsb: 32), value: 64),
      [Expected(kind: "cc", ch: 2, d1: 99, d2: 1, label: "NRPN MSB"),
       Expected(kind: "cc", ch: 2, d1: 98, d2: 32, label: "NRPN LSB"),
       Expected(kind: "cc", ch: 2, d1: 6, d2: 64, label: "Data Entry (coarse)")])
check("NRPN M/L 14-bit",
      MIDIPlanner.messages(output: .nrpnMSBLSB, channel: 2, ceiling: 16383, parameter: param(msb: 1, lsb: 32), value: 9000),
      [Expected(kind: "cc", ch: 2, d1: 99, d2: 1, label: "NRPN MSB"),
       Expected(kind: "cc", ch: 2, d1: 98, d2: 32, label: "NRPN LSB"),
       Expected(kind: "cc", ch: 2, d1: 6, d2: 70, label: "Data Entry (coarse)"),
       Expected(kind: "cc", ch: 2, d1: 38, d2: 40, label: "Data Entry (fine)")])
check("NRPN L/M 14-bit",
      MIDIPlanner.messages(output: .nrpnLSBMSB, channel: 2, ceiling: 16383, parameter: param(msb: 1, lsb: 32), value: 9000),
      [Expected(kind: "cc", ch: 2, d1: 99, d2: 1, label: "NRPN MSB"),
       Expected(kind: "cc", ch: 2, d1: 98, d2: 32, label: "NRPN LSB"),
       Expected(kind: "cc", ch: 2, d1: 38, d2: 40, label: "Data Entry (fine)"),
       Expected(kind: "cc", ch: 2, d1: 6, d2: 70, label: "Data Entry (coarse)")])
check("Program",
      MIDIPlanner.messages(output: .program, channel: 3, ceiling: 127, parameter: param(bankMSB: 5, bankLSB: 6), value: 42),
      [Expected(kind: "cc", ch: 3, d1: 0, d2: 5, label: "Bank MSB"),
       Expected(kind: "cc", ch: 3, d1: 32, d2: 6, label: "Bank LSB"),
       Expected(kind: "program", ch: 3, d1: 42, d2: 0, label: "")])
// SysEx, which unlike the others carries its whole message in the payload -
// so `check` alone would pass on any bytes at all. The template rules are
// section 11's business; what is checked here is only that the planner
// reaches them, and that an empty template still plans nothing.
check("SysEx",
      MIDIPlanner.messages(output: .sysEx, channel: 1, ceiling: 127,
                           parameter: param(sysex: "F0 41 32 00 VAL F7"), value: 0x53),
      [Expected(kind: "sysex", ch: 1, d1: 0, d2: 0, label: "")])
guard MIDIPlanner.messages(output: .sysEx, channel: 1, ceiling: 127,
                           parameter: param(sysex: "F0 41 32 00 VAL F7"), value: 0x53)[0].bytes
        == [0xF0, 0x41, 0x32, 0x00, 0x53, 0xF7] else {
    fatalError("SysEx payload wrong")
}
check("SysEx, empty",
      MIDIPlanner.messages(output: .sysEx, channel: 1, ceiling: 127, parameter: param(), value: 64),
      [])

let panic = MIDIPlanner.panic()
guard panic.count == 32 else { fatalError("panic: expected 32 messages, got \(panic.count)") }
guard describe(panic[0]).d1 == 123, describe(panic[1]).d1 == 120,
      describe(panic[2]).ch == 2 else { fatalError("panic order wrong: \(panic.prefix(3).map(\.description))") }
print("  panic            ✓  32 messages, All Notes Off then All Sound Off, channels 1...16")

// Byte packing.
let cc = MIDIMessage.controlChange(channel: 16, number: 74, value: 100)
guard cc.bytes == [0xBF, 74, 100] else { fatalError("CC bytes wrong: \(cc.bytes)") }
let pc = MIDIMessage.programChange(channel: 1, number: 42)
guard pc.bytes == [0xC0, 42] else { fatalError("Program bytes wrong: \(pc.bytes)") }
print("  byte packing     ✓  CH16 CC -> BF 4A 64, CH1 Program -> C0 2A")

// ─── 2. Actually send, through a virtual destination ─────────────────────
// No MIDI hardware on this machine, so the test provides its own sink.
final class Sink {
    private let lock = NSLock()
    private var packets: [[UInt8]] = []
    /// When each one turned up. The pacing settings are timestamps rather
    /// than sleeps (see SysExTransfer), so the only honest way to check that
    /// a break happened is to notice that the bytes were late.
    private var times: [Date] = []
    /// Every complete SysEx the harness has itself put on the wire.
    ///
    /// **A virtual destination is a public port.** It appears in every
    /// application's MIDI menu the moment it is created, and a DAW scanning
    /// for control surfaces finds it within seconds - Logic Pro writes Mackie
    /// Control probes, F0 00 00 66 ..., into anything new it sees. Those bytes
    /// are nobody's bug, and a harness that fails because another application
    /// is open is a harness that gets ignored.
    ///
    /// So `received` hands back **only the harness's own traffic**, and this
    /// is what tells the two apart. Registered rather than guessed: dropping
    /// SysEx by manufacturer, or dropping all of it, would take the teeth out
    /// of the one test that matters most here - "SysEx is *not* forwarded to
    /// the Output" is only worth something if a SysEx that *was* forwarded
    /// still arrives to be noticed.
    private var ours: Set<[UInt8]> = []
    /// How much foreign traffic has been dropped, so it can be reported. A
    /// filter nobody is told about is a filter that eventually hides something.
    private var foreign = 0

    func record(_ bytes: [UInt8]) {
        lock.lock(); packets.append(bytes); times.append(Date()); lock.unlock()
    }
    func clear() {
        lock.lock(); packets.removeAll(); times.removeAll(); foreign = 0; lock.unlock()
    }

    /// Declares a SysEx the harness is about to send or play. Anything else
    /// arriving as SysEx is somebody else's and will be dropped.
    func expect(sysEx bytes: [UInt8]) { lock.lock(); ours.insert(bytes); lock.unlock() }

    /// Every SysEx inside `bytes`, whole ones only - what `play` registers.
    static func sysExMessages(in bytes: [UInt8]) -> [[UInt8]] {
        var found: [[UInt8]] = []
        var current: [UInt8]?
        for byte in bytes {
            if byte == 0xF0 { current = [byte]; continue }
            if current != nil {
                current!.append(byte)
                if byte == 0xF7 { found.append(current!); current = nil }
            }
        }
        return found
    }

    /// The packets, with any SysEx the harness did not send taken out.
    ///
    /// Byte-wise rather than packet-wise, so that **packet boundaries survive
    /// untouched**: one run further down prints how many packets a 4104-byte
    /// SysEx arrived in, and that number is the point of it. A foreign probe
    /// arrives in a packet of its own, so removing its bytes removes the whole
    /// packet and nothing else moves.
    ///
    /// An unterminated SysEx at the end of the stream is kept. It is more
    /// likely a message still arriving than a foreign one, and dropping data
    /// in flight would be the worse mistake.
    var received: [[UInt8]] {
        lock.lock(); defer { lock.unlock() }
        var drop = Set<Int>()          // flat indices belonging to foreign SysEx
        var start: Int?                // where the SysEx being read began
        var current: [UInt8] = []
        var index = 0
        for packet in packets {
            for byte in packet {
                if byte == 0xF0 { start = index; current = [byte] }
                else if start != nil {
                    current.append(byte)
                    if byte == 0xF7 {
                        if !ours.contains(current) {
                            for foreignIndex in start!...index { drop.insert(foreignIndex) }
                        }
                        start = nil
                        current = []
                    }
                }
                index += 1
            }
        }
        foreign = drop.count
        guard !drop.isEmpty else { return packets }
        var cursor = 0
        return packets.compactMap { packet in
            let kept = packet.enumerated().compactMap { drop.contains(cursor + $0.offset) ? nil : $0.element }
            cursor += packet.count
            return kept.isEmpty ? nil : kept
        }
    }

    /// Says once, if it happened, that another application wrote to this port.
    func reportForeign(_ label: String) {
        _ = received                    // recomputes the count
        lock.lock(); let bytes = foreign; lock.unlock()
        guard bytes > 0 else { return }
        print("  note: ignored \(bytes) byte(s) of SysEx from other software on this Mac")
        print("        (a DAW probing for control surfaces - Logic sends Mackie Control) [\(label)]")
    }
    /// First packet to last, in seconds.
    var span: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let first = times.first, let last = times.last else { return 0 }
        return last.timeIntervalSince(first)
    }
}
let sink = Sink()

/// The filter above, checked before anything relies on it.
///
/// A filter that silently kept nothing would make every "nothing arrived"
/// assertion below pass for the wrong reason - and one of those is the rule
/// that SysEx must never reach the Output. So the teeth are demonstrated
/// here rather than asserted in a comment.
func verifySinkFilter() {
    let mine: [UInt8] = [0xF0, 0x43, 0x10, 0xF7]
    let logic: [UInt8] = [0xF0, 0x00, 0x00, 0x66, 0x10, 0x00, 0xF7]

    // Unregistered: dropped, whoever sent it.
    let foreignOnly = Sink()
    foreignOnly.record(logic)
    guard foreignOnly.received.isEmpty else {
        fatalError("foreign SysEx was not dropped: \(foreignOnly.received)")
    }

    // Registered: kept. **This is the one that matters** - it is what still
    // fails the "SysEx is held back" test if a SysEx really were forwarded.
    let ownOnly = Sink()
    ownOnly.expect(sysEx: mine)
    ownOnly.record(mine)
    guard ownOnly.received == [mine] else {
        fatalError("our own SysEx was dropped, which would gut the thru test")
    }

    // Mixed, and across packet boundaries: only the foreign bytes go, and
    // everything else keeps the packets it arrived in.
    let mixed = Sink()
    mixed.expect(sysEx: mine)
    mixed.record([0xB0, 74, 100])
    mixed.record(logic)
    mixed.record(Array(mine.prefix(2)))
    mixed.record(Array(mine.dropFirst(2)))
    guard mixed.received == [[0xB0, 74, 100], Array(mine.prefix(2)), Array(mine.dropFirst(2))] else {
        fatalError("a split SysEx or its packet boundaries did not survive: \(mixed.received)")
    }

    // An unterminated one is kept - more likely still arriving than foreign.
    let partial = Sink()
    partial.record([0xF0, 0x42, 0x01])
    guard partial.received == [[0xF0, 0x42, 0x01]] else {
        fatalError("a SysEx still in flight was thrown away")
    }
    print("  sink keeps our traffic and drops other software's ✓  boundaries intact")
}
verifySinkFilter()

var sinkClient = MIDIClientRef()
guard MIDIClientCreateWithBlock("TestSinkClient" as CFString, &sinkClient, nil) == noErr else {
    fatalError("could not create the sink client")
}
var virtualDestination = MIDIEndpointRef()
let sinkName = "PatchWork Verify Sink" as CFString
let created = MIDIDestinationCreateWithBlock(sinkClient, sinkName, &virtualDestination) { list, _ in
    // Walked through pointers rather than by copying each MIDIPacket, and
    // deliberately spelled out here rather than calling the engine's own
    // `midiBytes`: this is the other end of what is being tested, and a
    // receiver sharing the sender's reader would agree with it about a
    // truncation neither had noticed. (Copying is precisely the bug this
    // block used to have - a MIDIPacket value carries only the 256 bytes its
    // struct declares, so anything longer arrived cut short.)
    var packet = UnsafeRawPointer(list)
        .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!)
        .assumingMemoryBound(to: MIDIPacket.self)
    for _ in 0..<list.pointee.numPackets {
        let length = Int(packet.pointee.length)
        let data = UnsafeRawPointer(packet)
            .advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
            .assumingMemoryBound(to: UInt8.self)
        sink.record(Array(UnsafeBufferPointer(start: data, count: length)))
        packet = UnsafePointer(MIDIPacketNext(packet))
    }
}
guard created == noErr else { fatalError("could not create the virtual destination (OSStatus \(created))") }

print("\nsending through a virtual destination:")
let engine = MIDIEngine()
engine.refreshEndpoints()
guard let target = engine.destinations.first(where: { $0.name == (sinkName as String) }) else {
    fatalError("engine did not enumerate the test sink; saw \(engine.destinations.map(\.name))")
}
print("  engine enumerated the sink ✓  (\(engine.destinations.count) destination(s) visible)")
engine.select(target)

let toSend = MIDIPlanner.messages(
    output: .nrpnMSBLSB, channel: 2, ceiling: 16383, parameter: param(msb: 1, lsb: 32), value: 9000
)
guard engine.send(toSend) else { fatalError("send reported failure: \(engine.lastError ?? "?")") }
RunLoop.current.run(until: Date().addingTimeInterval(0.6))

// Compared as one flattened stream, not per packet: CoreMIDI coalesces
// messages sent close together into a single received packet, which is
// what the first run of this test discovered. A receiver therefore parses
// a byte stream and must not assume one message per packet - worth
// remembering for the input side.
let want: [UInt8] = [0xB1, 99, 1, 0xB1, 98, 32, 0xB1, 6, 70, 0xB1, 38, 40]

let got = sink.received.flatMap { $0 }
sink.reportForeign("section 2")
guard got == want else {
    fatalError("bytes on the wire differ:\n  want \(want)\n  got  \(got)")
}
print("  received exactly the planned bytes ✓  \(got.map { String(format: "%02X", $0) }.joined(separator: " "))")

// A long SysEx, which used to be refused outright at 256 bytes. The sizes
// below are real: a microKORG patch is 297 bytes, a minilogue All Dump's
// longest message 522, and its LFO store one message of 37,163 - every one
// of them over the old ceiling, and the last one over what a single packet
// can describe at all (a MIDIPacket's length is a UInt16).
for size in [297, 522, 4104, 37_163] {
    sink.clear()
    // F0, a maker id, a body that is anything but F0/F7, then F7 - so a
    // reassembled message can be checked byte for byte rather than only by
    // its length.
    var dump: [UInt8] = [0xF0, 0x42]
    dump += (0..<(size - 3)).map { UInt8($0 % 0x78) }
    dump.append(0xF7)
    guard dump.count == size else { fatalError("built \(dump.count) bytes, wanted \(size)") }

    sink.expect(sysEx: dump)
    guard engine.sendRaw(dump) else {
        fatalError("\(size) bytes refused: \(engine.lastError ?? "?")")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    sink.reportForeign("\(size)-byte SysEx")

    // Reassembled from the stream, which is the whole point: it arrives in
    // as many packets as CoreMIDI cares to use, and where the breaks fall
    // is not something a receiver is entitled to an opinion about.
    let arrived = sink.received
    let stream = arrived.flatMap { $0 }
    guard stream == dump else {
        fatalError("a \(size)-byte SysEx came back as \(stream.count) bytes"
                   + (stream.count == size ? ", with different contents" : ""))
    }
    print("  \(column("\(size) bytes", 12)) ✓  arrived whole in \(arrived.count) packet(s), F0 42 … F7")
}

// SysEx over the wire, which is its own case and not covered by the NRPN
// run above: a CC is three bytes and fits any packing, while a SysEx is one
// message of arbitrary length that `send` writes into a single packet's
// inline buffer. Nothing checked that the buffer's *length* field made it
// out with the bytes - a message whose tail is lost still leaves a plausible
// F0 41 32 on the wire, which is exactly what a truncating monitor shows.
//
// Three sends of the same template at different values, because the failure
// worth catching is a value byte that never changes: byte 5 is the only one
// that differs between these, and the first four are identical in all of them.
print("\nsending SysEx through the same destination:")
let seenBefore = sink.received.count
let sysexValues = [0x53, 0x52, 0x10]
for value in sysexValues { sink.expect(sysEx: [0xF0, 0x41, 0x32, 0x00, UInt8(value), 0xF7]) }
let sysexTemplate = "F0 41 32 00 VAL F7"
for value in sysexValues {
    let planned = MIDIPlanner.messages(output: .sysEx, channel: 1, ceiling: 127,
                                       parameter: param(sysex: sysexTemplate), value: value)
    guard planned.count == 1 else { fatalError("SysEx planned \(planned.count) message(s)") }
    guard engine.send(planned) else { fatalError("SysEx send failed: \(engine.lastError ?? "?")") }
}
RunLoop.current.run(until: Date().addingTimeInterval(0.6))

let sysexWant: [UInt8] = sysexValues.flatMap { [0xF0, 0x41, 0x32, 0x00, UInt8($0), 0xF7] }
let sysexGot = sink.received.dropFirst(seenBefore).flatMap { $0 }
guard sysexGot == sysexWant else {
    fatalError("SysEx on the wire differs:\n  want \(sysexWant.map { String(format: "%02X", $0) })\n  got  \(sysexGot.map { String(format: "%02X", $0) })")
}
print("  all \(sysexWant.count) bytes arrived, F7 and all ✓")
for packet in sink.received.dropFirst(seenBefore) {
    print("      \(packet.count) bytes: \(packet.map { String(format: "%02X", $0) }.joined(separator: " "))")
}
// Said outright, because it is the whole point of the run: the byte that
// carries the value is not the one a three-byte reader would ever show.
let valueBytes = stride(from: 4, to: sysexGot.count, by: 6).map { sysexGot[$0] }
guard valueBytes == sysexValues.map({ UInt8($0) }) else {
    fatalError("the value byte did not change across sends: \(valueBytes)")
}
print("  and byte 5 changed on every send ✓  \(valueBytes.map { String(format: "%02X", $0) }.joined(separator: " -> "))")

// The length guard, which is now about *what* the message is rather than how
// long it is. A long SysEx is split over as many packets as it takes (proved
// above, up to 37KB). A long anything-else is not a message at all - every
// other MIDI message is at most three bytes - so it is refused rather than
// cut into fragments that a device would act on.
let notSysEx = [UInt8](repeating: 0x40, count: 5000)
guard engine.sendRaw(notSysEx) == false, let lengthError = engine.lastError,
      lengthError.contains("not SysEx") else {
    fatalError("a \(notSysEx.count)-byte non-SysEx should be refused, not chopped up")
}
print("  a long non-SysEx message is refused ✓  \"\(lengthError)\"")

// And nothing at all is its own answer rather than an empty packet.
guard engine.sendRaw([]) == false else { fatalError("an empty message should be refused") }
print("  an empty message is refused ✓")

// ─── 2b. Pacing, for devices that cannot drink from a hose ───────────────
// Checked by the clock, because that is the only thing that can tell a
// break from no break: the bytes are identical either way, and every one of
// these sends "succeeds" whether the device could follow it or not - which
// is the whole reason the settings exist.
print("\npacing a transfer:")

let paceBatch = (0..<8).map { MIDIMessage.controlChange(channel: 1, number: 20, value: $0) }

sink.clear()
engine.transfer = SysExTransfer(breakMS: 50)
guard engine.send(paceBatch) else { fatalError("paced send failed: \(engine.lastError ?? "?")") }
RunLoop.current.run(until: Date().addingTimeInterval(1.0))
let pacedSpan = sink.span
guard sink.received.flatMap({ $0 }) == paceBatch.flatMap(\.bytes) else {
    fatalError("a paced batch changed the bytes or their order")
}
// Seven gaps of 50 ms between eight messages. Bounded on both sides: too
// quick means the pacing did nothing, far too slow means it is sleeping
// somewhere it should be scheduling.
guard pacedSpan > 0.3, pacedSpan < 0.6 else {
    fatalError("8 messages at 50 ms apart spanned \(String(format: "%.3f", pacedSpan))s")
}
print("  a batch is spaced out ✓  8 messages, 50 ms apart, \(Int(pacedSpan * 1000)) ms end to end")

// The live-gesture path. Same messages, same setting, and no waiting at
// all - a knob dragged across its range must not queue up behind itself.
sink.clear()
guard engine.send(paceBatch, paced: false) else { fatalError("unpaced send failed") }
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
guard sink.received.flatMap({ $0 }) == paceBatch.flatMap(\.bytes) else {
    fatalError("an unpaced batch changed the bytes or their order")
}
guard sink.span < 0.05 else {
    fatalError("a live gesture was paced anyway: \(String(format: "%.3f", sink.span))s")
}
print("  a live gesture is not ✓  the same 8 messages, \(Int(sink.span * 1000)) ms end to end")

// And the chunk really is the configured one. Proved through the clock as
// well: 320 bytes at 64 to a chunk is five units, so four breaks - a packet
// count would prove nothing, since CoreMIDI repacks the stream on the way
// out (see the 4104-byte run above, which arrived in six).
sink.clear()
engine.transfer = SysExTransfer(chunkBytes: 64, breakMS: 50)
var chunkedDump: [UInt8] = [0xF0, 0x42]
chunkedDump += (0..<317).map { UInt8($0 % 0x78) }
chunkedDump.append(0xF7)
guard chunkedDump.count == 320 else { fatalError("built \(chunkedDump.count) bytes") }
sink.expect(sysEx: chunkedDump)
guard engine.send([.systemExclusive(chunkedDump)]) else {
    fatalError("chunked SysEx send failed: \(engine.lastError ?? "?")")
}
RunLoop.current.run(until: Date().addingTimeInterval(1.0))
guard sink.received.flatMap({ $0 }) == chunkedDump else {
    fatalError("a chunked SysEx did not arrive whole")
}
let chunkSpan = sink.span
guard chunkSpan > 0.15, chunkSpan < 0.45 else {
    fatalError("320 bytes at 64 a chunk spanned \(String(format: "%.3f", chunkSpan))s, wanted about 0.2")
}
print("  one message is cut to the chunk ✓  320 bytes as 5 × 64, \(Int(chunkSpan * 1000)) ms end to end")

// A handshake with nothing to listen on is refused at the first byte rather
// than discovered one timeout at a time.
engine.transfer = SysExTransfer(strategy: .handshake)
guard engine.send(paceBatch) == false, let handshakeError = engine.lastError,
      handshakeError.contains("Input") else {
    fatalError("a handshake with no Input should be refused, not attempted")
}
print("  handshake without an Input is refused ✓  \"\(handshakeError)\"")

// Back to the defaults, or every test after this one would be paced too.
engine.transfer = SysExTransfer()

// Refusing to send with nothing selected is a real state, not a crash.
engine.select(nil)
guard engine.send(toSend) == false, engine.lastError != nil else {
    fatalError("sending with no destination selected should fail and report why")
}
print("  no-destination send fails with a message ✓  \"\(engine.lastError!)\"")

// ─── 3. The parser and decoder, on hand-built streams ────────────────────
// Byte streams rather than tidy messages, because that is what arrives: the
// coalescing discovered above means a packet is a stream, and gear uses
// running status to make it a terser one.
print("\nstream parser:")

func parse(_ bytes: [UInt8]) -> [RawMIDIMessage] {
    var parser = MIDIStreamParser()
    return parser.feed(bytes)
}
func expect(_ name: String, _ got: [RawMIDIMessage], _ want: [(UInt8, [UInt8])]) {
    guard got.count == want.count,
          zip(got, want).allSatisfy({ $0.status == $1.0 && $0.data == $1.1 }) else {
        fatalError("\(name): wanted \(want), got \(got.map { ($0.status, $0.data) })")
    }
    print("  \(name.padding(toLength: 26, withPad: " ", startingAt: 0)) ✓")
}

expect("three CCs in one packet",
       parse([0xB1, 99, 1, 0xB1, 98, 32, 0xB1, 6, 70]),
       [(0xB1, [99, 1]), (0xB1, [98, 32]), (0xB1, [6, 70])])
// Running status: the status byte is sent once and the data pairs follow.
expect("running status",
       parse([0xB0, 74, 10, 74, 20, 74, 30]),
       [(0xB0, [74, 10]), (0xB0, [74, 20]), (0xB0, [74, 30])])
expect("program change (1 byte)",
       parse([0xC2, 42]),
       [(0xC2, [42])])
// Clock and Active Sensing arrive constantly and would drown a monitor -
// and they may appear *inside* another message without disturbing it.
expect("real time dropped mid-message",
       parse([0xB0, 0xF8, 74, 0xFE, 100, 0xF8]),
       [(0xB0, [74, 100])])
expect("sysex",
       parse([0xF0, 0x43, 0x10, 0x4C, 0xF7]),
       [(0xF0, [0x43, 0x10, 0x4C, 0xF7])])
// System Common carries data bytes of its own; unconsumed they would be
// mistaken for the next message's.
expect("song position consumed",
       parse([0xF2, 0x10, 0x20, 0xB0, 74, 100]),
       [(0xB0, [74, 100])])
expect("orphaned data dropped",
       parse([74, 100, 0xB0, 74, 100]),
       [(0xB0, [74, 100])])

// Split across two feeds - a message really can straddle packets, which is
// the whole reason the parser holds state.
var splitParser = MIDIStreamParser()
let firstHalf = splitParser.feed([0xB0, 74])
let secondHalf = splitParser.feed([100])
guard firstHalf.isEmpty, secondHalf.count == 1,
      secondHalf[0].status == 0xB0, secondHalf[0].data == [74, 100] else {
    fatalError("split message: got \(firstHalf) then \(secondHalf)")
}
print("  message split across packets ✓")

print("\nNRPN decoder:")
func decode(_ bytes: [UInt8]) -> [IncomingMessage] {
    var parser = MIDIStreamParser()
    var decoder = MIDIDecoder()
    return parser.feed(bytes).compactMap { decoder.decode($0) }
}
func expectDecoded(_ name: String, _ got: [IncomingMessage], _ want: [IncomingMessage]) {
    guard got == want else { fatalError("\(name): wanted \(want), got \(got)") }
    print("  \(name.padding(toLength: 26, withPad: " ", startingAt: 0)) ✓  \(got.map(\.description).joined(separator: " | "))")
}

expectDecoded("plain CC",
              decode([0xB0, 74, 100]),
              [IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 100)])
// The round trip that matters: the exact bytes the planner produced for
// NRPN 1|32 = 9000 above, decoded back to that parameter and that value.
// The address messages yield nothing on their own - they are an address.
expectDecoded("NRPN round trip",
              decode([0xB1, 99, 1, 0xB1, 98, 32, 0xB1, 6, 70, 0xB1, 38, 40]),
              [IncomingMessage(kind: .nrpn, channel: 2, number: 160, value: 8960),
               IncomingMessage(kind: .nrpn, channel: 2, number: 160, value: 9000)])
expectDecoded("program change",
              decode([0xC2, 42]),
              [IncomingMessage(kind: .programChange, channel: 3, number: 0, value: 42)])
// Notes come through so a Monitor can show them and the lamp can light,
// the same way a Control Change does.
expectDecoded("note on",
              decode([0x91, 60, 100]),
              [IncomingMessage(kind: .noteOn, channel: 2, number: 60, value: 100)])
expectDecoded("note off",
              decode([0x81, 60, 64]),
              [IncomingMessage(kind: .noteOff, channel: 2, number: 60, value: 64)])
// A note on at velocity zero *is* a note off, and gear sends it that way
// constantly - read as an on, the Monitor would show "Note On 60 = 0", which
// reads like a note stuck open.
expectDecoded("note on at velocity 0",
              decode([0x91, 60, 0]),
              [IncomingMessage(kind: .noteOff, channel: 2, number: 60, value: 0)])
// No address seen, so CC 6 is reported as the CC it literally is rather
// than as an NRPN whose parameter we would have to invent.
expectDecoded("data entry, no address",
              decode([0xB0, 6, 64]),
              [IncomingMessage(kind: .controlChange, channel: 1, number: 6, value: 64)])

// Two channels interleaving their trios: each address must stay with its
// own channel, which is why the decoder keys its pending state by channel.
expectDecoded("two channels interleaved",
              decode([0xB0, 99, 1, 0xB1, 99, 2, 0xB0, 98, 10, 0xB1, 98, 20,
                      0xB0, 6, 5, 0xB1, 6, 9]),
              [IncomingMessage(kind: .nrpn, channel: 1, number: 138, value: 640),
               IncomingMessage(kind: .nrpn, channel: 2, number: 276, value: 1152)])

// ─── 4. Actually receive, through a virtual source ───────────────────────
// The mirror of part 2: the harness plays the part of the device, sending
// into a source the engine then listens to.
print("\nreceiving through a virtual source:")
var sourceClient = MIDIClientRef()
guard MIDIClientCreateWithBlock("TestSourceClient" as CFString, &sourceClient, nil) == noErr else {
    fatalError("could not create the source client")
}
var virtualSource = MIDIEndpointRef()
let sourceName = "PatchWork Verify Source" as CFString
let sourceCreated = MIDISourceCreate(sourceClient, sourceName, &virtualSource)
guard sourceCreated == noErr else {
    fatalError("could not create the virtual source (OSStatus \(sourceCreated))")
}

engine.refreshEndpoints()
guard let listenTo = engine.sources.first(where: { $0.name == (sourceName as String) }) else {
    fatalError("engine did not enumerate the test source; saw \(engine.sources.map(\.name))")
}
print("  engine enumerated the source ✓  (\(engine.sources.count) source(s) visible)")
engine.selectSource(listenTo)

func play(_ bytes: [UInt8], on source: MIDIEndpointRef = virtualSource) {
    // Declared before it goes out: anything else that arrives as SysEx came
    // from another application - see Sink.ours.
    for message in Sink.sysExMessages(in: bytes) { sink.expect(sysEx: message) }
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { $0.copyBytes(from: bytes) }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    let status = MIDIReceived(source, &list)
    guard status == noErr else { fatalError("MIDIReceived failed (OSStatus \(status))") }
}

// A CC, an NRPN trio, and Clock in the middle of it - what a real device
// sends. The engine's read callback has to survive all of it.
play([0xB0, 74, 100])
play([0xF8])
play([0xB1, 99, 1, 0xB1, 98, 32, 0xB1, 6, 70, 0xB1, 38, 40])

/// Runs the run loop in slices until `condition` holds, so the lamp can be
/// checked while it is still lit. Waiting a flat 0.6s instead - as the first
/// version of this did - outlasts the 0.12s flash window and finds the lamp
/// already out, which says nothing about whether it ever went on.
func wait(upTo seconds: TimeInterval, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

guard wait(upTo: 1.0, until: { engine.activity.receivedCount >= 3 }) else {
    fatalError("nothing arrived: \(engine.activity.lines)")
}

let heard = engine.activity.lines.filter { $0.hasPrefix("RX") }
let wantHeard = [
    "RX  CH1 CC 74 = 100",
    "RX  CH2 NRPN 160 = 8960",
    "RX  CH2 NRPN 160 = 9000",
]
guard heard == wantHeard else {
    fatalError("activity differs:\n  want \(wantHeard)\n  got  \(heard)")
}
print("  arrived, parsed and decoded ✓")
for line in heard { print("      \(line)") }
guard engine.activity.receivedCount == 3 else {
    fatalError("received count wrong: \(engine.activity.receivedCount)")
}
guard engine.activity.inputLit else {
    fatalError("the input lamp should be lit right after receiving")
}
print("  count is 3 and the lamp is lit ✓")

// And it goes out again on its own, which is what makes a stream read as
// flicker rather than as a lamp that is simply on.
guard wait(upTo: 1.0, until: { !engine.activity.inputLit }) else {
    fatalError("the lamp never went out")
}
print("  lamp goes out after the flash window ✓")

// The other half of the long-SysEx case: a device *answering* a dump request.
// This is where the receive path used to lose it - the read block copied each
// MIDIPacket by value, and a value carries only the 256 bytes the struct
// declares, so a 37KB reply was cut to 256 and the walk to the next packet
// started from the wrong place.
func playLong(_ bytes: [UInt8], on source: MIDIEndpointRef = virtualSource) {
    for message in Sink.sysExMessages(in: bytes) { sink.expect(sysEx: message) }
    // Chunked below the UInt16 that MIDIPacket.length is, one MIDIReceived
    // each - the same reason the engine's own sender does it that way.
    let chunk = 4096
    var offset = 0
    while offset < bytes.count {
        let piece = Array(bytes[offset..<min(bytes.count, offset + chunk)])
        let capacity = MemoryLayout<MIDIPacketList>.size + piece.count + 64
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: capacity, alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let start = MIDIPacketListInit(list)
        guard UInt(bitPattern: MIDIPacketListAdd(list, capacity, start, 0, piece.count, piece)) != 0
        else { fatalError("could not pack \(piece.count) bytes to play in") }
        guard MIDIReceived(source, list) == noErr else { fatalError("MIDIReceived failed") }
        offset += min(bytes.count, offset + chunk) - offset
    }
}

let dumpSize = 37_163
var reply: [UInt8] = [0xF0, 0x42]
reply += (0..<(dumpSize - 3)).map { UInt8($0 % 0x78) }
reply.append(0xF7)

let beforeDump = engine.activity.receivedCount
playLong(reply)
guard wait(upTo: 2.0, until: { engine.activity.receivedCount > beforeDump }) else {
    fatalError("the dump never arrived")
}
// The parser hands on everything between F0 and F7 inclusive of the F7, so a
// 37,163-byte message decodes as 37,162 payload bytes.
let dumpLine = engine.activity.lines.last { $0.contains("SysEx") }
guard dumpLine == "RX  SysEx \(dumpSize - 1) bytes" else {
    fatalError("the dump arrived as \(dumpLine ?? "nothing"), wanted \(dumpSize - 1) bytes")
}
print("  a \(dumpSize)-byte dump arrives whole ✓  \(dumpLine!)")

// Disconnecting must actually stop the stream, not merely grey out a menu.
// Counted against what has arrived by now rather than a fixed number, so
// adding a case above does not look like a disconnect that leaked.
let beforeDisconnect = engine.activity.receivedCount
engine.selectSource(nil)
play([0xB0, 74, 7])
_ = wait(upTo: 0.4, until: { false })
guard engine.activity.receivedCount == beforeDisconnect else {
    fatalError("still receiving after disconnect: \(engine.activity.receivedCount)")
}
print("  nothing arrives once disconnected ✓")

// ─── 5. Which control an arriving message moves ───────────────────────────
// The inverse of part 1: the same addresses, read the other way.
print("\nincoming messages move the control they address:")

func knob(output: OutputProtocol = .cc, channel: Int = 1, cc: Int = 74) -> CanvasElement {
    var element = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 80, height: 80))
    element.output = output
    element.channel = channel
    element.parameters[0].cc = cc
    return element
}

func expectMatch(_ name: String, _ element: CanvasElement, _ incoming: IncomingMessage, _ want: Bool) {
    guard element.matches(incoming) == want else {
        fatalError("\(name): expected matches == \(want)")
    }
    print("  \(name.padding(toLength: 30, withPad: " ", startingAt: 0)) ✓  \(want ? "matches" : "ignored")")
}

let cc74 = IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 100)
expectMatch("its own CC", knob(), cc74, true)
expectMatch("another CC number", knob(cc: 75), cc74, false)
expectMatch("another channel", knob(channel: 2), cc74, false)
// The address is the same for both NRPN variants: they differ only in the
// order the data-entry halves are sent, which is gone once decoded.
var nrpnKnob = knob(output: .nrpnMSBLSB)
nrpnKnob.parameters[0].paramMSB = 1
nrpnKnob.parameters[0].paramLSB = 32
let nrpn160 = IncomingMessage(kind: .nrpn, channel: 1, number: 160, value: 9000)
expectMatch("its own NRPN address", nrpnKnob, nrpn160, true)
expectMatch("NRPN vs a plain CC", nrpnKnob, cc74, false)
var reversed = nrpnKnob
reversed.output = .nrpnLSBMSB
expectMatch("the other NRPN variant", reversed, nrpn160, true)
expectMatch("a different NRPN address", nrpnKnob,
            IncomingMessage(kind: .nrpn, channel: 1, number: 161, value: 0), false)
// Program has no address beyond its channel.
var programKnob = knob(output: .program)
expectMatch("Program on its channel", programKnob,
            IncomingMessage(kind: .programChange, channel: 1, number: 0, value: 42), true)
programKnob.channel = 5
expectMatch("Program on another channel", programKnob,
            IncomingMessage(kind: .programChange, channel: 1, number: 0, value: 42), false)
// SysEx never matches - recognising a payload is its own piece of work, and
// half-doing it would mean controls reacting to the wrong messages.
expectMatch("SysEx never matches", knob(output: .sysEx), cc74, false)
// A multi-row element is not itself addressed; its rows are, and none of
// those types can be moved by a message yet.
var envelope = CanvasElement(type: .adsr, rect: CGRect(x: 0, y: 0, width: 208, height: 120))
envelope.output = .cc
envelope.channel = 1
envelope.parameters[0].cc = 74
expectMatch("an ADSR's four rows", envelope, cc74, false)

print("\nand each type reads the number back its own way:")
var moved = knob()
guard moved.apply(cc74), moved.parameters[0].value == 100 else {
    fatalError("knob did not take the value: \(moved.parameters[0].value)")
}
// An echo of what this panel just sent costs a comparison, not a write.
guard !moved.apply(cc74) else { fatalError("re-applying the same value should report no change") }
print("  knob takes the value, an echo changes nothing ✓")

// A stale 14-bit value cannot exceed a 7-bit control's ceiling.
var narrow = knob()
_ = narrow.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 9000))
guard narrow.parameters[0].value == 127 else {
    fatalError("value should clamp to the ceiling, got \(narrow.parameters[0].value)")
}
print("  clamped to the control's own ceiling ✓  9000 -> 127")

// 64 is where MIDI puts a switch: below is off, at or above is on.
var box = CanvasElement(type: .checkbox, rect: CGRect(x: 0, y: 0, width: 120, height: 32))
box.output = .cc; box.channel = 1; box.parameters[0].cc = 74
box.checked = false
_ = box.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 63))
guard box.checked == false else { fatalError("63 should read as off") }
_ = box.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 64))
guard box.checked == true else { fatalError("64 should read as on") }
print("  checkbox reads MIDI's half-way convention ✓  63 off, 64 on")

// A radio strip looks the number up in its own table rather than treating it
// as a position - and the numbers need be neither consecutive nor sorted.
var strip = CanvasElement(type: .radio, rect: CGRect(x: 0, y: 0, width: 240, height: 56))
strip.output = .cc; strip.channel = 1; strip.parameters[0].cc = 74
strip.values = [
    ValueEntry(name: "Saw", number: 0),
    ValueEntry(name: "Square", number: 40),
    ValueEntry(name: "Sine", number: 100),
]
_ = strip.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 96))
guard strip.selected == 3 else { fatalError("96 should pick the nearest entry (100), got \(strip.selected)") }
_ = strip.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 19))
guard strip.selected == 1 else { fatalError("19 is nearer 0 than 40, got \(strip.selected)") }
// Exactly between two entries: the first minimum wins, so
// the lower entry wins. Asserted because a tie is precisely where two
// implementations of "nearest" diverge without anyone noticing.
var tied = strip
tied.values = [ValueEntry(name: "Saw", number: 0), ValueEntry(name: "Square", number: 40)]
tied.selected = 2
_ = tied.apply(IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 20))
guard tied.selected == 1 else { fatalError("a tie should pick the lower entry, got \(tied.selected)") }
print("  radio picks the nearest entry by value ✓  96 -> \"Sine\", 19 -> \"Saw\", a tie -> the lower")

// With no entries there is nothing to land on, so nothing moves.
var empty = strip
empty.values = []
empty.selected = 2
guard !empty.apply(cc74), empty.selected == 2 else { fatalError("an empty value list should not move") }
print("  an empty value list moves nothing ✓")

// An envelope has no single number to be moved to at all.
guard !envelope.apply(cc74) else { fatalError("an ADSR should not be movable by a message") }
print("  an envelope is not movable by a message ✓")

// The whole canvas at once: one message can move two controls pointed at the
// same address, and must leave everything else alone.
var canvas = [knob(), knob(), knob(cc: 75), envelope]
guard canvas.apply([cc74]) else { fatalError("the canvas should report a change") }
guard canvas[0].parameters[0].value == 100, canvas[1].parameters[0].value == 100,
      canvas[2].parameters[0].value != 100 else {
    fatalError("wrong controls moved: \(canvas.map { $0.parameters[0].value })")
}
guard !canvas.apply([IncomingMessage(kind: .controlChange, channel: 9, number: 74, value: 1)]) else {
    fatalError("a message addressed to nothing should report no change")
}
print("  two knobs on one CC both follow, others untouched ✓")

// **Asking is not writing.** This is what keeps a panel responsive while a
// controller streams: `wouldChange` answers without touching the layout, so
// ContentView can decline to write to @State - and a write to @State repaints
// every element on the canvas whether or not the value differed.
//
// Three cases, and the first two are the ones that used to repaint for nothing.
var asked = [knob(), knob(cc: 75)]
let unaddressed = IncomingMessage(kind: .controlChange, channel: 1, number: 100, value: 64)
guard !asked.wouldChange(for: [unaddressed]) else {
    fatalError("a CC no element uses should not be worth a repaint")
}
_ = asked.apply([cc74])                 // now sitting at 100
guard !asked.wouldChange(for: [cc74]) else {
    fatalError("an echo of the value already set should not be worth a repaint")
}
guard asked.wouldChange(for: [IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 7)]) else {
    fatalError("a genuinely new value should be worth a repaint")
}
// And asking really did leave everything alone.
guard asked[0].parameters[0].value == 100 else {
    fatalError("wouldChange moved something: \(asked[0].parameters[0].value)")
}
print("  asking costs no repaint ✓  unaddressed: no, echo: no, new value: yes")

// A SysEx that never ends must not grow without bound. Sent as raw bytes
// straight to the parser, since the point is what the parser keeps rather than
// what comes out of it.
var runaway = MIDIStreamParser()
let openEnded = [UInt8(0xF0)] + [UInt8](repeating: 0x01, count: MIDIStreamParser.maxSysExBytes + 4096)
guard runaway.feed(openEnded).isEmpty else {
    fatalError("an unterminated SysEx should produce no message")
}
// It is abandoned rather than truncated, so the next whole one still arrives.
let afterRunaway = runaway.feed([0xF0, 0x42, 0x01, 0xF7])
guard afterRunaway.count == 1, afterRunaway[0].data == [0x42, 0x01, 0xF7] else {
    fatalError("the parser did not recover: \(afterRunaway)")
}
print("  an unterminated SysEx is capped and recovered from ✓  limit \(MIDIStreamParser.maxSysExBytes / 1024) KB")

// ─── 6. Routing: Controller → Out, and no In → Out at all ────────────────
// The requirement this whole arrangement exists for, so it is asserted at
// the wire rather than by reading the code: bytes are played into virtual
// sources and the virtual destination is checked for what actually arrived.
print("\nrouting:")

var controllerClient = MIDIClientRef()
guard MIDIClientCreateWithBlock("TestControllerClient" as CFString, &controllerClient, nil) == noErr else {
    fatalError("could not create the controller client")
}
func makeSource(_ name: String) -> MIDIEndpointRef {
    var endpoint = MIDIEndpointRef()
    let status = MIDISourceCreate(controllerClient, name as CFString, &endpoint)
    guard status == noErr else { fatalError("could not create \(name) (OSStatus \(status))") }
    return endpoint
}
let keyboardEndpoint = makeSource("PatchWork Verify Ctrl A")
let faderBoxEndpoint = makeSource("PatchWork Verify Ctrl B")

engine.refreshEndpoints()
guard let keyboard = engine.sources.first(where: { $0.name == "PatchWork Verify Ctrl A" }),
      let faderBox = engine.sources.first(where: { $0.name == "PatchWork Verify Ctrl B" }) else {
    fatalError("engine did not enumerate the test controllers; saw \(engine.sources.map(\.name))")
}

// Several at once - the requirement, and the thing a single-selection port
// picker could not express.
engine.setController(keyboard.id, connected: true)
engine.setController(faderBox.id, connected: true)
guard engine.selectedControllerIDs.count == 2 else {
    fatalError("expected two controllers, got \(engine.selectedControllerIDs.count)")
}
guard engine.selectedControllerNames.count == 2 else {
    fatalError("controller names wrong: \(engine.selectedControllerNames)")
}
print("  two controllers connected at once ✓  \(engine.selectedControllerNames.joined(separator: ", "))")

engine.select(target)

/// Everything the destination has received since the last call.
var drained = 0
func arrived() -> [UInt8] {
    let all = sink.received.flatMap { $0 }
    defer { drained = all.count }
    return Array(all.dropFirst(drained))
}
_ = arrived()

/// Pads without truncating - padding(toLength:) cuts a longer string short,
/// which was quietly clipping these labels.
func column(_ text: String, _ width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

func expectOnTheWire(_ name: String, _ want: [UInt8]) {
    guard wait(upTo: 1.0, until: { arrivedCount() >= want.count }) || want.isEmpty else {
        fatalError("\(name): nothing arrived, wanted \(want)")
    }
    let got = arrived()
    guard got == want else {
        fatalError("\(name): wrong bytes on the wire\n  want \(want)\n  got  \(got)")
    }
    let hex = want.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("  \(column(name, 34)) ✓  \(hex.isEmpty ? "nothing" : hex)")
}
func arrivedCount() -> Int { sink.received.flatMap { $0 }.count - drained }

// A note, which is what a keyboard mostly sends.
play([0x90, 60, 100], on: keyboardEndpoint)
expectOnTheWire("keyboard note reaches the Output", [0x90, 60, 100])

// The one that would break silently: an NRPN forwarded whole and in order.
// A thru hanging off the decoder would drop CC 99 and CC 98 - they carry an
// address, not a value - and the device would land the data entry on whatever
// parameter it happened to have selected.
play([0xB0, 99, 1, 0xB0, 98, 32, 0xB0, 6, 70, 0xB0, 38, 40], on: faderBoxEndpoint)
expectOnTheWire("NRPN forwarded whole, in order",
                [0xB0, 99, 1, 0xB0, 98, 32, 0xB0, 6, 70, 0xB0, 38, 40])

// Not everything is forwarded. Clock would flood the port; SysEx is none of
// this app's business; pitch bend is left out - see MIDIThru.forwards.
play([0xF8], on: keyboardEndpoint)
play([0xF0, 0x43, 0x10, 0xF7], on: keyboardEndpoint)
play([0xE0, 0x00, 0x40], on: keyboardEndpoint)
_ = wait(upTo: 0.3, until: { false })
expectOnTheWire("clock, SysEx and bend held back", [])

// Two controllers interleaving, one of them using running status. Each
// stream has its own parser, so B's message cannot complete A's - a shared
// one would read A's continuation against B's status byte.
play([0xB0, 74, 10], on: keyboardEndpoint)
_ = wait(upTo: 0.3, until: { arrivedCount() >= 3 })
play([0xB0, 20, 5], on: faderBoxEndpoint)
_ = wait(upTo: 0.3, until: { arrivedCount() >= 6 })
play([74, 20], on: keyboardEndpoint)          // running status: still CC 74 on A
expectOnTheWire("interleaved streams stay separate",
                [0xB0, 74, 10, 0xB0, 20, 5, 0xB0, 74, 20])

// ── The rule: nothing an Input sends ever reaches the Output ──────────
// Same messages that just went through as a Controller, played into the
// Input instead.
engine.selectSource(listenTo)
let before = engine.activity.receivedCount
play([0x90, 60, 100])
play([0xB0, 74, 100])
play([0xB0, 99, 1, 0xB0, 98, 32, 0xB0, 6, 70], on: virtualSource)
guard wait(upTo: 1.0, until: { engine.activity.receivedCount > before }) else {
    fatalError("the Input heard nothing at all - the test proves nothing")
}
_ = wait(upTo: 0.3, until: { false })
expectOnTheWire("Input reaches the Output: never", [])
print("  ...and it was heard: \(engine.activity.receivedCount - before) message(s) decoded ✓")

// A Controller is forwarded *and* logged - the two are separate steps, and
// the Monitor showing a message is no evidence that it went anywhere. See
// MIDIThru, and the "the editor forwards too" section below for the mode.
let ctrlLinesBefore = engine.activity.lines.filter { $0.hasPrefix("CTRL") }.count
play([0xB0, 74, 55], on: keyboardEndpoint)
guard wait(upTo: 1.0, until: {
    engine.activity.lines.filter { $0.hasPrefix("CTRL") }.count > ctrlLinesBefore
}) else { fatalError("a controller should be heard") }
expectOnTheWire("a controller's CC is forwarded", [0xB0, 74, 55])
print("  ...and is logged as CTRL ✓  \(engine.activity.lines.last ?? "")")

// Disconnecting one leaves the other alone.
engine.setController(keyboard.id, connected: false)
guard engine.selectedControllerIDs == [faderBox.id] else {
    fatalError("disconnecting one controller disturbed the other: \(engine.selectedControllerIDs)")
}
play([0x90, 60, 100], on: keyboardEndpoint)
_ = wait(upTo: 0.3, until: { false })
expectOnTheWire("a disconnected controller is silent", [])
play([0xB0, 20, 7], on: faderBoxEndpoint)
expectOnTheWire("the remaining one still gets through", [0xB0, 20, 7])

engine.disconnectAllControllers()
guard engine.selectedControllerIDs.isEmpty else { fatalError("Disconnect All left something connected") }
print("  Disconnect All releases every controller ✓")

// ─── 7. Operating a control with the mouse ────────────────────────────────
// The drag arithmetic against a captured table - not hand-computed, since
// the whole point is to pin the number down.
print("\noperating a control:")

struct Case {
    let ceiling: Int, start: Int
    let dy: CGFloat
    let fine: Bool, useValues: Bool, want: Int
}

let waveforms = [
    ValueEntry(name: "Saw", number: 0),
    ValueEntry(name: "Square", number: 40),
    ValueEntry(name: "Sine", number: 100),
]

let dragCases = [
    Case(ceiling: 127, start: 0, dy: 150.0, fine: false, useValues: false, want: 127),
    Case(ceiling: 127, start: 0, dy: 75.0, fine: false, useValues: false, want: 64),
    Case(ceiling: 127, start: 64, dy: -150.0, fine: false, useValues: false, want: 0),
    Case(ceiling: 127, start: 64, dy: 12.0, fine: false, useValues: false, want: 74),
    Case(ceiling: 127, start: 100, dy: 150.0, fine: false, useValues: false, want: 127),
    Case(ceiling: 127, start: 64, dy: 150.0, fine: true, useValues: false, want: 80),
    Case(ceiling: 16383, start: 64, dy: 150.0, fine: false, useValues: false, want: 16383),
    Case(ceiling: 16383, start: 8192, dy: 150.0, fine: true, useValues: false, want: 10240),
    Case(ceiling: 127, start: 0, dy: 73.9, fine: false, useValues: false, want: 63),
    // The two with a list in force count *stops*, not numbers. Three entries
    // put stops at 0, 75 and 150 points of the travel, and what is stored is
    // still the entry's own number - 0, 40, 100 for Saw, Square, Sine.
    //
    // These two used to read 100 and 100. That was the old arrangement, where
    // the drag ran over the numeric range and then snapped to whichever entry
    // was nearest: 100 points of 150 reached 85, and 85 is nearer 100 than 40.
    // It is also why a list of 0, 1, 2, 3 was unusable, every entry landing in
    // the first three percent of the sweep. Now two thirds of the travel is
    // two thirds of the way along the stops, which is the second of three.
    Case(ceiling: 127, start: 0, dy: 100.0, fine: false, useValues: true, want: 40),
    // And the whole travel reaches the last stop, whatever its number.
    Case(ceiling: 127, start: 0, dy: 150.0, fine: false, useValues: true, want: 100),
    Case(ceiling: 127, start: 0, dy: 100.0, fine: false, useValues: false, want: 85),
]

for (number, test) in dragCases.enumerated() {
    var control = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
    control.resolution = test.ceiling == 127 ? .sevenBit : .fourteenBit
    guard control.valueCeiling == test.ceiling else {
        fatalError("case \(number): ceiling is \(control.valueCeiling), wanted \(test.ceiling)")
    }
    control.useValues = test.useValues
    control.values = waveforms
    control.parameters[0].value = test.start
    _ = control.dragContinuous(from: test.start, by: test.dy, fine: test.fine)
    guard control.parameters[0].value == test.want else {
        fatalError("case \(number) (ceiling \(test.ceiling), start \(test.start), dy \(test.dy), fine \(test.fine), values \(test.useValues)): got \(control.parameters[0].value), the reference says \(test.want)")
    }
}
print("  \(dragCases.count) drag cases match control.drag's own formula ✓")

// 150 points is the whole range whatever the ceiling, and Shift is a fraction
// of that - the two properties the numbers above are there to protect.
print("  150pt covers 0...127 and 0...16383 alike, Shift is 1/8 ✓")

// A drag reports whether it changed anything, so a stream of mouse moves that
// says the same thing costs one comparison instead of one message.
var still = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
still.parameters[0].value = 64
guard !still.dragContinuous(from: 64, by: 0, fine: false) else {
    fatalError("a zero drag should report no change")
}
guard still.dragContinuous(from: 64, by: 10, fine: false) else {
    fatalError("a real drag should report a change")
}
print("  an unchanged drag reports nothing to send ✓")

// Clicking a discrete control.
var strip4 = CanvasElement(type: .radio, rect: CGRect(x: 0, y: 0, width: 240, height: 56))
strip4.segmentCount = 4
for (x, want) in [(0.0, 1), (59.0, 1), (61.0, 2), (130.0, 3), (239.0, 4), (240.0, 4)] {
    _ = strip4.press(at: CGPoint(x: x, y: 20), in: CGSize(width: 240, height: 56))
    guard strip4.selected == want else {
        fatalError("radio click at x=\(x) picked \(strip4.selected), wanted \(want)")
    }
}
print("  radio picks the segment under the pointer ✓  incl. the right edge, which divides out one past the last")

// The conversion the press depends on. A strip is rarely at the canvas's own
// origin, and reading a press in the wrong space still lands somewhere - it
// just always lands in the same segment, which is what made this invisible.
var placedStrip = CanvasElement(type: .radio, rect: CGRect(x: 500, y: 100, width: 240, height: 56))
placedStrip.segmentCount = 4
for (canvasX, want) in [(500.0, 1), (560.0, 2), (620.0, 3), (739.0, 4)] {
    let local = placedStrip.localPoint(fromCanvas: CGPoint(x: canvasX, y: 120))
    _ = placedStrip.press(at: local, in: placedStrip.rect.size)
    guard placedStrip.selected == want else {
        fatalError("a click at canvas x=\(canvasX) on a strip starting at 500 picked \(placedStrip.selected), wanted \(want)")
    }
}
// Read in the canvas's space by mistake, every one of those lands in the last
// segment - which is exactly the symptom that was reported.
_ = placedStrip.press(at: CGPoint(x: 560, y: 120), in: placedStrip.rect.size)
guard placedStrip.selected == 4 else { fatalError("the old mistake should land in the last segment") }
print("  and the point is converted into the element first ✓  a strip at x=500 spreads over its own four segments")

var box2 = CanvasElement(type: .checkbox, rect: CGRect(x: 0, y: 0, width: 120, height: 32))
let wasChecked = box2.checked
_ = box2.press(at: CGPoint(x: 10, y: 10), in: CGSize(width: 120, height: 32))
guard box2.checked != wasChecked else { fatalError("a checkbox click should toggle it") }
print("  checkbox toggles ✓")

var combo = CanvasElement(type: .combobox, rect: CGRect(x: 0, y: 0, width: 160, height: 56))
combo.values = waveforms
combo.selected = 1
var walked: [Int] = []
for _ in 0..<4 {
    _ = combo.press(at: .zero, in: CGSize(width: 160, height: 56))
    walked.append(combo.selected)
}
guard walked == [2, 3, 1, 2] else { fatalError("combobox should step and wrap, walked \(walked)") }
print("  combobox steps and wraps ✓  1 → 2 → 3 → 1")

// Choosing outright, which is what the dropdown reports back - the usual path
// on the canvas, where stepping is only the fallback for anyone with no view
// to put a list over.
var picked = CanvasElement(type: .combobox, rect: CGRect(x: 0, y: 0, width: 160, height: 56))
picked.values = waveforms
guard picked.choose(entry: 2), picked.selected == 3 else {
    fatalError("choosing the third entry gave \(picked.selected)")
}
guard !picked.choose(entry: 2) else { fatalError("choosing what is chosen should report nothing") }
// Clamped to the entry count, and never below the first.
_ = picked.choose(entry: 99)
guard picked.selected == 3 else { fatalError("past the end should clamp, got \(picked.selected)") }
_ = picked.choose(entry: -5)
guard picked.selected == 1 else { fatalError("below the start should clamp, got \(picked.selected)") }
print("  combobox chooses outright ✓  0-based in, 1-based out, clamped at both ends")

// Double-click a bipolar control: back to its own zero, whatever its width.
for (resolution, want) in [(Resolution.sevenBit, 64), (.fourteenBit, 8192)] {
    var bipolarKnob = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
    bipolarKnob.resolution = resolution
    bipolarKnob.bipolar = true
    bipolarKnob.parameters[0].value = 3
    guard bipolarKnob.recentre(), bipolarKnob.parameters[0].value == want else {
        fatalError("recentre at \(resolution) landed on \(bipolarKnob.parameters[0].value), wanted \(want)")
    }
}
// A unipolar control has no zero to go back to, so the gesture means nothing.
var unipolar = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
unipolar.parameters[0].value = 3
guard !unipolar.recentre(), unipolar.parameters[0].value == 3 else {
    fatalError("a unipolar control should not recentre")
}
print("  recentre finds the centre of its own domain ✓  64 at 7-bit, 8192 at 14-bit, nothing unipolar")

// What an operated control puts on the wire, which is not always what it
// holds (control.send_value).
var sendingStrip = CanvasElement(type: .radio, rect: CGRect(x: 0, y: 0, width: 240, height: 56))
sendingStrip.output = .cc
sendingStrip.channel = 1
sendingStrip.parameters[0].cc = 74
sendingStrip.values = waveforms
sendingStrip.selected = 3
guard sendingStrip.midiMessages.map(\.data2) == [100] else {
    fatalError("a radio should send its entry's number, got \(sendingStrip.midiMessages.map(\.data2))")
}
// No entry to read a number off: the position stands in, so an unfilled strip
// still tells its segments apart instead of sending the same thing every time.
sendingStrip.values = []
sendingStrip.selected = 3
guard sendingStrip.midiMessages.map(\.data2) == [2] else {
    fatalError("an unfilled strip should send its position, got \(sendingStrip.midiMessages.map(\.data2))")
}
print("  a radio sends its value table's number, or its position ✓  \"Sine\" → 100, unfilled 3rd → 2")

var sendingBox = CanvasElement(type: .checkbox, rect: CGRect(x: 0, y: 0, width: 120, height: 32))
sendingBox.output = .cc; sendingBox.channel = 1; sendingBox.parameters[0].cc = 74
sendingBox.resolution = .fourteenBit
sendingBox.checked = true
guard sendingBox.midiMessages.map(\.data2) == [127] else {
    fatalError("a 14-bit checkbox on CC should send full scale clamped to 7 bits, got \(sendingBox.midiMessages.map(\.data2))")
}
print("  a checkbox sends the ends of its own domain ✓")

// ─── 8. The grid ─────────────────────────────────────────────────────────
print("\nsnapping:")
for (raw, want) in [(0.0, 0.0), (3.0, 0.0), (4.0, 8.0), (5.0, 8.0), (105.015625, 104.0), (-3.0, -0.0)] {
    guard CanvasLayout.snapped(CGFloat(raw)) == CGFloat(want) else {
        fatalError("snapped(\(raw)) = \(CanvasLayout.snapped(CGFloat(raw))), wanted \(want)")
    }
}
guard CanvasLayout.grid == 8 else { fatalError("the grid step should be 8, as in canvas.GRID") }
print("  snapped() rounds to the nearest 8 ✓  and 105.015625 - the float the user saw - lands on 104")

// ─── 9. Copy and paste ────────────────────────────────────────────────────
print("\ncopy and paste:")

// What a paste produces. A shared id would be the worst kind of bug here:
// two entries with one id make a ForEach draw one element and a selection
// address both, so the copy would move whenever the original did.
var original = CanvasElement(type: .knob, rect: CGRect(x: 40, y: 40, width: 72, height: 88))
original.values = [ValueEntry(name: "Saw", number: 0)]
let copy = original.duplicated(offset: CanvasLayout.grid)
guard copy.id != original.id,
      copy.parameters[0].id != original.parameters[0].id,
      copy.values[0].id != original.values[0].id else {
    fatalError("a pasted element must not share an id with what it came from")
}
guard copy.x == original.x + 8, copy.y == original.y + 8 else {
    fatalError("a paste should be offset by one grid step, got (\(copy.x), \(copy.y))")
}
print("  \(column("paste is a real copy", 22)) ✓  fresh ids throughout, offset by one grid step")

// ─── 10. Learn ────────────────────────────────────────────────────────────
// Addresses, never values - and from the Controller, which is the port a hand
// touches. Checked against midi.learn's own rules.
print("\nlearn:")

var learnADSR = CanvasElement(type: .adsr, rect: CGRect(x: 0, y: 0, width: 208, height: 120))
guard learnADSR.parameters.count == 4 else {
    fatalError("an ADSR should have four parameters, has \(learnADSR.parameters.count)")
}

// A plain CC: 7-bit, and the number into this row alone.
guard learnADSR.learn(IncomingMessage(kind: .controlChange, channel: 3, number: 80, value: 99), at: 0) else {
    fatalError("a CC should be learnable")
}
guard learnADSR.output == .cc, learnADSR.resolution == .sevenBit,
      learnADSR.channel == 3, learnADSR.parameters[0].cc == 80 else {
    fatalError("CC learn wrong: \(learnADSR.output) \(learnADSR.resolution) ch\(learnADSR.channel) cc\(learnADSR.parameters[0].cc)")
}
// The value that happened to be on the knob is the one thing Learn never
// writes - a control pointed at a new address keeps whatever it was set to.
guard learnADSR.parameters[0].value != 99 else {
    fatalError("Learn wrote the value; it must only ever write the address")
}
print("  a CC writes address, protocol, resolution and channel ✓  CC 80 ch3, 7-bit")
print("  and never the value ✓  the knob stayed at \(learnADSR.parameters[0].value), not 99")

// Learning one stage leaves the other three where they were.
guard learnADSR.parameters[1].cc != 80, learnADSR.parameters[2].cc != 80 else {
    fatalError("learning one stage moved another")
}
print("  one stage at a time ✓  the other three stages untouched")

// An NRPN address is 14 bits, split across two 7-bit halves. Clamping instead
// of splitting would flatten 1234 to 127 and learn the wrong parameter.
var nrpnTarget = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
guard nrpnTarget.learn(IncomingMessage(kind: .nrpn, channel: 1, number: 1234, value: 0), at: 0) else {
    fatalError("an NRPN should be learnable")
}
guard nrpnTarget.output == .nrpnMSBLSB, nrpnTarget.resolution == .fourteenBit,
      nrpnTarget.parameters[0].paramMSB == (1234 >> 7) & 0x7F,
      nrpnTarget.parameters[0].paramLSB == 1234 & 0x7F else {
    fatalError("NRPN learn wrong: MSB \(nrpnTarget.parameters[0].paramMSB) LSB \(nrpnTarget.parameters[0].paramLSB)")
}
print("  an NRPN splits its 14-bit address ✓  1234 → MSB \(nrpnTarget.parameters[0].paramMSB) / LSB \(nrpnTarget.parameters[0].paramLSB), and 14-bit with it")

// The whole point: after learning, matches() is true for the same message -
// the two are one statement about addressing, written twice would be one bug.
let sameNRPN = IncomingMessage(kind: .nrpn, channel: 1, number: 1234, value: 42)
guard nrpnTarget.matches(sameNRPN) else {
    fatalError("a learned element must match the message it learned from")
}
let learnedCC = IncomingMessage(kind: .controlChange, channel: 3, number: 80, value: 1)
var single = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
_ = single.learn(learnedCC, at: 0)
guard single.matches(learnedCC) else {
    fatalError("a learned CC element must match the message it learned from")
}
print("  after learning, matches() is true for the same message ✓  both protocols")

// SysEx is not learnable - there is nothing to compare a payload against.
var untouched = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
let learnBefore = untouched
guard !untouched.learn(IncomingMessage(kind: .systemExclusive, channel: 0, number: 0, value: 6), at: 0),
      untouched.output == learnBefore.output, untouched.parameters[0].cc == learnBefore.parameters[0].cc else {
    fatalError("SysEx should not be learnable and should change nothing")
}
print("  SysEx is refused and changes nothing ✓")

// A row that does not exist is refused rather than trapping.
guard !untouched.learn(learnedCC, at: 7) else { fatalError("a missing row should be refused") }
print("  a row out of range is refused ✓")

// A note is played, not addressed. It must never be learned from - that would
// assign whichever key was pressed - and never match a control.
var noteTarget = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
noteTarget.output = .cc
noteTarget.channel = 1
noteTarget.parameters[0].cc = 60
let played = IncomingMessage(kind: .noteOn, channel: 1, number: 60, value: 100)
guard !noteTarget.learn(played, at: 0) else { fatalError("a note should not be learnable") }
guard Learn.output(for: .noteOn) == nil, Learn.output(for: .noteOff) == nil else {
    fatalError("notes have no output to be learned as")
}
// Note 60 on channel 1 against a knob on CC 60, channel 1 - the collision that
// would show a sloppy match.
guard !noteTarget.matches(played) else {
    fatalError("a note matched a control that happens to share its number")
}
print("  a note is never learned from and never matches ✓  even at CC 60 vs note 60")

// Which output a kind learns as - what lets a run refuse a second protocol.
guard Learn.output(for: .controlChange) == .cc,
      Learn.output(for: .nrpn) == .nrpnMSBLSB,
      Learn.output(for: .programChange) == .program,
      Learn.output(for: .systemExclusive) == nil else {
    fatalError("the learned-output table is wrong")
}
print("  one run, one protocol ✓  CC / NRPN (MSB/LSB) / Program, SysEx never")

// An address is a kind, a channel and a number - and no value. That is what
// makes "the knob is still moving" distinguishable from "the next answer".
let turning = IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 10)
let stillTurning = IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 90)
let otherKnob = IncomingMessage(kind: .controlChange, channel: 1, number: 75, value: 10)
guard LearnAddress(turning) == LearnAddress(stillTurning),
      LearnAddress(turning) != LearnAddress(otherKnob) else {
    fatalError("an address must ignore the value and nothing else")
}
print("  the same knob turning is one address ✓  a different knob is a new one")

// A four-stage run walks the stages, one distinct address each - the shape a
// real ADSR learn takes: four knobs, four stages.
var fourStage = CanvasElement(type: .adsr, rect: CGRect(x: 0, y: 0, width: 208, height: 120))
for (row, number) in [(0, 80), (1, 81), (2, 82), (3, 83)] {
    guard fourStage.learn(IncomingMessage(kind: .controlChange, channel: 5, number: number, value: 0), at: row) else {
        fatalError("stage \(row) refused")
    }
}
guard fourStage.parameters.map(\.cc) == [80, 81, 82, 83], fourStage.channel == 5 else {
    fatalError("the run landed wrong: \(fourStage.parameters.map(\.cc))")
}
print("  a four-stage run ✓  A/D/S/R on CC 80/81/82/83, channel shared")

// Which roles Learn answers to: the Input, and only the Input - the device the
// editor is being built for. Wrapped, like section 11 - see the note there.
func verifyLearnRoles() {
    print("\nlearn roles:")
    let input: MIDIRoles = [.input]
    let controller: MIDIRoles = [.controller]
    let shared: MIDIRoles = [.input, .controller]

    guard Learn.accepts(input) else { fatalError("the Input must be able to address") }
    // A device picked as both wears two hats and is still the Input.
    guard Learn.accepts(shared) else { fatalError("a shared device is the Input too") }
    // A Controller's CC numbers are the Controller's, and say nothing about
    // the instrument the panel is for.
    guard !Learn.accepts(controller) else {
        fatalError("a Controller-only message must not address anything")
    }
    print("  the Input addresses ✓  a shared device too, a Controller never")

    // The rule reads off the message alone. Nothing about what else is
    // selected can enter into it - that dependency is what silently refused
    // every Input message while a controller from an earlier session was
    // still remembered.
    guard Learn.accepts(input) == Learn.accepts(shared) else {
        fatalError("the answer must not depend on anything but the roles")
    }
    print("  and depends on the roles alone ✓  no hidden selection state")
}
verifyLearnRoles()

// What the MIDI Monitor window records: the classification each filter reads,
// and the gate that keeps all of it switched off while no window is open.
// Wrapped, like the sections around it - see the note at verifyLearnValues.
func verifyMonitorEvents() {
    print("\nmonitor events:")

    // Status byte → Kind. The filter is only as good as this table.
    let byKind: [(UInt8, MIDIEvent.Kind)] = [
        (0x90, .note), (0x80, .note), (0xA0, .aftertouch), (0xD0, .aftertouch),
        (0xB0, .controlChange), (0xC0, .programChange), (0xE0, .pitchBend),
        (0xF0, .sysEx), (0xF8, .realtime), (0xFE, .realtime), (0xF1, .other),
    ]
    for (status, expected) in byKind where MIDIEvent.Kind.of(status: status) != expected {
        fatalError("status \(String(format: "%02X", status)) classified as \(MIDIEvent.Kind.of(status: status)), not \(expected)")
    }
    // Channel messages carry their nibble, and it must not change the answer.
    for channel in UInt8(0)...UInt8(15) where MIDIEvent.Kind.of(status: 0xB0 | channel) != .controlChange {
        fatalError("the channel nibble changed what a CC is")
    }
    print("  every status byte lands on its kind ✓  Clock and Active Sensing as realtime")

    // The decoder's own kinds, including the one that exists nowhere on the
    // wire - which is the whole reason both forms are shown.
    guard MIDIEvent.Kind.of(incoming: .nrpn) == .nrpn,
          MIDIEvent.Kind.of(incoming: .controlChange) == .controlChange,
          MIDIEvent.Kind.of(incoming: .noteOn) == .note,
          MIDIEvent.Kind.of(incoming: .noteOff) == .note,
          MIDIEvent.Kind.of(incoming: .programChange) == .programChange,
          MIDIEvent.Kind.of(incoming: .systemExclusive) == .sysEx else {
        fatalError("a decoded kind was mapped wrong")
    }
    print("  and every decoded kind too ✓  NRPN among them, which no wire form has")

    // SysEx: the raw form spells the bytes out, the decoded form still only
    // counts them. Both on purpose - see MIDIEventParts.raw.
    let payload: [UInt8] = [0xF0, 0x42, 0x30, 0x00, 0x01, 0xF7]
    let rawSysEx = MIDIEventParts.raw(
        RawMIDIMessage(status: 0xF0, data: Array(payload.dropFirst())),
        direction: .rx, device: "Nord Lead"
    )
    guard rawSysEx.kind == .sysEx, rawSysEx.bytes == payload,
          rawSysEx.text.contains("42"), rawSysEx.text.contains("F7") else {
        fatalError("raw SysEx lost its bytes: \(rawSysEx.text) \(rawSysEx.bytes)")
    }
    let decodedSysEx = MIDIEventParts.decoded(
        IncomingMessage(kind: .systemExclusive, channel: 0, number: 0, value: 6),
        direction: .rx, device: "Nord Lead"
    )
    guard decodedSysEx.bytes.isEmpty, decodedSysEx.text.contains("bytes") else {
        fatalError("the decoded form should carry no bytes")
    }
    guard decodedSysEx.channel == nil else {
        // IncomingMessage stores 0 there; MIDI counts channels from 1, so
        // printing that would name one that does not exist.
        fatalError("a decoded SysEx must carry no channel")
    }
    print("  raw SysEx keeps its bytes ✓  the decoded form still just counts them, and no channel")

    // Realtime never becomes a RawMIDIMessage - the parser drops it before
    // anything downstream sees it - so the window picks it off the byte
    // stream itself and needs names of its own.
    let clock = MIDIEventParts.realtime(0xF8, direction: .rx, device: nil)
    guard clock.kind == .realtime, clock.channel == nil,
          clock.text == "Clock", clock.bytes == [0xF8] else {
        fatalError("Clock was recorded wrong: \(clock.text)")
    }
    guard MIDIEvent.realtimeName(0xFE) == "Active Sensing",
          MIDIEvent.realtimeName(0xFA) == "Start",
          MIDIEvent.realtimeName(0xFC) == "Stop" else {
        fatalError("the realtime names are wrong")
    }
    print("  realtime bytes are named ✓  Clock, Start, Stop, Active Sensing")

    // A sent message is logged in both forms, so neither view of the window is
    // missing half the traffic.
    let sent = MIDIEventParts.sent(
        .controlChange(channel: 1, number: 74, value: 100, label: "Cutoff"),
        device: "Nord Lead MIDI Input"
    )
    guard sent.count == 2, sent.contains(where: { $0.form == .raw }),
          sent.contains(where: { $0.form == .decoded }),
          sent.allSatisfy({ $0.direction == .tx && $0.kind == .controlChange }) else {
        fatalError("a sent message should be logged raw and decoded: \(sent.map(\.form))")
    }
    guard sent.first(where: { $0.form == .decoded })?.text.contains("Cutoff") == true else {
        fatalError("the decoded reading is the one carrying the label")
    }
    print("  a send is logged both ways ✓  the label rides on the decoded one")

    // Nothing is recorded while no window is open - the state this class is
    // in for almost all of its life.
    let activity = MIDIActivity()
    let one: [MIDIEventParts] = [.raw(RawMIDIMessage(status: 0xB0, data: [74, 100]),
                                     direction: .rx, device: nil)]
    activity.record(one)
    guard !activity.isCapturing, activity.events.isEmpty else {
        fatalError("recorded with no Monitor window open")
    }
    activity.beginCapture()
    activity.record(one)
    guard activity.events.count == 1 else { fatalError("nothing recorded while capturing") }
    print("  closed window records nothing ✓  open one records")

    // Two windows, one board: the last to close is what ends it.
    activity.beginCapture()
    activity.endCapture()
    guard activity.isCapturing, activity.events.count == 1 else {
        fatalError("the first window closing stopped the second's recording")
    }
    activity.endCapture()
    guard !activity.isCapturing, activity.events.isEmpty else {
        fatalError("the log should be dropped with the last window")
    }
    print("  two windows are counted, not toggled ✓")

    // The ring keeps the newest, which is what a log is read from.
    let deep = MIDIActivity()
    deep.beginCapture()
    for value in 0..<(MIDIActivity.eventLimit + MIDIActivity.historySlack + 200) {
        deep.record([.raw(RawMIDIMessage(status: 0xB0, data: [74, UInt8(value % 128)]),
                          direction: .rx, device: nil)])
    }
    guard deep.events.count <= MIDIActivity.eventLimit + MIDIActivity.historySlack,
          deep.events.count >= MIDIActivity.eventLimit else {
        fatalError("the ring did not hold: \(deep.events.count)")
    }
    let ids = deep.events.map(\.id)
    guard ids == ids.sorted(), ids.last == UInt64(MIDIActivity.eventLimit + MIDIActivity.historySlack + 200) else {
        fatalError("the ring dropped the newest instead of the oldest")
    }
    print("  the ring keeps the newest ✓  \(deep.events.count) of \(MIDIActivity.eventLimit + MIDIActivity.historySlack + 200)")

    // Clearing the window's log leaves the panel's own alone.
    let both = MIDIActivity()
    both.beginCapture()
    both.recordReceived([IncomingMessage(kind: .controlChange, channel: 1, number: 74, value: 9)])
    both.record(one)
    guard !both.lines.isEmpty, !both.events.isEmpty else { fatalError("nothing to clear") }
    both.clearEvents()
    guard both.events.isEmpty, !both.lines.isEmpty else {
        fatalError("clearing the window's log wiped the panel's Monitor too")
    }
    print("  Clear empties the window only ✓  the panel's Monitor keeps its lines")
}
verifyMonitorEvents()

// A value list that keeps its own order, and a control that steps through it.
// The Nord Lead is the case this exists for: its wave types are not numbered
// in the order the instrument lists them. Wrapped, like the sections around
// it - see the note at verifyLearnValues.
func verifyValueOrder() {
    print("\nvalue list order:")

    // A1 on CC 5, A2 on CC 2, A3 on CC 8 - the instrument's own order is not
    // its numeric one.
    let nordLead = [ValueEntry(name: "A1", number: 5),
                    ValueEntry(name: "A2", number: 2),
                    ValueEntry(name: "A3", number: 8)]

    guard ValueList.ordered(nordLead, sorted: false).map(\.name) == ["A1", "A2", "A3"],
          ValueList.ordered(nordLead, sorted: true).map(\.name) == ["A2", "A1", "A3"] else {
        fatalError("ordered() got the two orders wrong")
    }
    print("  both orders ✓  listed A1/A2/A3, sorted A2/A1/A3")

    // Stable: entries sharing a number keep the order they were typed in,
    // rather than swapping between one call and the next.
    let tied = [ValueEntry(name: "first", number: 4), ValueEntry(name: "second", number: 4),
                ValueEntry(name: "third", number: 1)]
    guard ValueList.ordered(tied, sorted: true).map(\.name) == ["third", "first", "second"] else {
        fatalError("the sort is not stable")
    }
    print("  a tie keeps the typed order ✓")

    func waveKnob(sorted: Bool) -> CanvasElement {
        var element = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
        element.useValues = true
        element.values = nordLead
        element.sortsValues = sorted
        element.parameters[0].value = sorted ? 2 : 5      // the first stop of each order
        return element
    }

    // Dragging up walks the stops in the element's own order, and what is
    // stored is the entry's number - never the index.
    for (sorted, expected) in [(false, [5, 2, 8]), (true, [2, 5, 8])] {
        var element = waveKnob(sorted: sorted)
        var seen = [element.parameterValue(0)]
        // Far enough per step to cross one stop of three, from the value the
        // gesture began on - the same measure-from-the-start rule the
        // continuous drag uses.
        let start = element.parameterValue(0)
        for step in 1...2 {
            _ = element.dragContinuous(from: start,
                                       by: CGFloat(step) * ControlOperation.dragRange / 2,
                                       fine: false)
            seen.append(element.parameterValue(0))
        }
        guard seen == expected else {
            fatalError("sorted=\(sorted) walked \(seen), expected \(expected)")
        }
    }
    print("  a drag walks the stops in order ✓  unsorted sends 5, 2, 8 - not 2, 5, 8")

    // The stops are evenly spread, whatever the numbers are. This is what
    // makes a list of 0/1/2/3 usable at all.
    var lowNumbers = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
    lowNumbers.useValues = true
    lowNumbers.values = (0...3).map { ValueEntry(name: "W\($0)", number: $0) }
    for (index, entry) in lowNumbers.orderedValues.enumerated() {
        lowNumbers.parameters[0].value = entry.number
        let wanted = CGFloat(index) / 3
        guard abs(lowNumbers.displayFraction - wanted) < 0.0001 else {
            fatalError("entry \(index) sat at \(lowNumbers.displayFraction), not \(wanted)")
        }
    }
    print("  N entries are N even stops ✓  0/1/2/3 spread across the whole travel")

    // The caption is the entry's name, and the index survives a value that is
    // on no entry at all - a hand-edited file, or a narrowed resolution.
    var knob = waveKnob(sorted: false)
    knob.parameters[0].value = 2
    guard knob.valueIndex == 1, knob.valueCaption == "A2" else {
        fatalError("index/caption wrong: \(knob.valueIndex) \(knob.valueCaption ?? "nil")")
    }
    knob.parameters[0].value = 7          // between A1 (5) and A3 (8), on neither
    guard knob.valueIndex == 2 else { fatalError("the nearest stop should be A3") }
    print("  the caption names the stop ✓  and an off-entry value finds its nearest")

    // No list, no override: an ordinary knob is untouched by any of this.
    var plain = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
    plain.parameters[0].value = 64
    guard !plain.valueListActive, plain.valueCaption == nil,
          abs(plain.displayFraction - valueFraction(64, ceiling: 127)) < 0.0001 else {
        fatalError("a plain knob should behave exactly as before")
    }
    print("  a knob without a list is unchanged ✓")

    // Min/Max no longer reach a value list. Narrowing the range used to drag
    // a perfectly good entry value off its entry.
    var narrowed = waveKnob(sorted: false)
    narrowed.rangeMin = 20
    narrowed.rangeMax = 100
    guard narrowed.parameterValue(0) == 5 else {
        fatalError("Min/Max moved a value list entry to \(narrowed.parameterValue(0))")
    }
    print("  Min/Max leave a value list alone ✓  the entry stayed on 5")

    // Sort defaults on, and survives a save/load round trip.
    guard CanvasElement(type: .knob, rect: .zero).sortsValues else {
        fatalError("Sort should default to true")
    }
    var off = waveKnob(sorted: false)
    off.name = "Wave"
    let document = PatchWorkDocument(elements: [off], locked: false)
    let coded = try! JSONEncoder().encode(document)
    let back = try! JSONDecoder().decode(PatchWorkDocument.self, from: coded)
    guard back.elements.first?.sortsValues == false else {
        fatalError("Sort did not survive the round trip")
    }
    print("  Sort defaults on and round-trips ✓")
}
verifyValueOrder()

// ─── 11. Learn Values ─────────────────────────────────────────────────────
// The other half of Learn: collecting the values a control takes rather than
// the address it sits at. Checked against captureValue's own rules - what it
// files, and every reason it refuses.
// Wrapped in a function it then calls, unlike the sections around it. Every
// top-level statement in this file is type-checked as one body, and that body
// is now long enough that adding to it overflows the solver's stack outright -
// a compiler crash, not an error message. A function is a body of its own.
func verifyLearnValues() {
    print("\nlearn values:")

    // A combo box addressed at CC 77, channel 1, which is the shape the feature
    // exists for: step the device's waveform selector and the list fills itself.
    func valueLearnCombo() -> CanvasElement {
        var element = CanvasElement(type: .combobox, rect: CGRect(x: 0, y: 0, width: 120, height: 28))
        element.output = .cc
        element.channel = 1
        element.parameters[0].cc = 77
        element.useValues = true
        element.values = []
        return element
    }
    func addressed(_ value: Int, cc: Int = 77, channel: Int = 1) -> IncomingMessage {
        IncomingMessage(kind: .controlChange, channel: channel, number: cc, value: value)
    }

    var collector = valueLearnCombo()
    guard collector.captureValue(addressed(0)) else { fatalError("an addressed value should be collected") }
    guard collector.values.count == 1, collector.values[0].number == 0,
          collector.values[0].name.isEmpty else {
        fatalError("the entry should be the value, unnamed: \(collector.values)")
    }
    print("  an addressed value is filed, unnamed ✓  the name is typed over it later")

    // Arrival order, not sorted: the order a front panel walks its own values is
    // information, and sorting would throw it away.
    _ = collector.captureValue(addressed(32))
    _ = collector.captureValue(addressed(16))
    guard collector.values.map(\.number) == [0, 32, 16] else {
        fatalError("arrival order lost: \(collector.values.map(\.number))")
    }
    print("  arrival order is kept ✓  0, 32, 16 - not sorted")

    // The same value again is the knob sweeping back over it, not a new entry.
    guard !collector.captureValue(addressed(32)), collector.values.count == 3 else {
        fatalError("a repeated value should be skipped")
    }
    print("  an existing value is skipped ✓")

    // Another knob on the same device contributes nothing, and neither does the
    // same knob on another channel. This is the whole reason it filters by address.
    guard !collector.captureValue(addressed(64, cc: 74)),
          !collector.captureValue(addressed(64, channel: 2)),
          collector.values.count == 3 else {
        fatalError("an unaddressed message was collected: \(collector.values.map(\.number))")
    }
    print("  a different CC or channel is ignored ✓")

    // Min/Max have no say over a value list - the list defines the legal
    // values outright - so a narrowed range must not drop entries the device
    // really sends. This check used to assert the opposite; the rule changed
    // deliberately, along with the Range fields going grey in the Inspector.
    var narrowed = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
    narrowed.output = .cc
    narrowed.channel = 1
    narrowed.parameters[0].cc = 77
    narrowed.useValues = true
    narrowed.rangeMin = 20
    narrowed.rangeMax = 100
    guard narrowed.captureValue(addressed(12)), narrowed.values.map(\.number) == [12] else {
        fatalError("Min/Max filtered a value list entry: \(narrowed.values.map(\.number))")
    }
    print("  Min/Max do not filter what is collected ✓  the list defines its own values")

    // The resolution still does bound it: a 7-bit control has no 9000, and
    // clamping would file an entry at 127 that nothing ever sent.
    var sevenBit = valueLearnCombo()
    sevenBit.output = .nrpnMSBLSB
    sevenBit.parameters[0].paramMSB = 0
    sevenBit.parameters[0].paramLSB = 9
    sevenBit.resolution = .sevenBit
    let big = IncomingMessage(kind: .nrpn, channel: 1, number: 9, value: 9000)
    guard sevenBit.matches(big) else { fatalError("the test message should be addressed here") }
    guard !sevenBit.captureValue(big), sevenBit.values.isEmpty else {
        fatalError("a value past the ceiling was collected: \(sevenBit.values.map(\.number))")
    }
    print("  past the resolution's ceiling is skipped, not clamped ✓")

    // No list to append to.
    var switchedOff = valueLearnCombo()
    switchedOff.useValues = false
    guard !switchedOff.captureValue(addressed(0)), switchedOff.values.isEmpty else {
        fatalError("Value List is off; nothing should be collected")
    }
    var header = CanvasElement(type: .header, rect: CGRect(x: 0, y: 0, width: 120, height: 28))
    header.useValues = true
    guard !header.captureValue(addressed(0)) else {
        fatalError("a type with no Value List should collect nothing")
    }
    print("  no list means nothing is collected ✓  switch off, and a type that has none")

    // SysEx never matches, so it never collects - the same rule matches() states,
    // arriving here for free rather than written twice.
    var sysExTarget = valueLearnCombo()
    sysExTarget.output = .sysEx
    guard !sysExTarget.captureValue(addressed(0)),
          !sysExTarget.captureValue(IncomingMessage(kind: .systemExclusive, channel: 0, number: 0, value: 6)),
          sysExTarget.values.isEmpty else {
        fatalError("SysEx should collect nothing")
    }
    guard !sysExTarget.canLearnValues else { fatalError("SysEx should not offer Learn Values") }
    // And the checkbox agrees with the collecting, which is the point of having
    // both: a control that would refuse every message says so before one arrives.
    guard valueLearnCombo().canLearnValues, !switchedOff.canLearnValues, !header.canLearnValues else {
        fatalError("canLearnValues disagrees with what captureValue does")
    }
    var adsrTarget = CanvasElement(type: .adsr, rect: CGRect(x: 0, y: 0, width: 208, height: 120))
    adsrTarget.useValues = true
    guard !adsrTarget.canLearnValues else {
        fatalError("a control with four rows is not addressed as a whole")
    }
    print("  SysEx and multi-row controls are refused ✓  and say so before a message arrives")


    // A 14-bit sweep has 16384 distinct values to offer. The cap is what stops a
    // hand still on the knob from filing all of them.
    var flooded = valueLearnCombo()
    flooded.resolution = .fourteenBit
    for value in 0..<200 { _ = flooded.captureValue(addressed(value)) }
    guard flooded.values.count == ElementOptions.valueLearnMaxEntries else {
        fatalError("the cap did not hold: \(flooded.values.count) entries")
    }
    print("  the cap holds ✓  200 distinct values leave \(ElementOptions.valueLearnMaxEntries)")

    // What Learn wrote is what this then collects against: the two halves of one
    // gesture, and the reason the address has to be right first.
    var learnedThenCollected = CanvasElement(type: .combobox, rect: CGRect(x: 0, y: 0, width: 120, height: 28))
    learnedThenCollected.useValues = true
    learnedThenCollected.values = []
    let fromKnob = IncomingMessage(kind: .controlChange, channel: 7, number: 91, value: 12)
    _ = learnedThenCollected.learn(fromKnob, at: 0)
    guard learnedThenCollected.parameters[0].value != 12 else {
        fatalError("Learn wrote the value; it must only ever write the address")
    }
    guard learnedThenCollected.captureValue(fromKnob),
          learnedThenCollected.values.map(\.number) == [12] else {
        fatalError("the value Learn discarded should be the first one collected")
    }
    print("  Learn takes the address, Learn Values takes the value ✓  from the same message")
}
verifyLearnValues()

// ─── 12. SysEx templates ──────────────────────────────────────────────────
// Every number below is captured output of the value encoders, the checksum
// bytes, the template parser and the assembled message.
print("\nsysex value formats:")

let formatCases: [(String, Int, [Int])] = [
    ("One Byte",    1000, [104]),          ("One Byte",    100, [100]),
    ("MSB/LSB",     1000, [7, 104]),       ("MSB/LSB",     100, [0, 100]),
    ("LSB/MSB",     1000, [104, 7]),       ("LSB/MSB",     100, [100, 0]),
    ("BCD 4 LSB",   1000, [0, 0, 0, 1]),   ("BCD 4 LSB",   100, [0, 0, 1, 0]),
    ("BCD 4 MSB",   1000, [1, 0, 0, 0]),   ("BCD 4 MSB",   100, [0, 1, 0, 0]),
    ("2 Nibbles L", 1000, [8, 14]),        ("2 Nibbles L", 100, [4, 6]),
    ("3 Nibbles L", 1000, [8, 14, 3]),     ("3 Nibbles L", 100, [4, 6, 0]),
    ("4 Nibbles L", 1000, [8, 14, 3, 0]),  ("4 Nibbles L", 100, [4, 6, 0, 0]),
    ("2 Nibbles M", 1000, [14, 8]),        ("2 Nibbles M", 100, [6, 4]),
    ("3 Nibbles M", 1000, [3, 14, 8]),     ("3 Nibbles M", 100, [0, 6, 4]),
    ("4 Nibbles M", 1000, [0, 3, 14, 8]),  ("4 Nibbles M", 100, [0, 0, 6, 4]),
    ("2 ASCII M",   1000, [48, 48]),       ("2 ASCII M",   100, [48, 48]),
    ("3 ASCII M",   1000, [48, 48, 48]),   ("3 ASCII M",   100, [49, 48, 48]),
    ("4 ASCII M",   1000, [49, 48, 48, 48]), ("4 ASCII M", 100, [48, 49, 48, 48]),
]
// The names below are the raw values verbatim, which makes this a
// round-trip check as well as an arithmetic one: a raw value that
// stopped matching would fail here first, and a raw value that stopped
// matching is a .pwork file that stops loading.
for (name, value, want) in formatCases {
    guard let format = ValueFormat(rawValue: name) else {
        fatalError("\"\(name)\" is not a ValueFormat - the raw values have drifted from these names")
    }
    let got = format.encode(value)
    guard got == want else {
        fatalError("\(name).encode(\(value)) = \(got), the reference says \(want)")
    }
    guard got.count == format.byteCount else {
        fatalError("\(name) encodes \(got.count) bytes but reserves \(format.byteCount) slots")
    }
}
print("  all \(ValueFormat.allCases.count) formats match encode_value ✓  (\(formatCases.count) cases)")
// There is no unknown format to degrade from any more: it is a case or it is
// not a ValueFormat at all, and the parser never sees a string.
guard ValueFormat(rawValue: "nonsense") == nil else {
    fatalError("\"nonsense\" should not be a ValueFormat")
}
print("  an unrecognised name is not a format at all ✓  no fallback needed")

print("\nsysex checksums:")
let summed = [0x60, 0x00, 0x07, 0x41]
for (name, want) in [("Roland", 88), ("Yamaha", 88), ("2's com", 88), ("Checksum", 40), ("1's Com", 87)] {
    guard let mode = ChecksumMode(rawValue: name) else {
        fatalError("\"\(name)\" is not a ChecksumMode - the raw values have drifted from these names")
    }
    let got = mode.byte(over: summed)
    guard got == want else { fatalError("checksum \(name) = \(got), the reference says \(want)") }
}
print("  Roland / Yamaha / 2's com are one arithmetic ✓  all 88; Checksum 40, 1's Com 87")

print("\nsysex templates:")
func expectParse(_ template: String, _ format: ValueFormat, _ wantTokens: [String], _ wantStart: Int?, _ wantProblem: String) {
    let parsed = SysEx.parse(template, format: format)
    guard parsed.tokens == wantTokens, parsed.checksumStart == wantStart,
          parsed.problem == wantProblem else {
        fatalError("parse(\(template.debugDescription), \(format)): got tokens=\(parsed.tokens) start=\(String(describing: parsed.checksumStart)) problem=\(parsed.problem.debugDescription) / want tokens=\(wantTokens) start=\(String(describing: wantStart)) problem=\(wantProblem.debugDescription)")
    }
    let shown = wantProblem.isEmpty ? wantTokens.joined(separator: " ") : wantProblem
    print("  \(column(template.isEmpty ? "(empty)" : template, 30)) \(column(format.rawValue, 10)) ✓  \(shown)")
}

// The Waldorf Microwave shape from the original's own comment: the sum covers
// only what follows the bracket, not the maker id in front of it.
expectParse("F0 3E 00 00 ( 60 00 VAL ) F7", .oneByte,
            ["F0", "3E", "00", "00", "60", "00", "VAL", "CS", "F7"], 4, "")
// The frame is added when it is not typed - a line that did not show F0/F7
// would not be the message it claims to be.
expectParse("3E 00 VAL", .oneByte, ["F0", "3E", "00", "VAL", "F7"], nil, "")
// VAL becomes one slot per byte the format produces, so the parsed line can be
// counted against the manual.
expectParse("3E 00 VAL", .msbLsb, ["F0", "3E", "00", "VAL", "VAL", "F7"], nil, "")
// Brackets stuck to their neighbours are still two tokens each, and the index
// shifts by the inserted F0.
expectParse("3E (00 VAL) 41", .oneByte, ["F0", "3E", "00", "VAL", "CS", "41", "F7"], 2, "")
// Lower case is accepted; tokens come back canonical.
expectParse("f0 3e 00 val f7", .oneByte, ["F0", "3E", "00", "VAL", "F7"], nil, "")
// The complaints, which are what the Parsed column shows instead of tokens.
expectParse("F0 41 ) 10 ( F7", .oneByte, [], nil, ") before (")
expectParse("F0 41 ( 10 ( F7", .oneByte, [], nil, "one checksum range: a second (")
expectParse("F0 41 ( ) F7", .oneByte, [], nil, "nothing between ( and )")
expectParse("F0 ZZ F7", .oneByte, [], nil, "not a byte and not a name: ZZ")
expectParse("F0 1FF F7", .oneByte, [], nil, "not a byte: 1FF")
// An empty line is unconfigured, not wrong - no tokens and no complaint.
expectParse("", .oneByte, [], nil, "")

print("\nsysex on the wire (value 100):")
func expectMessage(_ template: String, _ format: ValueFormat, _ mode: ChecksumMode, _ wantData: [UInt8]) {
    // CoreMIDI takes the bytes as given rather than framing them itself, so
    // SysEx.message returns the whole message. The reference data below is
    // the payload alone, so the frame is added back around it here.
    let want = [0xF0] + wantData + [0xF7]
    let got = SysEx.message(template: template, value: 100, checksumMode: mode, format: format)
    guard got == want else {
        fatalError("message(\(template.debugDescription)): got \(got.map { String(format: "%02X", $0) }), want \(want.map { String(format: "%02X", $0) })")
    }
    print("  \(column(format.rawValue, 10)) \(column(mode.rawValue, 9)) ✓  \(got.map { String(format: "%02X", $0) }.joined(separator: " "))")
}
expectMessage("F0 3E 00 00 ( 60 00 VAL ) F7", .oneByte, .roland,
              [0x3E, 0x00, 0x00, 0x60, 0x00, 0x64, 0x3C])
expectMessage("F0 3E 00 00 ( 60 00 VAL ) F7", .oneByte, .sum,
              [0x3E, 0x00, 0x00, 0x60, 0x00, 0x64, 0x44])
expectMessage("F0 3E 00 00 ( 60 00 VAL ) F7", .msbLsb, .roland,
              [0x3E, 0x00, 0x00, 0x60, 0x00, 0x00, 0x64, 0x3C])
expectMessage("F0 43 10 VAL F7", .twoASCII, .roland, [0x43, 0x10, 0x30, 0x30])
// A data byte mistyped as FF is clamped: everything between F0 and F7 has to
// be seven-bit, and a status byte inside a message would shift the device's
// parse of everything after it.
expectMessage("F0 41 FF VAL F7", .oneByte, .roland, [0x41, 0x7F, 0x64])

// An unsound template sends nothing at all - not a bare F0 F7.
for bad in ["F0 ZZ F7", "F0 41 ( F7", ""] {
    guard SysEx.message(template: bad, value: 100).isEmpty else {
        fatalError("an unsound template must send nothing: \(bad.debugDescription)")
    }
}
print("  an unsound or empty template sends nothing ✓  not even a bare F0 F7")

// And through the element, which is how it is actually reached.
var sysexKnob = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))
sysexKnob.output = .sysEx
sysexKnob.checksum = .roland
sysexKnob.valueFormat = .oneByte
sysexKnob.parameters[0].sysex = "F0 3E 00 00 ( 60 00 VAL ) F7"
sysexKnob.parameters[0].value = 100
let planned = sysexKnob.midiMessages
guard planned.count == 1, planned[0].kind == .systemExclusive,
      planned[0].bytes == [0xF0, 0x3E, 0x00, 0x00, 0x60, 0x00, 0x64, 0x3C, 0xF7] else {
    fatalError("the element planned \(planned.map(\.description))")
}
print("  a SysEx element plans one message ✓  \(planned[0].description)")
sysexKnob.parameters[0].sysex = ""
guard sysexKnob.midiMessages.isEmpty else {
    fatalError("an element with no template should plan nothing")
}
print("  with no template it plans nothing ✓  unconfigured, not an error")

// ─── 13. Envelope nodes and pad points ────────────────────────────────────
// Captured reference values, not transcribed by reading the drawing code.
//
// The plot rect is passed in explicitly rather than derived, because how a
// plot is arrived at and what it means are two different questions: the
// label strip may be subtracted from the element rect or already excluded by
// the canvas. What has to hold is the mapping from a pointer position to
// values, given one plot - which is exactly what these functions take.
print("\nenvelope shapes:")

func envelope(_ type: ElementType, _ w: CGFloat, _ h: CGFloat) -> CanvasElement {
    CanvasElement(type: type, rect: CGRect(x: 0, y: 0, width: w, height: h))
}
func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool {
    abs(a - b) <= tolerance
}

for (type, wantValues, wantAxis, wantPoints) in [
    (ElementType.ad, [12, 60], CGFloat(4), [(CGFloat(0), CGFloat(0)), (0.189, 1), (1.1339, 0)]),
    (.adsr, [20, 50, 76, 40], CGFloat(7),
     [(CGFloat(0), CGFloat(0)), (0.315, 1), (1.1024, 0.5984), (2.1024, 0.5984), (2.7323, 0)]),
    (.mseg, [63, 32, 63, 64, 63, 95, 63], CGFloat(8),
     [(CGFloat(0), CGFloat(0)), (0.9921, 0.252), (1.9843, 0.5039), (2.9764, 0.748), (3.9685, 0)]),
] {
    let element = envelope(type, 208, 120)
    guard element.parameterValues == wantValues else {
        fatalError("\(type) seeds are \(element.parameterValues), the reference is \(wantValues)")
    }
    let (points, axis) = envelopePoints(element)
    guard close(axis, wantAxis), points.count == wantPoints.count,
          zip(points, wantPoints).allSatisfy({ close($0.t, $1.0) && close($0.level, $1.1) }) else {
        fatalError("\(type) shape is \(points) axis \(axis), the reference says \(wantPoints) axis \(wantAxis)")
    }
    print("  \(column(type.rawValue, 6)) ✓  axis \(axis), \(points.count) corners, seeds match the blueprint")
}

// Which corners can be grabbed. ADSR's held segment ends and both envelopes'
// final corners carry no level - they land at zero by definition.
func handleTuples(_ element: CanvasElement) -> [(Int, Int, Int?)] {
    envelopeHandles(element).map { ($0.point, $0.timeRow, $0.levelRow) }
}
func sameHandles(_ got: [(Int, Int, Int?)], _ want: [(Int, Int, Int?)]) -> Bool {
    got.count == want.count && zip(got, want).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
}
guard sameHandles(handleTuples(envelope(.ad, 208, 120)), [(1, 0, nil), (2, 1, nil)]),
      sameHandles(handleTuples(envelope(.adsr, 208, 120)), [(1, 0, nil), (2, 1, 2), (4, 3, nil)]),
      sameHandles(handleTuples(envelope(.mseg, 280, 120)), [(1, 0, 1), (2, 2, 3), (3, 4, 5), (4, 6, nil)]) else {
    fatalError("the handle tables differ from render.ENVELOPE_HANDLES")
}
print("  handles match ENVELOPE_HANDLES ✓  and an MSEG's release node carries no level row")

print("\ngrabbing an envelope node:")
// The reference plot for a 208x120 ADSR.
let adsrPlot = CGRect(x: 7, y: 7, width: 194, height: 91)
let adsr = envelope(.adsr, 208, 120)
let wantNodes: [(CGFloat, CGFloat)] = [(7, 98), (15.729, 7), (37.551, 43.543), (65.265, 43.543), (82.723, 98)]
let gotNodes = envelopeNodes(adsr, plot: adsrPlot)
guard gotNodes.count == wantNodes.count,
      zip(gotNodes, wantNodes).allSatisfy({ close($0.x, $1.0) && close($0.y, $1.1) }) else {
    fatalError("nodes are \(gotNodes), the reference says \(wantNodes)")
}
print("  the corners land where render.envelope_nodes puts them ✓")

// The grab radius: 9 points, and generous next to the 2.5-point dot.
let peak = gotNodes[1]
guard adsr.nodeIndex(at: peak, plot: adsrPlot) == 0,
      adsr.nodeIndex(at: CGPoint(x: peak.x + 8, y: peak.y + 4), plot: adsrPlot) == 0,
      adsr.nodeIndex(at: CGPoint(x: peak.x + 20, y: peak.y), plot: adsrPlot) == nil else {
    fatalError("the grab radius does not match control.node_at")
}
print("  grabbed within 9pt, missed beyond it ✓  empty field grabs nothing at all")

// Dragging the decay/sustain corner: its time is the run *into* it, so what
// the pointer gives is a position on the axis minus where the previous corner
// sits - and it is clamped there, since a stage cannot run backwards.
for (target, want) in [
    (CGPoint(x: 60, y: 20), [20, 101, 109, 40]),
    (CGPoint(x: 100, y: 60), [20, 127, 53, 40]),
    (CGPoint(x: 5, y: 110), [20, 0, 0, 40]),
] {
    var moving = envelope(.adsr, 208, 120)
    guard moving.dragNode(1, to: target, plot: adsrPlot) else {
        fatalError("dragging to \(target) should have moved something")
    }
    guard moving.parameterValues == want else {
        fatalError("drag to \(target) gave \(moving.parameterValues), the reference says \(want)")
    }
    print("  drag corner 2 to (\(Int(target.x)),\(Int(target.y))) ✓  \(moving.parameterValues)")
}
// Both its rows moved together - one gesture, a length and a level.
var pair = envelope(.adsr, 208, 120)
_ = pair.dragNode(1, to: CGPoint(x: 60, y: 20), plot: adsrPlot)
guard pair.parameterValue(0) == 20, pair.parameterValue(3) == 40 else {
    fatalError("dragging one corner moved another stage")
}
print("  it moves that corner's two rows and no others ✓")

print("\ngrabbing a pad point:")
let padPlotXY = CGRect(x: 8.75, y: 8.75, width: 142.5, height: 143.5)
let pad = envelope(.xyPad, 160, 176)
guard pad.parameterValues == [64, 64] else {
    fatalError("a fresh pad should start centred, has \(pad.parameterValues)")
}
guard let padDot = padNode(pad, plot: padPlotXY, point: (x: 0, y: 1)),
      close(padDot.x, 80.56, 0.01), close(padDot.y, 79.94, 0.01) else {
    fatalError("the pad's point is not where render.pad_node puts it")
}
print("  the point lands where render.pad_node puts it ✓  (80.56, 79.94)")

for (target, want) in [
    (CGPoint(x: padPlotXY.minX, y: padPlotXY.maxY), [0, 0]),
    (CGPoint(x: padPlotXY.maxX, y: padPlotXY.minY), [127, 127]),
] {
    var moving = envelope(.xyPad, 160, 176)
    guard moving.dragPad(0, to: target, plot: padPlotXY), moving.parameterValues == want else {
        fatalError("pad drag to \(target) gave \(moving.parameterValues), the reference says \(want)")
    }
}
print("  bottom-left is 0,0 and top-right is full scale ✓  up is more")
// Sliding to where the point already is reports nothing - one mouse move
// saying nothing would be one message saying nothing.
var unmovedPad = envelope(.xyPad, 160, 176)
guard !unmovedPad.dragPad(0, to: padDot, plot: padPlotXY) else {
    fatalError("dragging a point to where it already is should report no change")
}
print("  a drag that changes nothing reports nothing ✓")

// A quad grabs the nearer of its two points and holds it.
let quadPlot = CGRect(x: 8.75, y: 8.75, width: 182.5, height: 187.5)
let quad = envelope(.xyQuad, 200, 220)
guard quad.parameterValues == [40, 40, 88, 88] else {
    fatalError("a fresh quad should start apart, has \(quad.parameterValues)")
}
let quadDots = padPoints(quad).compactMap { padNode(quad, plot: quadPlot, point: $0) }
guard quadDots.count == 2,
      close(quadDots[0].x, 66.23, 0.01), close(quadDots[0].y, 137.19, 0.01),
      close(quadDots[1].x, 135.21, 0.01), close(quadDots[1].y, 66.33, 0.01) else {
    fatalError("the quad's points are not where render.pad_node puts them")
}
guard quad.padPointIndex(at: CGPoint(x: quadPlot.minX, y: quadPlot.maxY), plot: quadPlot) == 0,
      quad.padPointIndex(at: CGPoint(x: quadPlot.maxX, y: quadPlot.minY), plot: quadPlot) == 1 else {
    fatalError("the quad grabbed the wrong point")
}
var quadMoving = envelope(.xyQuad, 200, 220)
guard quadMoving.dragPad(1, to: CGPoint(x: quadPlot.maxX, y: quadPlot.minY), plot: quadPlot),
      quadMoving.parameterValues == [40, 40, 127, 127] else {
    fatalError("the quad moved \(quadMoving.parameterValues), the reference says [40, 40, 127, 127]")
}
print("  a quad grabs the nearer point and moves only its two rows ✓  \(quadMoving.parameterValues)")

// An inverted axis sends the opposite of where the point sits, so the drag
// unmovedPad feels ordinary and padNode mirrors it back to where it was dropped.
var inverted = envelope(.xyPad, 160, 176)
inverted.parameters[1].inverted = true
_ = inverted.dragPad(0, to: CGPoint(x: padPlotXY.maxX, y: padPlotXY.minY), plot: padPlotXY)
guard inverted.parameterValues == [127, 0] else {
    fatalError("an inverted axis should send the opposite, got \(inverted.parameterValues)")
}
guard let backAgain = padNode(inverted, plot: padPlotXY, point: (x: 0, y: 1)),
      close(backAgain.y, padPlotXY.minY, 0.01) else {
    fatalError("an inverted point should be drawn where it was dropped")
}
print("  an inverted axis sends the opposite, and still draws where dropped ✓")

// ─── 14. Rolling a control ────────────────────────────────────────────────
// A roll is luck, so the assertions are the invariants rather than the
// numbers: what a type may land on, and what it must never land on. Each is
// run enough times that a rule broken on one path in ten would show.
print("\nrandom:")

let rolls = 400

func rolled(_ type: ElementType, _ w: CGFloat, _ h: CGFloat, _ prepare: (inout CanvasElement) -> Void = { _ in }) -> CanvasElement {
    var element = CanvasElement(type: type, rect: CGRect(x: 0, y: 0, width: w, height: h))
    element.random = true
    prepare(&element)
    return element
}

// Every rolled value stays inside the element's own domain, at both widths.
for resolution in Resolution.allCases {
    var knob = rolled(.knob, 72, 88) { $0.resolution = resolution }
    let ceiling = knob.valueCeiling
    var seen: Set<Int> = []
    for _ in 0..<rolls {
        _ = knob.randomise()
        let value = knob.parameterValue(0)
        guard (0...ceiling).contains(value) else {
            fatalError("a roll left \(resolution) at \(value), outside 0...\(ceiling)")
        }
        seen.insert(value)
    }
    // And it really is rolling, not returning the same number.
    guard seen.count > 1 else { fatalError("a knob rolled the same value \(rolls) times") }
    print("  \(column(resolution.rawValue, 7)) knob stays in 0...\(ceiling) ✓  \(seen.count) distinct values in \(rolls) rolls")
}

// A control carrying named values lands *on* an entry, never between two -
// "halfway between Saw and Square" is not a waveform.
var listed = rolled(.knob, 72, 88) {
    $0.useValues = true
    $0.values = [ValueEntry(name: "Saw", number: 0), ValueEntry(name: "Square", number: 40),
                 ValueEntry(name: "Sine", number: 100)]
}
let numbers = Set(listed.values.map(\.number))
var landedOn: Set<Int> = []
for _ in 0..<rolls {
    _ = listed.randomise()
    let value = listed.parameterValue(0)
    guard numbers.contains(value) else {
        fatalError("a roll landed on \(value), which is not one of \(numbers.sorted())")
    }
    landedOn.insert(value)
}
guard landedOn == numbers else {
    fatalError("only \(landedOn.sorted()) of \(numbers.sorted()) were ever reached")
}
print("  a value list lands on entries only ✓  all three reached, nothing in between")

// The switch is what says whether the list is in force: off, a knob rolls its
// whole range again.
var unlisted = listed
unlisted.useValues = false
var offList = false
for _ in 0..<rolls {
    _ = unlisted.randomise()
    if !numbers.contains(unlisted.parameterValue(0)) { offList = true }
}
guard offList else { fatalError("with Value List off, a knob should roll its whole range") }
print("  with Value List off it rolls the whole range ✓")

// A shape rolls every row it has - one stage rerolled is not a new shape.
var envelopeRoll = rolled(.adsr, 208, 120)
var movedRows = Set<Int>()
for _ in 0..<rolls {
    let before = envelopeRoll.parameterValues
    _ = envelopeRoll.randomise()
    for (row, value) in envelopeRoll.parameterValues.enumerated() where value != before[row] {
        movedRows.insert(row)
    }
}
guard movedRows == Set(0..<4) else {
    fatalError("an ADSR roll moved only rows \(movedRows.sorted())")
}
print("  an envelope rolls every row ✓  all four stages move")

var quadRoll = rolled(.xyQuad, 200, 220)
var quadRows = Set<Int>()
for _ in 0..<rolls {
    let before = quadRoll.parameterValues
    _ = quadRoll.randomise()
    for (row, value) in quadRoll.parameterValues.enumerated() where value != before[row] {
        quadRows.insert(row)
    }
}
guard quadRows == Set(0..<4) else { fatalError("a quad roll moved only \(quadRows.sorted())") }
print("  a pad rolls both its points ✓  all four axes move")

// A checkbox is a coin; a radio lands on a segment; a combo box on an entry.
var coin = rolled(.checkbox, 120, 32)
var faces = Set<Bool>()
for _ in 0..<rolls { _ = coin.randomise(); faces.insert(coin.checked) }
guard faces == [true, false] else { fatalError("a checkbox never reached both faces") }

var rolledStrip = rolled(.radio, 240, 56) { $0.segmentCount = 4 }
var segments = Set<Int>()
for _ in 0..<rolls {
    _ = rolledStrip.randomise()
    guard (1...4).contains(rolledStrip.selected) else {
        fatalError("a radio rolled segment \(rolledStrip.selected), outside 1...4")
    }
    segments.insert(rolledStrip.selected)
}
guard segments == Set(1...4) else { fatalError("a radio reached only \(segments.sorted())") }

var dropdown = rolled(.combobox, 160, 56) {
    $0.values = [ValueEntry(name: "A", number: 0), ValueEntry(name: "B", number: 1)]
}
for _ in 0..<rolls {
    _ = dropdown.randomise()
    guard (1...2).contains(dropdown.selected) else {
        fatalError("a combo box rolled \(dropdown.selected), outside 1...2")
    }
}
print("  checkbox, radio and combo box land where they are read ✓  both faces, all four segments")

// What must never roll.
print("\nwhat a roll leaves alone:")
// A button marked Random would be a button that presses itself.
for type in [ElementType.random, .sendAll, .panic, .midiPlayer] {
    let button = rolled(type, 112, 40)
    guard !button.isRandomisable else { fatalError("\(type) should never be randomisable") }
}
print("  a button is never randomisable ✓  even with the flag set")

// Furniture and the display elements have nothing to roll.
for type in [ElementType.header, .label, .led, .status, .monitor] {
    var furniture = rolled(type, 200, 28)
    guard !furniture.randomise() else { fatalError("\(type) should have nothing to roll") }
}
print("  furniture and displays roll nothing ✓")

// The flag is what decides, and a whole canvas rolls only what is marked.
var canvasPage = [
    rolled(.knob, 72, 88),
    CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88)),   // random off
    rolled(.panic, 112, 40),
]
canvasPage[0].parameters[0].value = 0
canvasPage[1].parameters[0].value = 64
var everMoved = false
for _ in 0..<rolls {
    let moved = canvasPage.randomiseMarked()
    guard canvasPage[1].parameterValue(0) == 64 else {
        fatalError("an element with Random off was rolled anyway")
    }
    guard !moved.contains(where: { $0.type == .panic }) else {
        fatalError("a button was rolled")
    }
    if !moved.isEmpty { everMoved = true }
}
guard everMoved else { fatalError("nothing was ever rolled on the whole canvas") }
print("  a canvas rolls only what is marked ✓  the unmarked knob never left 64")

// ─── 15. Reading and playing a MIDI file ──────────────────────────────────
// The file below was built byte by byte and then read by an independent
// parser; both its bytes and that answer are embedded here. It is
// deliberately awkward: two
// tracks meant to sound together, a tempo change partway through, running
// status, a text meta event that must be dropped, and a SysEx.
print("\nmidi files:")

let mixedFile: [UInt8] = [
    0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x01, 0xE0,
    0x4D, 0x54, 0x72, 0x6B, 0x00, 0x00, 0x00, 0x2D, 0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1,
    0x20, 0x00, 0xFF, 0x01, 0x04, 0x68, 0x69, 0x79, 0x61, 0x00, 0x90, 0x3C, 0x64, 0x81,
    0x70, 0x50, 0x00, 0x81, 0x70, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40, 0x83, 0x60, 0x90,
    0x40, 0x5A, 0x81, 0x70, 0x80, 0x40, 0x40, 0x00, 0xFF, 0x2F, 0x00, 0x4D, 0x54, 0x72,
    0x6B, 0x00, 0x00, 0x00, 0x14, 0x00, 0xB1, 0x4A, 0x0A, 0x78, 0xF0, 0x05, 0x43, 0x10,
    0x4C, 0x01, 0xF7, 0x84, 0x58, 0xC2, 0x07, 0x00, 0xFF, 0x2F, 0x00,
]
let mixedWanted: [(TimeInterval, [UInt8])] = [
    (0.0,   [144, 60, 100]),        // note on, track 1
    (0.0,   [177, 74, 10]),         // CC on channel 2, track 2 - same instant
    (0.125, [240, 67, 16, 76, 1, 247]),   // SysEx, its length byte gone
    (0.25,  [144, 80, 0]),          // running status: no status byte in the file
    (1.0,   [194, 7]),              // program change - one data byte, not two
    (1.5,   [144, 64, 90]),         // after the tempo change, so twice as slow
    (2.0,   [128, 64, 64]),
]

let mixed = try MIDIFile.parse(Data(mixedFile)).events
guard mixed.count == mixedWanted.count else {
    fatalError("parsed \(mixed.count) events, the reference says \(mixedWanted.count)")
}
for (got, want) in zip(mixed, mixedWanted) {
    guard got.bytes == want.1, abs(got.time - want.0) < 1e-9 else {
        fatalError("event \(got) differs from the reference \(want)")
    }
}
print("  a two-track file with a tempo change ✓  \(mixed.count) events, byte for byte")
print("    tracks merged by tick, meta dropped, running status resolved,")
print("    SysEx reassembled, and everything after the tempo change twice as slow")

// Two real files, from a sequencer rather than from this test's own idea of
// the format - see Verification/Fixtures.
//
// Found relative to the working directory, so the harness has to be run from
// the repository root - which is where it is compiled from too (see the top of
// this file). #filePath would seem like the better answer and is not: the
// compiler was handed a relative path, so that is what it holds.
let fixtures = URL(fileURLWithPath: "Verification/Fixtures")
// The fourth number is the one worth having here. A file's length is what its
// End of Track says, not when it last made a sound: PatchWork.mid is two bars
// at 100bpm - 4.8s - whose last note-off is at 4.485. Measuring it by its own
// events drops that half-beat rest, and a loop then restarts half a beat early,
// every pass, for ever. PatchWork 2.mid ends *on* its last event, which is why
// that one always looped correctly and this one never did.
for (file, count, last, length) in [("PatchWork.mid", 58, 4.485, 4.8),
                                    ("PatchWork 2.mid", 592, 35.555584, 35.555584)] {
    let path = fixtures.appendingPathComponent(file).path
    guard let data = FileManager.default.contents(atPath: path) else {
        // They live in the repository now, so missing means a broken checkout
        // rather than an optional extra.
        fatalError("missing fixture \(path) - run this from the repository root, not \(FileManager.default.currentDirectoryPath)")
    }
    let parsed = try MIDIFile.parse(data)
    let events = parsed.events
    guard abs(parsed.duration - length) < 1e-5 else {
        fatalError("\(file): runs \(parsed.duration)s, the reference says \(length)s")
    }
    guard events.count == count, let end = events.last?.time, abs(end - last) < 1e-5 else {
        fatalError("\(file): \(events.count) events ending at \(events.last?.time ?? -1), the reference says \(count) ending at \(last)")
    }
    print("  \(column(file, 16)) ✓  \(count) events, last at \(String(format: "%.3f", last))s, runs \(String(format: "%.3f", length))s")
}

// A file that is not one has to complain rather than crash, and a header with
// no tracks is a legal empty file rather than an error.
for (name, bytes) in [
    ("empty", [UInt8]()),
    ("plain text", Array("this is not a midi file".utf8)),
    ("truncated track", Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
                        + Array("MTrk".utf8) + [0, 0, 0, 40, 0x00, 0x90]),
] {
    do {
        _ = try MIDIFile.parse(Data(bytes))
        fatalError("\(name) should not have parsed")
    } catch {
        print("  \(column(name, 16)) ✓  refused: \(error.localizedDescription)")
    }
}
let headerOnly = try MIDIFile.parse(Data(Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 0, 0x01, 0xE0]))
guard headerOnly.events.isEmpty, headerOnly.duration == 0 else {
    fatalError("a file with no tracks should parse to nothing")
}
print("  \(column("no tracks", 16)) ✓  a legal file with nothing to play, not an error")

// A file that never says where it ends falls back to its own last event, which
// is what the length used to be for every file.
let noEnd = try MIDIFile.parse(Data(
    Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
    + Array("MTrk".utf8) + [0, 0, 0, 0x08, 0x00, 0x90, 0x3C, 0x64, 0x18, 0x80, 0x3C, 0x40]
))
guard noEnd.events.count == 2, abs(noEnd.duration - 0.025) < 1e-9 else {
    fatalError("a file with no End of Track should run to its last event, not \(noEnd.duration)")
}
print("  \(column("no end of track", 16)) ✓  falls back to the last event, \(noEnd.duration)s")

// System common and real time have no business in a track, but they turn up in
// files dumped from a live stream - and each carries its own number of data
// bytes, never the two a channel message has. Read as a channel message, an F8
// eats the next delta time and every event after it in that track lands at a
// nonsensical moment. Here an F8 (no data) and an F1 (one) sit between three
// notes that must still be 25ms apart.
let interrupted = try MIDIFile.parse(Data(
    Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0]
    + Array("MTrk".utf8) + [0, 0, 0, 0x15,
                            0x00, 0x90, 0x3C, 0x64,
                            0x00, 0xF8,                 // clock: no data bytes
                            0x18, 0x80, 0x3C, 0x40,
                            0x00, 0xF1, 0x20,           // quarter frame: one
                            0x18, 0x90, 0x43, 0x64,
                            0x00, 0xFF, 0x2F, 0x00]
))
let interruptedWanted: [(TimeInterval, [UInt8])] = [
    (0.0,   [0x90, 0x3C, 0x64]),
    (0.025, [0x80, 0x3C, 0x40]),
    (0.05,  [0x90, 0x43, 0x64]),
]
guard interrupted.events.count == interruptedWanted.count else {
    fatalError("real-time bytes desynchronised the track: \(interrupted.events)")
}
for (got, want) in zip(interrupted.events, interruptedWanted) {
    guard got.bytes == want.1, abs(got.time - want.0) < 1e-9 else {
        fatalError("event \(got) differs from \(want) - the data counts are wrong")
    }
}
print("  \(column("stream leftovers", 16)) ✓  F8 and F1 stepped over, the notes still 25ms apart")

// Tick arithmetic. A positive division is ticks per quarter note, so the tempo
// decides how long one lasts; a negative one is SMPTE, which is real time and
// which no tempo can alter.
guard MIDIFile.ticksToSeconds(480, division: 480, tempo: 500_000) == 0.5,
      MIDIFile.ticksToSeconds(480, division: 480, tempo: 600_000) == 0.6,
      MIDIFile.ticksToSeconds(240, division: 480, tempo: 500_000) == 0.25 else {
    fatalError("ticks per quarter note convert wrongly")
}
let smpte = 0xE728          // 25 frames a second, 40 ticks a frame
guard abs(MIDIFile.ticksToSeconds(1000, division: smpte, tempo: 500_000) - 1) < 1e-9,
      abs(MIDIFile.ticksToSeconds(1000, division: smpte, tempo: 900_000) - 1) < 1e-9 else {
    fatalError("SMPTE division should be real time whatever the tempo")
}
print("  tick arithmetic ✓  480/quarter at two tempos, SMPTE ignoring tempo entirely")

print("\nplaying:")
// A file whose three events span 50ms and which then rests until 100ms, where
// its End of Track is. The rest is the point: it is what the loop used to drop.
let tinyFile: [UInt8] = [
    0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x01, 0x01, 0xE0,
    0x4D, 0x54, 0x72, 0x6B, 0x00, 0x00, 0x00, 0x17, 0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1,
    0x20, 0x00, 0x90, 0x3C, 0x64, 0x18, 0x80, 0x3C, 0x40, 0x18, 0x90, 0x43, 0x64, 0x30,
    0xFF, 0x2F, 0x00,
]
let tinyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("patchwork-tiny.mid")
try Data(tinyFile).write(to: tinyURL)

let player = MIDIPlayer()
guard player.name == nil, !player.playing else { fatalError("a fresh player holds nothing") }
try player.load(tinyURL)
guard player.name == "patchwork-tiny.mid", abs(player.duration - 0.1) < 1e-9 else {
    fatalError("loaded \(player.name ?? "nothing"), duration \(player.duration)")
}
print("  loading reads the file once, up front ✓  100ms, and the name is what the element shows")
print("    the last event is at 50ms; the length is what End of Track says, not that")

// Loading something unreadable throws *before* anything plays, and leaves the
// player as it was.
let notMIDI = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("patchwork-not.mid")
try Data("nope".utf8).write(to: notMIDI)
do {
    try player.load(notMIDI)
    fatalError("loading a non-MIDI file should have thrown")
} catch {
    print("  a file that cannot be read throws before playing ✓  \(error.localizedDescription)")
}

/// Stands in for the output, and keeps each message's timestamp as well as
/// its bytes - the timestamp is what the player is now actually doing, so it
/// is what has to be checked.
///
/// `nonisolated` and locked, because the refill loop is not on the main actor
/// any more: this is written from the global executor and read from the run
/// loop below, which is exactly what a lock is for. `@unchecked` is honest
/// here - the lock *is* the checking.
///
/// It answers nil or a complaint rather than a Bool, the same as the real
/// thing: the reason a send failed used to be written straight to `lastError`
/// and now has to be carried back to the main actor instead.
nonisolated final class Wire: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(bytes: [UInt8], at: MIDITimeStamp)] = []
    private var accepting = true

    var accept: Bool {
        get { lock.withLock { accepting } }
        set { lock.withLock { accepting = newValue } }
    }
    var sent: [(bytes: [UInt8], at: MIDITimeStamp)] { lock.withLock { recorded } }
    var bytes: [[UInt8]] { sent.map(\.bytes) }

    func send(_ bytes: [UInt8], at timeStamp: MIDITimeStamp) -> String? {
        lock.withLock {
            guard accepting else { return "the wire refused it" }
            recorded.append((bytes, timeStamp))
            return nil
        }
    }
}
let wire = Wire()
var complaint: String?

try player.load(tinyURL)
player.play(send: { wire.send($0, at: $1) }, silence: {}, onError: { complaint = $0 })
guard player.playing else { fatalError("play should have started it") }
guard wait(upTo: 2, until: { wire.sent.count >= 3 }) else {
    fatalError("nothing was sent: \(wire.sent.count)")
}
let firstPass = Array(wire.bytes.prefix(3))
guard firstPass == [[0x90, 60, 100], [0x80, 60, 64], [0x90, 67, 100]] else {
    fatalError("the file did not play in order: \(firstPass)")
}
print("  the file goes out in order ✓  \(firstPass.map { $0.map { String(format: "%02X", $0) }.joined() }.joined(separator: " "))")

// And it loops - the point of it.
guard wait(upTo: 2, until: { wire.sent.count >= 6 }) else {
    fatalError("it played once and stopped; it should loop")
}
guard Array(wire.bytes[3..<6]) == firstPass else {
    fatalError("the second pass differs from the first: \(Array(wire.bytes[3..<6]))")
}
print("  and loops ✓  \(wire.sent.count) messages by now, the second pass identical to the first")

// The timestamps are the point of the whole arrangement, so they are what
// gets checked - not the wall-clock moment each send happened, which is
// exactly the thing that no longer has to be right.
//
// This file's three events sit at 0, 25ms and 50ms, and it runs to 100ms -
// where its End of Track is. So a loop puts the next pass's first event 50ms
// after this pass's last, and the expected gaps are 25, 25, **50** at the loop
// point, then 25, 25.
//
// That 50 used to be a 0, and it was the bug: the length was taken from the
// last event rather than from End of Track, so every pass dropped the trailing
// rest and the next one began on the same instant as the previous one's final
// note. A file ending on a bar line looped half a beat early for ever, and the
// two events sharing an instant were an audible double-hit at the seam.
let ticks25ms = MIDIHostClock.ticks(0.025)
let ticks50ms = MIDIHostClock.ticks(0.05)
let tolerance = MIDIHostClock.ticks(0.001)      // a tick is 1/24,000,000s
let stamps = wire.sent.prefix(6).map(\.at)
let wantGaps = [ticks25ms, ticks25ms, ticks50ms, ticks25ms, ticks25ms]
for (index, pair) in zip(stamps, stamps.dropFirst()).enumerated() {
    guard pair.1 >= pair.0 else {
        fatalError("timestamp \(index + 1) goes backwards from \(index): \(pair.0) then \(pair.1)")
    }
    let gap = pair.1 &- pair.0
    let want = wantGaps[index]
    guard gap + tolerance >= want, gap <= want + tolerance else {
        fatalError("gap \(index)→\(index + 1) is \(gap) ticks, wanted \(want)")
    }
}
print("  every event is stamped with when it is due ✓  25ms, 25ms, 50ms at the loop point, 25ms, 25ms")

// And they are handed over *ahead* of being due - which is what makes the
// timing the driver's rather than this loop's.
guard stamps.last! > MIDIHostClock.now else {
    fatalError("the window was scheduled into the past - nothing is being scheduled ahead")
}
print("  and handed over before it is due ✓  the window is still in the future")

// Stopping silences what the file was in the middle of - twice, and both are
// needed. The refill is on the global executor now, so a stop lands *between
// threads* rather than between statements: a send can be in flight at the very
// moment the flush happens, and a packet handed over after a flush is one the
// flush could not take back. The first silence is what makes the stop
// immediate; the second, once the run has actually let go, is what makes it
// complete. At most one message can be in flight, because the loop checks for
// cancellation before every send.
var silenced = 0
player.stop(silence: { silenced += 1 })
guard !player.playing, silenced == 1 else { fatalError("stop should have stopped and silenced") }
guard wait(upTo: 1, until: { silenced >= 2 }) else {
    fatalError("the stop should silence again once the run has let go")
}
let afterStop = wire.sent.count
_ = wait(upTo: 0.4, until: { false })
guard wire.sent.count == afterStop else {
    fatalError("\(wire.sent.count - afterStop) messages went out after the run ended")
}
print("  stopping ends it and silences ✓  immediately, and again once the run let go")
// A second stop does not silence again - there is nothing being held.
silenced = 0
player.stop(silence: { silenced += 1 })
guard silenced == 0 else { fatalError("stopping an idle player should not silence") }
print("  stopping an idle player silences nothing ✓")

// A stop immediately followed by a play - which is exactly what dropping a
// file on a playing element does - must not silence the run that replaced it.
// The second silence waits for the old run to let go, and that wait outlasts
// the main actor's turn: without a check it lands after the new run has
// committed its first window and flushes it away.
var lateSilences = 0
try player.load(tinyURL)
player.play(send: { wire.send($0, at: $1) }, silence: {}, onError: { complaint = $0 })
guard wait(upTo: 2, until: { wire.sent.count > 0 }) else { fatalError("it did not start") }
player.stop(silence: { lateSilences += 1 })
try player.load(tinyURL)                    // a fresh drop, same as ContentView does
player.play(send: { wire.send($0, at: $1) }, silence: {}, onError: { complaint = $0 })
let restarted = wire.sent.count
_ = wait(upTo: 0.5, until: { false })
guard lateSilences == 1 else {
    fatalError("the replaced run silenced \(lateSilences) times over the top of its successor")
}
guard player.playing, wire.sent.count > restarted else {
    fatalError("the replacement run should still be going")
}
player.stop()
print("  a drop that replaces a playing file ✓  the old run does not silence the new one")

// A press resumes the file still loaded, and the file outlives the stop.
guard player.name != nil else { fatalError("the file should outlive a stop") }
var pressSilenced = false
player.toggle(send: { wire.send($0, at: $1) }, silence: { pressSilenced = true },
              onError: { complaint = $0 })
guard player.playing else { fatalError("a press should have resumed it") }
guard !pressSilenced else { fatalError("starting should not silence") }
player.toggle(send: { wire.send($0, at: $1) }, silence: { pressSilenced = true },
              onError: { complaint = $0 })
guard !player.playing else { fatalError("a second press should have stopped it") }
// The press that stops has to silence what the file was in the middle of: a
// stop can land between a note on and its note off, and that note would
// otherwise be held for ever - and it has to take back the window that was
// scheduled ahead, or the stop would only arrive a fifth of a second later.
guard pressSilenced else { fatalError("the press that stopped it should have silenced") }
print("  a press resumes what is loaded, and the next one stops it ✓  and that one silences")

// A failing send ends the run rather than spending the rest of the file
// failing once per message.
wire.accept = false
complaint = nil
var failSilenced = false
player.play(send: { wire.send($0, at: $1) }, silence: { failSilenced = true },
            onError: { complaint = $0 })
guard wait(upTo: 2, until: { complaint != nil }) else {
    fatalError("a failing send should have been reported")
}
guard !player.playing else { fatalError("a failing send should have ended the run") }
// And it has to silence, which it did not used to. A send can fail between a
// note on and its note off just as a stop can land there, and the run simply
// ending leaves that note held by whatever still hears it.
guard failSilenced else { fatalError("a failing send should have silenced too") }
print("  a failed send stops the run, silences, and says so ✓  \"\(complaint ?? "")\"")

try? FileManager.default.removeItem(at: tinyURL)
try? FileManager.default.removeItem(at: notMIDI)

// ─── 16. The document, and the lock ───────────────────────────────────────
// The lock belongs to the layout rather than to any element in it, which is
// why the file became an object. That round trip is what this checks; where
// the lock is *enforced* is ContentView and EditorCanvasView, which want a
// running window rather than a harness.
print("\ndocument:")

var saved = PatchWorkDocument(elements: [
    CanvasElement(type: .knob, rect: CGRect(x: 8, y: 16, width: 72, height: 88)),
    CanvasElement(type: .adsr, rect: CGRect(x: 96, y: 16, width: 208, height: 120)),
], locked: true)
saved.elements[0].name = "Cutoff"
saved.elements[0].parameters[0].cc = 74
saved.elements[0].values = [ValueEntry(name: "Saw", number: 0)]
saved.elements[1].checksum = .yamaha
saved.elements[1].valueFormat = .msbLsb

let written = try JSONEncoder().encode(saved)
let read = try JSONDecoder().decode(PatchWorkDocument.self, from: written)

guard read.locked else { fatalError("the lock did not survive the round trip") }
guard read.elements.count == 2 else { fatalError("elements lost: \(read.elements.count)") }
guard read.elements[0].id == saved.elements[0].id,
      read.elements[0].name == "Cutoff",
      read.elements[0].parameters[0].cc == 74,
      read.elements[0].parameters[0].id == saved.elements[0].parameters[0].id,
      read.elements[0].values.first?.name == "Saw",
      read.elements[1].checksum == .yamaha,
      read.elements[1].valueFormat == .msbLsb,
      read.elements[1].rect == saved.elements[1].rect else {
    fatalError("the layout did not survive the round trip")
}
print("  a locked layout survives the round trip ✓  lock, ids, addresses, values and geometry")

// An unlocked one says so rather than leaving it to a missing key.
let unlocked = try JSONDecoder().decode(
    PatchWorkDocument.self, from: try JSONEncoder().encode(PatchWorkDocument())
)
guard !unlocked.locked, unlocked.elements.isEmpty else { fatalError("an empty document is wrong") }
print("  an empty layout is empty and unlocked ✓")

// The transfer settings travel with the layout, which is the whole point of
// their being in the file rather than in UserDefaults: a panel built for a
// device that needs 32-byte chunks opens that way on another machine.
var pacedLayout = PatchWorkDocument(elements: [])
pacedLayout.transfer = SysExTransfer(strategy: .handshake, chunkBytes: 32, breakMS: 20,
                                     timeoutMS: 250, retries: 5)
let readPace = try JSONDecoder().decode(
    PatchWorkDocument.self, from: try JSONEncoder().encode(pacedLayout)
)
guard readPace.transfer == pacedLayout.transfer else {
    fatalError("the transfer settings did not survive the round trip: \(String(describing: readPace.transfer))")
}
// And a file that has never been asked says so, rather than answering with
// a default it does not hold - see PatchWorkDocument.
guard unlocked.transfer == nil else { fatalError("an untouched layout invented transfer settings") }
print("  the transfer settings survive the round trip ✓  handshake, 32 bytes, 20 ms, 250 ms × 5")

// The shape really is an object now, and really does carry the flag - a bare
// array would decode into nothing here.
let asObject = try JSONSerialization.jsonObject(with: written) as? [String: Any]
guard let asObject, asObject["locked"] as? Bool == true, asObject["elements"] is [Any] else {
    fatalError("the file is not an object with locked and elements")
}
print("  the file is an object, not an array ✓  {\"elements\": [...], \"locked\": true}")

// Which is exactly why files written before this do not open. Asserted rather
// than merely stated: it is the one visible cost of the change.
let oldFormat = try JSONEncoder().encode([CanvasElement(type: .knob, rect: .zero)])
do {
    _ = try JSONDecoder().decode(PatchWorkDocument.self, from: oldFormat)
    fatalError("a bare array should no longer decode")
} catch {
    print("  a file from before the change is refused ✓  no migration, by instruction")
}

// ── One device in both roles ─────────────────────────────────────────────
// The user's own rig: a synth chosen as the Input *and* as a Controller.
// Connecting it to both ports would make CoreMIDI deliver every message
// twice, and the app would log it twice, count it twice and flash twice.
print("\nboth roles at once:")

var seenByRole: [(count: Int, roles: MIDIRoles)] = []
engine.onDecoded = { messages, roles in seenByRole.append((messages.count, roles)) }

func rolesOf(_ roles: MIDIRoles) -> String {
    var names: [String] = []
    if roles.contains(.input) { names.append("input") }
    if roles.contains(.controller) { names.append("controller") }
    return names.joined(separator: "+")
}

// Controller first, then the same device as the Input - and afterwards the
// other way round, because the result must not depend on which menu was
// touched first.
for (order, wire) in [("controller then input", true), ("input then controller", false)] {
    engine.selectSource(nil)
    engine.disconnectAllControllers()
    if wire {
        engine.setController(listenTo.id, connected: true)
        engine.selectSource(listenTo)
    } else {
        engine.selectSource(listenTo)
        engine.setController(listenTo.id, connected: true)
    }
    guard engine.controllerSharesInput else {
        fatalError("\(order): the roles should be sharing one connection")
    }

    engine.select(target)
    _ = arrived()
    seenByRole.removeAll()
    let linesBefore = engine.activity.lines.count
    let countBefore = engine.activity.receivedCount

    play([0xB0, 74, 100])
    guard wait(upTo: 1, until: { !seenByRole.isEmpty }) else { fatalError("\(order): nothing arrived") }
    _ = wait(upTo: 0.3, until: { false })

    guard seenByRole.count == 1, seenByRole[0].count == 1 else {
        fatalError("\(order): seenByRole \(seenByRole.count) times, wanted once")
    }
    guard seenByRole[0].roles == [.input, .controller] else {
        fatalError("\(order): roles were \(rolesOf(seenByRole[0].roles))")
    }
    guard engine.activity.lines.count == linesBefore + 1 else {
        fatalError("\(order): \(engine.activity.lines.count - linesBefore) log lines for one message")
    }
    guard engine.activity.receivedCount == countBefore + 1 else {
        fatalError("\(order): counted \(engine.activity.receivedCount - countBefore) times")
    }
    // And it still reaches the Output - the Controller's half of the job
    // happens on the shared connection.
    expectOnTheWire("  \(order) → still forwarded", [0xB0, 74, 100])
    print("  \(column(order, 24)) ✓  one line, one count, roles \(rolesOf(seenByRole[0].roles))")
}

// Taking the Input away leaves it a plain Controller, still forwarding.
engine.selectSource(nil)
guard !engine.controllerSharesInput, engine.selectedControllerIDs == [listenTo.id] else {
    fatalError("dropping the Input should leave the Controller alone")
}
seenByRole.removeAll()
_ = arrived()
play([0xB0, 74, 7])
guard wait(upTo: 1, until: { !seenByRole.isEmpty }) else { fatalError("the controller went silent") }
guard seenByRole[0].roles == [.controller] else {
    fatalError("roles after dropping the Input: \(rolesOf(seenByRole[0].roles))")
}
expectOnTheWire("still a controller", [0xB0, 74, 7])
print("  \(column("input taken away", 24)) ✓  its own connection again, roles \(rolesOf(seenByRole[0].roles))")

// And the rule that must never bend: an Input on its own reaches nothing.
engine.disconnectAllControllers()
engine.selectSource(listenTo)
guard !engine.controllerSharesInput else { fatalError("no controller should be sharing now") }
seenByRole.removeAll()
_ = arrived()
play([0xB0, 74, 3])
guard wait(upTo: 1, until: { !seenByRole.isEmpty }) else { fatalError("the input went silent") }
guard seenByRole[0].roles == [.input] else { fatalError("roles: \(rolesOf(seenByRole[0].roles))") }
_ = wait(upTo: 0.3, until: { false })
expectOnTheWire("Input alone reaches the Output: never", [])
print("  \(column("input alone", 24)) ✓  heard, roles input, and nothing on the wire")

// ── The editor forwards too: notes and CC alike ──────────────────────────
// Building a panel means playing and operating the device you are building
// it for, so a Controller reaches the Output while the layout is still being
// arranged. The engine is never told which mode the panel is in - there is
// no such property to set here, which is the point.
print("\na controller in the editor:")

engine.disconnectAllControllers()
engine.selectSource(nil)
engine.setController(keyboard.id, connected: true)
engine.select(target)

_ = arrived()
play([0x90, 60, 100], on: keyboardEndpoint)
expectOnTheWire("a note gets through", [0x90, 60, 100])
play([0xB0, 74, 100], on: keyboardEndpoint)
expectOnTheWire("and so does a CC", [0xB0, 74, 100])

// The rule that must not bend, asked of both: an Input alone reaches the
// Output with neither.
engine.disconnectAllControllers()
engine.selectSource(listenTo)
_ = arrived()
play([0x90, 62, 100])
play([0xB0, 74, 9])
_ = wait(upTo: 0.4, until: { false })
expectOnTheWire("Input notes and CC reach the Output: never", [])

// And a note on the Input is *heard* - which is the other half of the
// complaint: the decoder used to drop notes, so a keyboard on the shared
// connection appeared nowhere at all.
let linesBeforeNote = engine.activity.lines.count
let countBeforeNote = engine.activity.receivedCount
play([0x90, 64, 99])
guard wait(upTo: 1, until: { engine.activity.receivedCount > countBeforeNote }) else {
    fatalError("a note on the Input was not heard")
}
guard engine.activity.lines.count == linesBeforeNote + 1,
      engine.activity.lines.last == "RX  CH1 Note On 64 = 99" else {
    fatalError("the Monitor line for a note is wrong: \(engine.activity.lines.last ?? "none")")
}
print("  \(column("a note reaches the Monitor", 30)) ✓  \(engine.activity.lines.last ?? "")")

engine.selectSource(nil)

engine.onDecoded = nil
engine.selectSource(nil)

// ── What the layout knows about itself ───────────────────────────────────
print("\nmode and window sizes:")

let sized = PatchWorkDocument(
    elements: [CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 72, height: 88))],
    locked: false,
    mode: .active,
    windows: PatchWorkDocument.windowsDictionary([
        .editor: CGSize(width: 1400, height: 900),
        .active: CGSize(width: 640, height: 400),
    ])
)
let sizedBack = try JSONDecoder().decode(
    PatchWorkDocument.self, from: try JSONEncoder().encode(sized)
)
guard sizedBack.opensActive,
      sizedBack.windowSize(for: .editor) == CGSize(width: 1400, height: 900),
      sizedBack.windowSize(for: .active) == CGSize(width: 640, height: 400) else {
    fatalError("the mode and window sizes did not survive: \(String(describing: sizedBack.windows))")
}
print("  a size per mode survives the round trip ✓  editor 1400x900, active 640x400, opens active")

// A file that says nothing about either is not a file with a problem - it is
// one that has not been given a size yet, and it opens in the editor.
let quiet = try JSONDecoder().decode(
    PatchWorkDocument.self,
    from: Data(#"{"elements":[],"locked":false}"#.utf8)
)
guard !quiet.opensActive, quiet.windowSize(for: .editor) == nil,
      quiet.windowSize(for: .active) == nil else {
    fatalError("a file with no mode or sizes should read as editor and no size")
}
print("  a file that says neither ✓  opens in the editor, at no particular size")

// Half a size is not a size, and neither is a negative one.
for broken in [#"{"editor":[800]}"#, #"{"editor":[0,600]}"#, #"{"editor":[-5,-5]}"#] {
    let doc = try JSONDecoder().decode(
        PatchWorkDocument.self,
        from: Data(#"{"elements":[],"locked":false,"windows":"#.utf8) + Data(broken.utf8) + Data("}".utf8)
    )
    guard doc.windowSize(for: .editor) == nil else {
        fatalError("\(broken) should not read as a size")
    }
}
print("  half a size, a zero and a negative one are refused ✓")

// ── The application's own memory ─────────────────────────────────────────
print("\nsettings:")

let suite = "PatchWorkVerification"
guard let scratch = UserDefaults(suiteName: suite) else { fatalError("no scratch defaults") }
scratch.removePersistentDomain(forName: suite)

// Nothing stored is a clean answer, not an empty one.
let fresh = AppSettings.load(from: scratch)
guard fresh.outputName == nil, fresh.inputName == nil,
      fresh.controllerNames.isEmpty, fresh.windowSize == nil else {
    fatalError("a fresh settings file should be empty, got \(fresh)")
}
print("  nothing stored reads as nothing chosen ✓")

var toStore = AppSettings()
toStore.outputName = "MiniFreak MIDI"
toStore.inputName = "MiniFreak MIDI"
toStore.controllerNames = ["minilogue", "MiniFreak MIDI"]
toStore.windowSize = CGSize(width: 1360, height: 820)
toStore.save(to: scratch)

let reloaded = AppSettings.load(from: scratch)
guard reloaded == toStore else { fatalError("settings did not survive: \(reloaded)") }
print("  ports and window size survive ✓  out/in \"MiniFreak MIDI\", 2 controllers, 1360x820")

// Choosing nothing has to be storable too - otherwise a port cleared today
// would come back tomorrow.
var cleared = AppSettings()
cleared.windowSize = CGSize(width: 900, height: 700)
cleared.save(to: scratch)
let afterClearing = AppSettings.load(from: scratch)
guard afterClearing.outputName == nil, afterClearing.inputName == nil,
      afterClearing.controllerNames.isEmpty,
      afterClearing.windowSize == CGSize(width: 900, height: 700) else {
    fatalError("clearing the ports did not stick: \(afterClearing)")
}
print("  clearing a port sticks ✓  it does not come back next session")
scratch.removePersistentDomain(forName: suite)

// ── Ports are remembered by name, and wanted until told otherwise ────────
print("\nremembered ports:")

engine.disconnectAllControllers()
engine.selectSource(nil)
engine.select(nil)

// A name that is not plugged in is kept, not dropped: a rig switched on after
// the app is still the rig.
engine.restorePorts(output: "Nothing Like This", input: "Nor This", controllers: ["Or This"])
guard engine.selectedDestinationID == nil, engine.selectedSourceID == nil,
      engine.selectedControllerIDs.isEmpty else {
    fatalError("names that are not present should connect nothing")
}
guard engine.wantedInputName == "Nor This", engine.wantedControllerNames == ["Or This"] else {
    fatalError("the wanted names should have been kept")
}
print("  names of absent devices are kept, not dropped ✓  nothing connected, everything still wanted")

// The names of what *is* here connect it, which is what a restart does.
engine.restorePorts(output: sinkName as String, input: sourceName as String,
                    controllers: ["PatchWork Verify Ctrl B"])
guard engine.selectedDestinationID == target.id else { fatalError("the output was not restored") }
guard engine.selectedSourceID == listenTo.id else { fatalError("the input was not restored") }
guard engine.selectedControllerIDs == [faderBox.id] else {
    fatalError("the controller was not restored: \(engine.selectedControllerIDs)")
}
print("  names of present devices connect them ✓  out, in and one controller, all by name")

// And what goes back to the settings is what was asked for, not what happened
// to be plugged in at the time.
let remembered = engine.portSettings
guard remembered.output == (sinkName as String), remembered.input == (sourceName as String),
      remembered.controllers == ["PatchWork Verify Ctrl B"] else {
    fatalError("the wrong names would be stored: \(remembered)")
}
print("  what is stored is what was chosen ✓  \(remembered.controllers.joined(separator: ", "))")

engine.disconnectAllControllers()
engine.selectSource(nil)
engine.select(nil)

MIDIEndpointDispose(keyboardEndpoint)
MIDIEndpointDispose(faderBoxEndpoint)
MIDIClientDispose(controllerClient)
MIDIEndpointDispose(virtualSource)
MIDIClientDispose(sourceClient)
MIDIEndpointDispose(virtualDestination)
MIDIClientDispose(sinkClient)
print("\nOK")
