//
//  MIDIEvent.swift
//  PatchWork
//
//  One line of the MIDI Monitor, with the parts a filter needs kept apart
//  instead of flattened into the text.
//
//  The canvas Monitor element keeps its plain `[String]` and is untouched by
//  any of this - six lines of the newest traffic need nothing more. A tool
//  window does: "show me only the CCs, only inbound, and not the Clock" is
//  three questions about a message, and none of them can be asked of a
//  string that already reads "CH1 CC 74 = 100".
//
//  **Every message is recorded twice**, once as it arrived and once as the
//  app understood it - see `Form`. That is the whole point of the window: an
//  NRPN is three or four Control Changes on the wire and one parameter in the
//  layout, and when those two disagree there is nowhere else to look.
//
//  It also puts the SysEx bytes back. The decoder keeps a payload's length
//  and throws its contents away (see MIDIInput), so the decoded form can only
//  ever say "SysEx 42 bytes". The raw form has the bytes and now carries
//  them, which for an editor aimed at gear that speaks SysEx is not a detail.
//

import Foundation

nonisolated struct MIDIEvent: Identifiable, Sendable {
    /// Which way it went.
    ///
    /// The same three the existing log prefixes with - RX, TX and CTRL - so
    /// the window and the canvas element say the same words about the same
    /// message.
    enum Direction: String, CaseIterable, Sendable {
        case rx = "RX"
        case tx = "TX"
        case ctrl = "CTRL"

        var title: String {
            switch self {
            case .rx: "Input"
            case .tx: "Sent"
            case .ctrl: "Controller"
            }
        }
    }

    /// As it arrived, or as the app read it.
    enum Form: String, CaseIterable, Sendable {
        case raw = "RAW"
        case decoded = "DEC"

        var title: String {
            switch self {
            case .raw: "Raw"
            case .decoded: "Decoded"
            }
        }
    }

    /// What the message is - the filter that matters most in practice.
    ///
    /// `realtime` earns its own case for one reason: Clock arrives twenty-four
    /// times a beat, and a monitor that cannot silence it is a monitor nobody
    /// can read. `other` is the honest bucket for the rest of the system
    /// messages rather than a case per byte nothing here acts on.
    enum Kind: String, CaseIterable, Sendable {
        case note, controlChange, nrpn, programChange, pitchBend
        case aftertouch, sysEx, realtime, other

        var title: String {
            switch self {
            case .note: "Note"
            case .controlChange: "CC"
            case .nrpn: "NRPN"
            case .programChange: "Program"
            case .pitchBend: "Pitch Bend"
            case .aftertouch: "Aftertouch"
            case .sysEx: "SysEx"
            case .realtime: "Realtime"
            case .other: "Other"
            }
        }
    }

    /// A running number rather than a UUID: this is minted per message on the
    /// MIDI path, and a fader sweep is sixty of them a second. It only has to
    /// be unique within one run of the app, which counting gives for free.
    let id: UInt64
    let time: Date
    let direction: Direction
    let form: Form
    let kind: Kind
    /// 1...16, or nil for a system message, which has no channel.
    let channel: Int?
    /// Which port it came from or went to. Beyond the filters, but a log with
    /// two instruments on it and no column saying which is one nobody can
    /// read.
    let device: String?
    /// The line itself, from the same `description` the canvas Monitor uses -
    /// written once, so the two cannot describe one message differently.
    let text: String
    /// The bytes, where they are known. Empty for a decoded event, which is a
    /// reading rather than something that was ever on the wire.
    let bytes: [UInt8]

    /// `HH:mm:ss.SSS` - to the millisecond, because the question a timestamp
    /// answers here is "did these two arrive together", and seconds cannot.
    var timeText: String { Self.formatter.string(from: time) }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// One line of a copied log: everything the window shows, tab-separated so
    /// it keeps its columns when pasted somewhere with a monospaced font.
    var logLine: String {
        let channelText = channel.map { "CH\($0)" } ?? "--"
        let deviceText = device ?? ""
        var line = "\(timeText)\t\(direction.rawValue)\t\(form.rawValue)\t\(channelText)\t\(text)"
        if !deviceText.isEmpty { line += "\t[\(deviceText)]" }
        return line
    }
}

extension MIDIEvent {
    /// What a System Real Time byte is called.
    ///
    /// Needed because these never become a `RawMIDIMessage`: the stream parser
    /// drops everything from 0xF8 up, deliberately and with good reason - they
    /// arrive constantly and would drown the panel's six-line Monitor tile.
    /// The tool window picks them off ahead of the parser instead, and it has
    /// a filter to switch them back off with, so here they need names.
    static func realtimeName(_ status: UInt8) -> String {
        switch status {
        case 0xF8: "Clock"
        case 0xFA: "Start"
        case 0xFB: "Continue"
        case 0xFC: "Stop"
        case 0xFE: "Active Sensing"
        case 0xFF: "System Reset"
        default: "System \(String(format: "%02X", status))"
        }
    }
}

extension MIDIEvent.Kind {
    /// What a raw status byte is.
    ///
    /// Reads the same nibbles `RawMIDIMessage` does rather than asking it, so
    /// that a message which never became a `RawMIDIMessage` - a sent one, say -
    /// can be classified by exactly the same rule.
    static func of(status: UInt8) -> Self {
        switch status & 0xF0 {
        case 0x80, 0x90: .note
        case 0xA0, 0xD0: .aftertouch
        case 0xB0: .controlChange
        case 0xC0: .programChange
        case 0xE0: .pitchBend
        default:
            // 0xF0 upward is the system range: a SysEx, or one of the realtime
            // bytes a device sprays continuously.
            status == 0xF0 ? .sysEx : (status >= 0xF8 ? .realtime : .other)
        }
    }

    /// What the decoder made of it. A reassembled NRPN is the one kind that
    /// exists here and nowhere on the wire, which is the reason both forms
    /// are worth showing.
    static func of(incoming: IncomingMessage.Kind) -> Self {
        switch incoming {
        case .noteOn, .noteOff: .note
        case .controlChange: .controlChange
        case .nrpn: .nrpn
        case .programChange: .programChange
        case .systemExclusive: .sysEx
        }
    }
}
