//
//  MIDIMessage.swift
//  PatchWork
//
//  What a control sending a value turns into on the wire. The single place
//  the protocol rules live - including the reasons, because several of these
//  bytes are the way they are because of specific hardware rather than
//  because of the spec.
//
//  Deliberately free of CoreMIDI and of CanvasElement: it takes the four
//  things a message depends on and returns bytes, so it can be tested by
//  compiling this file on its own. MIDIEngine does the talking.
//

import Foundation

/// The MIDI numbers that mean something in particular here, rather than
/// being whatever a control was configured with.
nonisolated enum MIDIControlNumber {
    static let bankMSB = 0
    static let bankLSB = 32
    static let nrpnMSB = 99
    static let nrpnLSB = 98
    static let dataEntryMSB = 6
    static let dataEntryLSB = 38
    static let allSoundOff = 120
    static let allNotesOff = 123
}

/// One message, already reduced to the bytes that go out. `label` is what
/// a monitor would call it, because "CC 6" tells you far less than "Data
/// Entry (coarse)" when you are reading back a burst of NRPN.
nonisolated struct MIDIMessage: Equatable {
    enum Kind: Equatable {
        case controlChange
        case programChange
        case systemExclusive
    }

    let kind: Kind
    /// 1...16 as everyone writes it; the byte on the wire is this minus 1.
    let channel: Int
    let data1: Int
    let data2: Int
    let label: String
    /// Set only for SysEx, where the payload is the whole message.
    let payload: [UInt8]

    private init(kind: Kind, channel: Int, data1: Int, data2: Int, label: String, payload: [UInt8]) {
        self.kind = kind
        self.channel = channel
        self.data1 = data1
        self.data2 = data2
        self.label = label
        self.payload = payload
    }

    static func controlChange(channel: Int, number: Int, value: Int, label: String = "") -> MIDIMessage {
        MIDIMessage(
            kind: .controlChange,
            channel: clampChannel(channel), data1: clamp7(number), data2: clamp7(value),
            label: label, payload: []
        )
    }

    static func programChange(channel: Int, number: Int, label: String = "") -> MIDIMessage {
        MIDIMessage(
            kind: .programChange,
            channel: clampChannel(channel), data1: clamp7(number), data2: 0,
            label: label, payload: []
        )
    }

    static func systemExclusive(_ payload: [UInt8], label: String = "") -> MIDIMessage {
        MIDIMessage(kind: .systemExclusive, channel: 1, data1: 0, data2: 0, label: label, payload: payload)
    }

    /// The bytes as they go on the wire. Status nibbles are the standard
    /// ones; the channel is zero-based here and one-based everywhere a
    /// human sees it.
    var bytes: [UInt8] {
        switch kind {
        case .controlChange:
            [UInt8(0xB0 | (channel - 1)), UInt8(data1), UInt8(data2)]
        case .programChange:
            [UInt8(0xC0 | (channel - 1)), UInt8(data1)]
        case .systemExclusive:
            payload
        }
    }

    /// How a monitor would print it - the label when there is one, since
    /// that is the part worth reading.
    var description: String {
        switch kind {
        case .controlChange:
            "CH\(channel) CC \(data1) = \(data2)\(label.isEmpty ? "" : "  (\(label))")"
        case .programChange:
            "CH\(channel) Program \(data1)"
        case .systemExclusive:
            "SysEx \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))"
        }
    }
}

nonisolated func clamp7(_ value: Int) -> Int { min(max(value, 0), 127) }
nonisolated func clampChannel(_ value: Int) -> Int { min(max(value, 1), 16) }

/// The messages a control sending a value turns into, in order.
nonisolated enum MIDIPlanner {
    static let fourteenBitMax = 16383

    /// One parameter's messages. Takes the element's protocol settings and
    /// the parameter's own address separately, because that is how they are
    /// stored: one envelope speaks one protocol on one channel, while each
    /// of its stages is addressed for itself.
    ///
    /// Exhaustive over the protocol rather than falling through to plain CC
    /// for anything unrecognised, which is what it did while `output` was a
    /// `String`: a protocol nobody had written a branch for then sent a CC
    /// on the parameter's `cc` field - silently, on the wire, to the device.
    /// There is no unrecognised protocol now.
    static func messages(
        output: OutputProtocol,
        channel: Int,
        ceiling: Int,
        parameter: ElementParameter,
        value: Int,
        checksum: ChecksumMode = .roland,
        valueFormat: ValueFormat = .oneByte
    ) -> [MIDIMessage] {
        switch output {
        case .program:
            // Bank Select goes out whether or not it changed: a bank is
            // part of the address, and a Program Change that assumed the
            // device was still on the right bank would land somewhere else
            // the first time it wasn't.
            return [
                .controlChange(channel: channel, number: MIDIControlNumber.bankMSB,
                               value: parameter.bankMSB, label: "Bank MSB"),
                .controlChange(channel: channel, number: MIDIControlNumber.bankLSB,
                               value: parameter.bankLSB, label: "Bank LSB"),
                .programChange(channel: channel, number: value),
            ]

        case .nrpnMSBLSB, .nrpnLSBMSB:
            let address = [
                MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.nrpnMSB,
                                          value: parameter.paramMSB, label: "NRPN MSB"),
                MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.nrpnLSB,
                                          value: parameter.paramLSB, label: "NRPN LSB"),
            ]
            return address + dataEntry(output: output, channel: channel, ceiling: ceiling, value: value)

        case .sysEx:
            // Nothing for a template that is empty or unsound: that is
            // unconfigured rather than an error, and half a message - or a bare
            // F0 F7 - is worse than none. See SysExTemplate.
            let bytes = SysEx.message(
                template: parameter.sysex, value: value,
                checksumMode: checksum, format: valueFormat
            )
            return bytes.isEmpty ? [] : [.systemExclusive(bytes)]

        case .cc:
            // Plain CC. No label: this is the element's own configured
            // number, and it is not renamed just because it happens to
            // collide with 0, 6, 32, 38, 98 or 99.
            return [.controlChange(channel: channel, number: parameter.cc, value: value)]
        }
    }

    /// NRPN's payload: a real 14-bit split - CC 6 the high 7 bits, CC 38
    /// the low 7 - and the two variants differ only in which goes out
    /// first, LSB first being for gear that commits on CC 6.
    ///
    /// At 7 bits there is no low half to send, and **CC 38 is left off
    /// entirely rather than sent as a zero**. That is not tidying up: a
    /// microKORG takes a trailing CC 38 0 as a second edit and lands on a
    /// different value, which is why three messages work on it and four do
    /// not.
    private static func dataEntry(output: OutputProtocol, channel: Int, ceiling: Int, value: Int) -> [MIDIMessage] {
        guard ceiling > 127 else {
            return [.controlChange(channel: channel, number: MIDIControlNumber.dataEntryMSB,
                                   value: value, label: "Data Entry (coarse)")]
        }
        let bounded = min(max(value, 0), fourteenBitMax)
        let coarse = bounded / 128
        let fine = bounded % 128
        let msb = MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.dataEntryMSB,
                                            value: coarse, label: "Data Entry (coarse)")
        let lsb = MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.dataEntryLSB,
                                            value: fine, label: "Data Entry (fine)")
        return output == .nrpnLSBMSB ? [lsb, msb] : [msb, lsb]
    }

    /// All Notes Off and All Sound Off, on every channel.
    ///
    /// Both rather than either alone: All Notes Off (123) is the polite
    /// request that still lets
    /// a release stage run and is what most gear honours; All Sound Off
    /// (120) mutes immediately, for whatever a stuck note came from that
    /// 123 does not reach. A Panic button by definition cannot afford to be
    /// picky about which.
    static func panic() -> [MIDIMessage] {
        (1...16).flatMap { channel in
            [
                MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.allNotesOff,
                                          value: 0, label: "All Notes Off"),
                MIDIMessage.controlChange(channel: channel, number: MIDIControlNumber.allSoundOff,
                                          value: 0, label: "All Sound Off"),
            ]
        }
    }
}
