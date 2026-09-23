//
//  MIDIInput.swift
//  PatchWork
//
//  Turning arriving bytes back into messages, and then into the terms
//  elements are addressed in. Two stages, both pure Foundation so they can
//  be compiled and tested on their own:
//
//    MIDIStreamParser  bytes -> messages
//    MIDIDecoder       messages -> what they meant (NRPN reassembled)
//
//  Every type here is `nonisolated`: they are values and pure state machines,
//  and the app target's own default would otherwise put them on the main actor
//  - which is not where a parser fed from a CoreMIDI thread belongs, and which
//  makes even `==` on one of them a concurrency error outside that actor.
//
//  Both stages are written here, which is the point of using CoreMIDI
//  directly. The first has two details a higher-level MIDI library would
//  normally hide: running status, and the fact that a packet is a byte
//  stream rather than one message.
//

import Foundation

/// One message as it arrived, before anyone has decided what it means.
nonisolated struct RawMIDIMessage: Equatable {
    /// The status byte, with its channel nibble still in it.
    let status: UInt8
    let data: [UInt8]

    /// 1...16, or nil for a system message which has no channel.
    var channel: Int? {
        status < 0xF0 ? Int(status & 0x0F) + 1 : nil
    }

    var isNote: Bool { status & 0xF0 == 0x80 || status & 0xF0 == 0x90 }
    var isControlChange: Bool { status & 0xF0 == 0xB0 }
    var isProgramChange: Bool { status & 0xF0 == 0xC0 }
    var isSystemExclusive: Bool { status == 0xF0 }

    /// The message as bytes again, ready to be forwarded.
    ///
    /// **Not literally the bytes as they arrived**: a device using running
    /// status sends the status byte once and then bare data pairs, and this
    /// puts an explicit status byte in front of every message. Same messages,
    /// same order, same values - just spelled out, which no receiver can
    /// object to. What matters for forwarding is that nothing is dropped,
    /// reordered or recombined; see MIDIThru.
    var bytes: [UInt8] { [status] + data }

    /// How a monitor prints it - raw, as what arrived rather than as what it
    /// meant. A Controller's messages are shown this way because nothing
    /// reassembles them: an NRPN's CC 99 / CC 98 / CC 6 read as three lines,
    /// in the order they came, which is exactly what got forwarded.
    var description: String {
        let channelLabel = channel.map { "CH\($0) " } ?? ""
        switch status & 0xF0 {
        case 0x80:
            return "\(channelLabel)Note Off \(data.first ?? 0)"
        case 0x90:
            // Velocity 0 is Note Off in disguise, and gear sends it that way
            // constantly - printing it as "Note On … = 0" would read as a
            // stuck note.
            let velocity = data.count > 1 ? data[1] : 0
            return velocity == 0
                ? "\(channelLabel)Note Off \(data.first ?? 0)"
                : "\(channelLabel)Note On \(data.first ?? 0) = \(velocity)"
        case 0xA0:
            return "\(channelLabel)Aftertouch \(data.first ?? 0) = \(data.count > 1 ? data[1] : 0)"
        case 0xB0:
            return "\(channelLabel)CC \(data.first ?? 0) = \(data.count > 1 ? data[1] : 0)"
        case 0xC0:
            return "\(channelLabel)Program \(data.first ?? 0)"
        case 0xD0:
            return "\(channelLabel)Pressure \(data.first ?? 0)"
        case 0xE0:
            let bend = (Int(data.count > 1 ? data[1] : 0) << 7) | Int(data.first ?? 0)
            return "\(channelLabel)Pitch Bend \(bend)"
        default:
            return isSystemExclusive
                ? "SysEx \(data.count) bytes"
                : "Status \(String(format: "%02X", status))"
        }
    }
}

/// Bytes in, messages out.
///
/// Stateful on purpose, and one instance per port: a message can be split
/// across packets, and running status means a data-only packet is
/// meaningful *because* of what came before it. Two ports sharing a parser
/// would hand each other their halves.
nonisolated struct MIDIStreamParser {
    /// The most a single incoming SysEx may grow to before it is abandoned.
    ///
    /// There has to be a number. A device that sends `0xF0` and then stops -
    /// unplugged mid-dump, a bad cable, a byte lost to noise - leaves this
    /// buffer open, and every byte that follows until some other status arrives
    /// is added to it. Without a ceiling that is unbounded growth driven by
    /// whatever is on the wire.
    ///
    /// 1 MB is far above anything real: the largest dump this app is built for
    /// is a 37 KB microKORG store, so the limit is roughly thirty of those. It
    /// is a guard against nonsense, not a policy about message size.
    static let maxSysExBytes = 1 << 20

    private var runningStatus: UInt8?
    private var expectedDataCount = 0
    private var data: [UInt8] = []
    private var sysex: [UInt8]?

    /// How many data bytes a channel-voice status takes. Program Change and
    /// Channel Pressure take one; everything else takes two.
    private static func dataCount(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: 1
        default: 2
        }
    }

    /// How many a System Common message takes, so its data bytes are
    /// consumed rather than mistaken for the next message's.
    private static func systemCommonDataCount(for status: UInt8) -> Int {
        switch status {
        case 0xF1, 0xF3: 1  // MTC quarter frame, Song Select
        case 0xF2: 2        // Song Position Pointer
        default: 0          // Tune Request, and the rest
        }
    }

    mutating func feed(_ bytes: some Sequence<UInt8>) -> [RawMIDIMessage] {
        var messages: [RawMIDIMessage] = []
        for byte in bytes {
            // System Real Time (0xF8...0xFF) may appear *inside* another
            // message and does not disturb it - which is exactly why Clock
            // and Active Sensing are dropped here rather than upstream:
            // they arrive constantly, and letting them through would drown
            // a monitor in noise.
            if byte >= 0xF8 { continue }

            if byte == 0xF7 {
                // End of a SysEx. A stray one with no start is ignored.
                if var payload = sysex {
                    // Reassembled in place. This used to append to a copy and
                    // then build a second array from `dropFirst()` - two full
                    // passes over a payload that can be tens of kilobytes.
                    sysex = nil
                    payload.append(byte)
                    payload.removeFirst()               // the 0xF0 is framing here
                    messages.append(RawMIDIMessage(status: 0xF0, data: payload))
                }
                continue
            }

            if byte >= 0x80 {
                // Any other status byte ends an unterminated SysEx: the
                // payload is incomplete, so it is dropped rather than
                // reported as though it were whole.
                sysex = nil

                if byte == 0xF0 {
                    sysex = [byte]
                    runningStatus = nil
                } else if byte >= 0xF0 {
                    // System Common: no running status survives it.
                    runningStatus = nil
                    expectedDataCount = Self.systemCommonDataCount(for: byte)
                    data = []
                } else {
                    runningStatus = byte
                    expectedDataCount = Self.dataCount(for: byte)
                    data = []
                }
                continue
            }

            // A data byte.
            if sysex != nil {
                if sysex!.count >= Self.maxSysExBytes {
                    // Abandoned rather than truncated: half a dump reported as
                    // whole is worse than none, and something is wrong with the
                    // stream anyway. The next status byte starts afresh.
                    sysex = nil
                    continue
                }
                sysex!.append(byte)
                continue
            }
            guard let status = runningStatus else {
                // Orphaned - no status has been seen, so there is nothing
                // to attach it to.
                continue
            }
            data.append(byte)
            if data.count == expectedDataCount {
                messages.append(RawMIDIMessage(status: status, data: data))
                // Running status persists: the next data pair belongs to
                // the same status byte, which is the whole point of it.
                data = []
            }
        }
        return messages
    }
}

/// One decoded message, in the terms elements are addressed in. The
/// counterpart of MIDIMessage: that says what an element would send, this
/// says what arrived.
nonisolated struct IncomingMessage: Equatable {
    nonisolated enum Kind: Equatable, Hashable {
        case noteOn, noteOff, controlChange, nrpn, programChange, systemExclusive
    }

    let kind: Kind
    let channel: Int
    /// A CC number, or an NRPN parameter as its two halves joined. A
    /// Program Change has no address beyond its channel, so this stays 0
    /// and the program itself is the value - the program is what a control
    /// carrying it is *set to*, exactly as it is sent.
    let number: Int
    let value: Int

    /// How a monitor prints it. A plain CC names itself by number;
    /// everything else says what it is, because "CC 99" tells you nothing
    /// about an NRPN address while "NRPN" tells you everything.
    var description: String {
        switch kind {
        case .noteOn: "CH\(channel) Note On \(number) = \(value)"
        case .noteOff: "CH\(channel) Note Off \(number)"
        case .controlChange: "CH\(channel) CC \(number) = \(value)"
        case .nrpn: "CH\(channel) NRPN \(number) = \(value)"
        case .programChange: "CH\(channel) Program \(value)"
        case .systemExclusive: "SysEx \(value) bytes"
        }
    }
}

/// Reassembles what a stream of Control Changes actually meant.
///
/// A CC and a Program Change say everything in one message. An NRPN does
/// not: CC 99 and CC 98 carry an address and no value, and the CC 6 / CC 38
/// that follow carry a value and no address. So the address is remembered
/// per channel until the data entry arrives - which is why this holds
/// state.
///
/// One decoder per port, for the same reason as the parser: two ports
/// interleaving their trios through a shared address would hand each other
/// the wrong halves.
nonisolated struct MIDIDecoder {
    private struct Pending {
        var msb: Int?
        var lsb: Int?
        var coarse: Int?
        var fine: Int?
    }

    private var pending: [Int: Pending] = [:]

    mutating func decode(_ message: RawMIDIMessage) -> IncomingMessage? {
        if message.isSystemExclusive {
            return IncomingMessage(kind: .systemExclusive, channel: 0, number: 0, value: message.data.count)
        }
        guard let channel = message.channel else { return nil }

        if message.isProgramChange, let program = message.data.first {
            return IncomingMessage(kind: .programChange, channel: channel, number: 0, value: Int(program))
        }

        // Notes carry no address a control could be pointed at, so nothing
        // downstream matches one - they come through so a Monitor can show
        // them and the lamp can light, the same way a Control Change does.
        if message.isNote, message.data.count == 2 {
            let velocity = Int(message.data[1])
            // A note on at velocity zero *is* a note off, and gear sends it
            // that way constantly. Printing it as "Note On ... = 0" would read
            // as a stuck note.
            let off = message.status & 0xF0 == 0x80 || velocity == 0
            return IncomingMessage(
                kind: off ? .noteOff : .noteOn,
                channel: channel, number: Int(message.data[0]), value: velocity
            )
        }

        guard message.isControlChange, message.data.count == 2 else { return nil }
        let control = Int(message.data[0])
        let value = Int(message.data[1])
        var state = pending[channel] ?? Pending()

        switch control {
        case MIDIControlNumber.nrpnMSB:
            state.msb = value
            pending[channel] = state
            return nil                      // an address, not a value
        case MIDIControlNumber.nrpnLSB:
            state.lsb = value
            pending[channel] = state
            return nil
        case MIDIControlNumber.dataEntryMSB, MIDIControlNumber.dataEntryLSB:
            // Data entry against an address we have seen. Both halves are
            // kept so either order works - gear that sends CC 38 first is
            // the whole reason the "LSB/MSB" output exists.
            //
            // With no address seen, it falls through to being reported as
            // the plain CC 6 or CC 38 that it literally is: guessing at an
            // NRPN we never saw addressed would invent a parameter number.
            guard state.msb != nil else { break }
            if control == MIDIControlNumber.dataEntryMSB {
                state.coarse = value
            } else {
                state.fine = value
            }
            pending[channel] = state
            let number = ((state.msb ?? 0) << 7) | (state.lsb ?? 0)
            let combined = ((state.coarse ?? 0) << 7) | (state.fine ?? 0)
            return IncomingMessage(kind: .nrpn, channel: channel, number: number, value: combined)
        default:
            break
        }
        return IncomingMessage(kind: .controlChange, channel: channel, number: control, value: value)
    }
}
