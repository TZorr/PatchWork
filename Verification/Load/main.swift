//
//  Verification/Load/main.swift
//  PatchWork
//
//  A load harness for the MIDI input path, separate from the correctness one
//  next door because it answers a different kind of question: not "is this
//  right" but "what does this cost when several controllers all talk at once".
//
//  Everything here is measured rather than reasoned about. The numbers in the
//  plan that produced this file were estimates from reading the code; these
//  are the ones to argue with.
//
//  Run it from the repository root, the same as the other one:
//
//      swiftc -O -default-isolation MainActor -o /tmp/load_midi \
//          Verification/Load/main.swift \
//          PatchWork/MIDI/*.swift \
//          PatchWork/Canvas/ControlOperation.swift PatchWork/Canvas/ElementRandom.swift \
//          PatchWork/Canvas/ElementParameter.swift PatchWork/Canvas/CanvasElement.swift \
//          PatchWork/Canvas/ElementSchema.swift \
//          PatchWork/Document/PatchWorkDocument.swift PatchWork/Document/AppSettings.swift \
//          PatchWork/Document/AppAppearance.swift \
//          PatchWork/Widgets/EnvelopeDrawing.swift PatchWork/Widgets/PadDrawing.swift \
//          PatchWork/Widgets/ValueReadout.swift
//      /tmp/load_midi
//
//  **-O, and not the default.** The app's Debug build is -Onone, which
//  overstates every cost in here - the parser and the matcher are both a great
//  deal of small struct work, which is exactly what the optimiser eats. A
//  measurement taken in Debug would send us optimising the wrong thing.
//
import CoreMIDI
import Foundation

// ─── Plumbing ────────────────────────────────────────────────────────────

func pump(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.002))
    }
}

func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.002))
    }
    return condition()
}

/// Resident size, for the SysEx case where the cost is copying rather than
/// computing.
func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

func column(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

print("PatchWork MIDI load harness")
print(String(repeating: "=", count: 60))

// ─── 1. A 56-element panel, the size of the microKORG preset ─────────────

/// Knobs on channel 1, CC 0...55 - a real panel's worth of addresses.
func panel(count: Int) -> [CanvasElement] {
    (0..<count).map { index in
        var element = CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 60, height: 60))
        element.channel = 1
        element.output = .cc
        element.parameters[0].cc = index
        return element
    }
}

let elementCount = 56
print("\npanel: \(elementCount) knobs, channel 1, CC 0...\(elementCount - 1)")

// ─── 2. What an incoming batch costs the element list ────────────────────
//
// Two streams, and the difference between them is the whole point:
//
//   "addressed"   - CC 0, which a knob on this panel is pointed at. Half the
//                   messages carry a new value and half repeat the last one,
//                   which is what an echo of our own send looks like.
//   "unaddressed" - CC 100, which nothing on this panel uses at all. Every
//                   one of these should cost nothing beyond the lookup.
//
// `apply` already answers whether anything moved. What is being measured here
// is how often that answer is *false* - because that is how often the panel is
// being redrawn for nothing.

func benchApply(label: String, cc: Int, alternating: Bool, batches: Int) {
    var elements = panel(count: elementCount)
    var writes = 0
    var value = 0

    let started = ContinuousClock.now
    for batch in 0..<batches {
        if alternating {
            // Half the batches repeat the previous value - an echo.
            value = (batch / 2) % 128
        } else {
            value = batch % 128
        }
        let message = IncomingMessage(kind: .controlChange, channel: 1, number: cc, value: value)
        // Exactly what ContentView.incoming does: ask first, and only then
        // write. Each `write` here is one @State assignment, which is one
        // repaint of every element on the canvas.
        if elements.wouldChange(for: [message]) {
            writes += 1
            elements.apply([message])
        }
    }
    let elapsed = ContinuousClock.now - started
    let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000

    print("  \(column(label, 14)) \(column("\(batches) batches", 14)) " +
          "whole-panel repaints: \(column("\(writes)", 7)) " +
          "\(column(String(format: "(%.0f%% of batches)", 100.0 * Double(writes) / Double(batches)), 18)) " +
          "\(String(format: "%.1f", ms)) ms")
}

print("\nwrite-backs to the element list (the cause of the repaint):")
benchApply(label: "unaddressed", cc: 100, alternating: false, batches: 6000)
benchApply(label: "addressed",   cc: 0,   alternating: true,  batches: 6000)
print("    Before the change this column read 6000 both times - every incoming")
print("    message wrote to @State, whether or not it moved anything.")

// ─── 3. End to end, through CoreMIDI, several controllers at once ────────

print("\nthrough CoreMIDI, three controllers at once:")

let engine = MIDIEngine()

var sourceClient = MIDIClientRef()
guard MIDIClientCreateWithBlock("LoadSourceClient" as CFString, &sourceClient, nil) == noErr else {
    fatalError("could not create the source client")
}

let controllerCount = 3
var virtualSources: [MIDIEndpointRef] = []
for index in 0..<controllerCount {
    var source = MIDIEndpointRef()
    let name = "PatchWork Load \(index)" as CFString
    guard MIDISourceCreate(sourceClient, name, &source) == noErr else {
        fatalError("could not create virtual source \(index)")
    }
    virtualSources.append(source)
}

engine.refreshEndpoints()
for index in 0..<controllerCount {
    guard let info = engine.sources.first(where: { $0.name == "PatchWork Load \(index)" }) else {
        fatalError("engine did not enumerate source \(index); saw \(engine.sources.map(\.name))")
    }
    engine.setController(info.id, connected: true)
}
guard engine.selectedControllerIDs.count == controllerCount else {
    fatalError("connected \(engine.selectedControllerIDs.count) of \(controllerCount) controllers")
}
print("  \(controllerCount) virtual controllers connected ✓")

// Counted here rather than off `activity.receivedCount`: that counter belongs
// to the Input role, and a Controller's messages deliberately do not touch it
// (see MIDIActivity.recordController). This is also the callback ContentView
// itself hangs on, so it is the same path the panel sees.
var decodedCount = 0
var decodedSysEx = 0
engine.onDecoded = { messages, _ in
    decodedCount += messages.count
    decodedSysEx += messages.filter { $0.kind == .systemExclusive }.count
}

func blast(_ bytes: [UInt8], on source: MIDIEndpointRef) {
    var packet = MIDIPacket()
    packet.timeStamp = 0
    packet.length = UInt16(bytes.count)
    withUnsafeMutableBytes(of: &packet.data) { $0.copyBytes(from: bytes) }
    var list = MIDIPacketList(numPackets: 1, packet: packet)
    _ = MIDIReceived(source, &list)
}

let perController = 2000
let totalSent = perController * controllerCount
let before = decodedCount
let startedStream = ContinuousClock.now

for index in 0..<perController {
    for source in virtualSources {
        blast([0xB0, 74, UInt8(index % 128)], on: source)
    }
    // Let the run loop breathe every so often, or the sends outrun the reads
    // and this measures the queue rather than the path.
    if index % 100 == 0 { pump(0.001) }
}
_ = waitUntil(20) { decodedCount - before >= totalSent }
let streamElapsed = ContinuousClock.now - startedStream
let streamSeconds = Double(streamElapsed.components.seconds)
    + Double(streamElapsed.components.attoseconds) / 1e18
let delivered = decodedCount - before

print("  sent \(totalSent), decoded \(delivered) in \(String(format: "%.2f", streamSeconds))s " +
      "→ \(String(format: "%.0f", Double(delivered) / streamSeconds)) msg/s")
if delivered < totalSent {
    print("  ⚠︎ \(totalSent - delivered) message(s) never arrived")
}

// ─── 4. A bulk SysEx in, which is where the copying shows ────────────────
//
// The receiving parser accumulates a SysEx across packet lists. If the buffer
// is copied on each append - which it is when the Connection is lifted out of
// its dictionary to be mutated - the total copying is quadratic in the dump.
// Doubling the dump should then roughly quadruple the time.
//
// So this measures two sizes and prints the ratio. Linear accumulation gives
// about 2; copy-per-append gives about 4.

print("\nreceiving a bulk SysEx (the copying case):")

func feedSysEx(bytes total: Int, chunk: Int, on source: MIDIEndpointRef) -> (seconds: Double, grew: Int64) {
    var payload: [UInt8] = [0xF0, 0x42]
    payload += (0..<(total - 3)).map { UInt8($0 % 0x78) }
    payload.append(0xF7)

    let residentBefore = residentBytes()
    let wanted = decodedSysEx + 1
    let started = ContinuousClock.now
    var offset = 0
    while offset < payload.count {
        let end = min(offset + chunk, payload.count)
        blast(Array(payload[offset..<end]), on: source)
        offset = end
        if offset % (chunk * 8) == 0 { pump(0.001) }
    }
    guard waitUntil(20, { decodedSysEx >= wanted }) else {
        fatalError("the \(total)-byte SysEx never came back out of the parser")
    }
    let elapsed = ContinuousClock.now - started
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    return (seconds, Int64(residentBytes()) - Int64(residentBefore))
}

// Three sizes, each 4x the last. Linear accumulation gives ~4x the time per
// step; a buffer copied on every append gives ~16x, and the gap widens.
var previous: Double?
for bytes in [8_192, 32_768, 131_072] {
    let run = feedSysEx(bytes: bytes, chunk: 128, on: virtualSources[0])
    let step = previous.map { String(format: "%5.1f×", run.seconds / max($0, 1e-9)) } ?? "    -"
    print("  \(column("\(bytes / 1024) KB", 7)) in 128-byte chunks: " +
          "\(String(format: "%7.3f", run.seconds))s   step \(step)")
    previous = run.seconds
}
print("    ≈4× per step is linear; ≈16× would be a copy per append.")

print("\n" + String(repeating: "=", count: 60))
print("done")
