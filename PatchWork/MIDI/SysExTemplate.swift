//
//  SysExTemplate.swift
//  PatchWork
//
//  A typed SysEx line -> the bytes it means. What fills the parameter
//  table's "Parsed" column, and what a SysEx element puts on the wire.
//
//  A parameter holds one typed line rather than a token list assembled in a
//  dialog, so value encodings, checksum arithmetic and the bracketed
//  checksum range are all stated over a string. Pure Foundation and
//  `nonisolated`, so it can be compiled and checked on its own.
//
//  A template is written the way a manual prints the message:
//
//      F0 3E 00 00 ( 60 00 VAL ) F7
//
//  Everything is a hex byte except:
//
//    VAL   the value being sent, expanded through the value format
//    ( )   the checksum's range; the closing bracket is where its byte goes
//
//  The address is deliberately *not* a symbol: each parameter's template is
//  its own line, differing from its siblings in exactly those bytes, so a
//  name standing for the address would need a field to read it from - and
//  there is no longer one.
//

import Foundation

/// How VAL expands on the wire.
///
/// The raw values are what the Inspector's menu shows, and nothing more. An
/// `encode` that took a `String` and worked out what to do by picking it
/// apart - `hasSuffix("Nibbles L")`, the byte count scraped out of the front
/// of "2 Nibbles L" with a number parser - would be a list of display names
/// doing duty as behaviour, where renaming a menu entry changes the bytes on
/// the wire.
///
/// Here the name is the name and the arithmetic is the arithmetic.
/// `.oneByte` is first and is the default: it is what a template means when
/// nothing says otherwise. The wider forms only became meaningful once a
/// value could exceed 127.
nonisolated enum ValueFormat: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case oneByte = "One Byte"
    case msbLsb = "MSB/LSB"
    case lsbMsb = "LSB/MSB"
    case bcd4LSB = "BCD 4 LSB"
    case bcd4MSB = "BCD 4 MSB"
    case twoNibblesLow = "2 Nibbles L"
    case threeNibblesLow = "3 Nibbles L"
    case fourNibblesLow = "4 Nibbles L"
    case twoNibblesHigh = "2 Nibbles M"
    case threeNibblesHigh = "3 Nibbles M"
    case fourNibblesHigh = "4 Nibbles M"
    case twoASCII = "2 ASCII M"
    case threeASCII = "3 ASCII M"
    case fourASCII = "4 ASCII M"

    var id: Self { self }

    /// How many bytes VAL becomes - how many slots the parser reserves for
    /// it, so a parsed line has one entry per byte on the wire.
    var byteCount: Int {
        switch self {
        case .oneByte: 1
        case .msbLsb, .lsbMsb: 2
        case .bcd4LSB, .bcd4MSB: 4
        case .twoNibblesLow, .twoNibblesHigh, .twoASCII: 2
        case .threeNibblesLow, .threeNibblesHigh, .threeASCII: 3
        case .fourNibblesLow, .fourNibblesHigh, .fourASCII: 4
        }
    }

    /// One value -> the bytes VAL stands for.
    ///
    /// Computed over the *whole* value rather than a 7-bit clamp of it, with
    /// only the individual output bytes masked - which is what lets a 14-bit
    /// control produce correct multi-byte output here without this function
    /// knowing anything about resolutions.
    ///
    /// A value past a format's capacity wraps rather than failing: every byte
    /// is masked to what its format holds.
    func encode(_ value: Int) -> [Int] {
        let value = max(0, value)

        switch self {
        case .oneByte:
            return [value & 0x7F]

        case .msbLsb:
            return [(value >> 7) & 0x7F, value & 0x7F]

        case .lsbMsb:
            return [value & 0x7F, (value >> 7) & 0x7F]

        case .bcd4MSB:
            return SysEx.decimalDigits(value, count: 4)

        case .bcd4LSB:
            return SysEx.decimalDigits(value, count: 4).reversed()

        case .twoNibblesLow, .threeNibblesLow, .fourNibblesLow:
            // Low nibble first.
            return (0..<byteCount).map { (value >> (4 * $0)) & 0x0F }

        case .twoNibblesHigh, .threeNibblesHigh, .fourNibblesHigh:
            return (0..<byteCount).map { (value >> (4 * $0)) & 0x0F }.reversed()

        case .twoASCII, .threeASCII, .fourASCII:
            // Truncating to the *last* N digits, not the first: a value past
            // the capacity has no faithful N-digit form either way, and keeping
            // the low digits at least tracks small changes.
            return SysEx.decimalDigits(value, count: byteCount).map { 0x30 + $0 }
        }
    }
}

/// The checksum arithmetics a SysEx template can close its bracket with.
///
/// Roland, Yamaha and "2's com" are the *same* computation - listed apart
/// because manuals name them that way. What actually differs between
/// devices is which bytes are covered, and that is the template's brackets,
/// not this list. There is no "No Checksum" entry either: whether there is a
/// checksum at all is the brackets' answer.
nonisolated enum ChecksumMode: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case roland = "Roland"
    case yamaha = "Yamaha"
    case twosComplement = "2's com"
    case sum = "Checksum"
    case onesComplement = "1's Com"

    var id: Self { self }

    /// The checksum byte over `data`.
    ///
    /// Always a byte: whether there *is* a checksum is the brackets' answer,
    /// so by the time this is called the question is only which one.
    func byte(over data: [Int]) -> Int {
        let total = data.reduce(0, +) & 0x7F
        switch self {
        case .sum: return total
        case .onesComplement: return (~total) & 0x7F
        case .roland, .yamaha, .twosComplement: return (-total) & 0x7F
        }
    }
}

nonisolated enum SysEx {
    static let start: UInt8 = 0xF0
    static let end: UInt8 = 0xF7
    static let startToken = "F0"
    static let endToken = "F7"

    static let checksumOpen = "("
    static let checksumClose = ")"
    /// What the closing bracket becomes once parsed. Not something anyone
    /// types - it is the parser saying where it put the checksum.
    static let checksumToken = "CS"

    /// What a template may say beyond plain hex bytes and the brackets.
    static let symbols = ["VAL"]

    /// What a parsed template came to: one token per byte, where the checksum
    /// starts summing, and a complaint.
    ///
    /// The complaint is empty when the line is sound; when it is not, it is
    /// what to show instead of the tokens.
    struct Parsed {
        var tokens: [String] = []
        /// The index summing starts at, or nil for no checksum. Usable as an
        /// index into the message precisely because every token is one byte.
        var checksumStart: Int?
        var problem: String = ""

        var isSound: Bool { problem.isEmpty && !tokens.isEmpty }
    }

    /// Parses a typed line.
    ///
    /// **Nothing throws.** This runs on every keystroke and on every send, and
    /// a half-typed line is a normal state rather than an error.
    ///
    /// Two things happen here that the typed line does not say outright. The
    /// brackets disappear and a CS token takes the closing one's place - the
    /// checksum is one byte at one position, and that position is where the
    /// range ends; where it *starts* is the opening bracket, which leaves no
    /// token behind, so it comes back as an index instead. And VAL becomes as
    /// many slots as the value format expands to, so the parsed line has one
    /// entry per byte on the wire and can be counted against the manual.
    ///
    /// F0 and F7 are added when missing, so what comes back is always the whole
    /// message - a line that did not show them would not be the message it
    /// claims to be.
    static func parse(_ template: String, format: ValueFormat = .oneByte) -> Parsed {
        // Brackets stuck to a token - "(10" and "VAL)" are how anyone would
        // type this, and both are two tokens.
        var spaced = template
        for bracket in [checksumOpen, checksumClose] {
            spaced = spaced.replacingOccurrences(of: bracket, with: " \(bracket) ")
        }

        var tokens: [String] = []
        var opens = 0, closes = 0
        for word in spaced.split(whereSeparator: \.isWhitespace).map({ $0.uppercased() }) {
            switch word {
            case checksumOpen:
                opens += 1
                if opens > 1 { return Parsed(problem: "one checksum range: a second (") }
                tokens.append(word)
            case checksumClose:
                closes += 1
                if closes > 1 { return Parsed(problem: "one checksum range: a second )") }
                if opens == 0 { return Parsed(problem: ") before (") }
                tokens.append(word)
            case "VAL":
                tokens.append(contentsOf: Array(repeating: "VAL", count: max(1, format.byteCount)))
            default:
                guard let byte = Int(word, radix: 16) else {
                    return Parsed(problem: "not a byte and not a name: \(word)")
                }
                guard (0...0xFF).contains(byte) else {
                    return Parsed(problem: "not a byte: \(word)")
                }
                tokens.append(String(format: "%02X", byte))
            }
        }

        if opens != closes { return Parsed(problem: "( without )") }
        if tokens.isEmpty { return Parsed() }

        // The brackets have done their work. The closing one becomes the CS
        // token; the opening one becomes the index that goes back with it.
        var start: Int?
        var kept: [String] = []
        for token in tokens {
            switch token {
            case checksumOpen:
                start = kept.count
            case checksumClose:
                if start == kept.count { return Parsed(problem: "nothing between ( and )") }
                kept.append(checksumToken)
            default:
                kept.append(token)
            }
        }

        if kept.first != startToken {
            kept.insert(startToken, at: 0)
            if start != nil { start! += 1 }
        }
        if kept.last != endToken {
            kept.append(endToken)
        }
        return Parsed(tokens: kept, checksumStart: start, problem: "")
    }

    /// The parsed line as one string - the tokens, or the complaint. What the
    /// parameter table's "Parsed" column shows.
    static func parsedText(_ template: String, format: ValueFormat = .oneByte) -> String {
        let parsed = parse(template, format: format)
        return parsed.problem.isEmpty ? parsed.tokens.joined(separator: " ") : parsed.problem
    }

    /// A typed template -> the whole message, F0 to F7.
    ///
    /// VAL is the value being sent, expanded through the format; everything
    /// else in the line is already the byte it will be.
    ///
    /// **An unsound template sends nothing at all.** That is unconfigured
    /// rather than an error, and half a message is worse than none.
    ///
    /// The frame comes off and goes back on around the data, which is not
    /// pedantry. Everything between F0 and F7 must be seven-bit, so every data
    /// byte is clamped - a manual mistyped as `FF` would otherwise put a status
    /// byte inside a message and shift the device's parse of everything after
    /// it. F0 and F7 are the two bytes that must *not* be clamped, so they are
    /// kept out of that loop entirely.
    ///
    /// What comes back here is the whole message, frame included: CoreMIDI
    /// takes the bytes as given rather than putting F0/F7 on the wire
    /// itself.
    static func message(
        template: String, value: Int,
        checksumMode: ChecksumMode = .roland, format: ValueFormat = .oneByte
    ) -> [UInt8] {
        let parsed = parse(template, format: format)
        guard parsed.isSound else { return [] }

        // The parser guarantees the frame, so this is where it comes off.
        var tokens = parsed.tokens
        var summingFrom = parsed.checksumStart ?? 0
        if tokens.first == startToken {
            tokens.removeFirst()
            // The index came back counting that F0, and it is no longer there.
            summingFrom = max(0, summingFrom - 1)
        }
        if tokens.last == endToken { tokens.removeLast() }

        var data: [Int] = []
        var checksumAt: Int?
        let expanded = format.encode(value)
        var used = 0

        for token in tokens {
            switch token {
            case "VAL":
                // One slot per byte, filled in order - the parser already made
                // as many slots as this format produces.
                data.append(clamp7(used < expanded.count ? expanded[used] : 0))
                used += 1
            case checksumToken:
                checksumAt = data.count
                data.append(0)              // placeholder, overwritten below
            default:
                data.append(clamp7(Int(token, radix: 16) ?? 0))
            }
        }

        if let checksumAt, summingFrom <= checksumAt {
            data[checksumAt] = checksumMode.byte(over: Array(data[summingFrom..<checksumAt]))
        }
        return [start] + data.map { UInt8($0 & 0x7F) } + [end]
    }

    /// `value` as exactly `count` decimal digits, keeping the low ones.
    /// Shared with ValueFormat's BCD and ASCII forms.
    static func decimalDigits(_ value: Int, count: Int) -> [Int] {
        let text = String(value)
        let padded = String(repeating: "0", count: max(0, count - text.count)) + text
        return padded.suffix(count).compactMap { $0.wholeNumberValue }
    }
}
