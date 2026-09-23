//
//  MIDIFile.swift
//  PatchWork
//
//  Reading a Standard MIDI File into the events that go on the wire, and when.
//
//  A format to implement rather than a library to call, which is the same
//  position the stream parser is in (see MIDIInput). What comes out is the
//  playable messages in order, each with the time it happens at.
//
//  **Absolute times, not deltas.** A player that slept for each delta in turn
//  would accumulate every rounding error in the file and drift measurably by
//  the end of a long one; with absolute times it can sleep until a deadline
//  measured from one start.
//
//  Meta events are read and then dropped, except the one that matters: a tempo
//  change alters how every following tick converts to seconds, so it has to be
//  followed even though it never goes out.
//

import Foundation

/// One thing to send, and when - measured from the start of the file.
///
/// `nonisolated` because the player's refill loop reads these from a task of
/// its own rather than from the main actor, and this file's default isolation
/// would otherwise make every `event.time` a cross-actor read.
nonisolated struct MIDIFileEvent: Equatable, Sendable {
    let time: TimeInterval
    let bytes: [UInt8]
}

/// A parsed file: what to send, and how long the file runs.
///
/// **The length is not the last event's time.** A file that ends with a rest
/// says so with its End of Track, and that meta event never goes on the wire -
/// so a player measuring the file by its own events would restart on the last
/// note-off and drop the rest, every pass. Which is a loop that does not sit
/// on the bar. The length is therefore parsed and carried rather than inferred
/// later from something that cannot tell.
nonisolated struct MIDIFileContents: Equatable, Sendable {
    let events: [MIDIFileEvent]
    let duration: TimeInterval
}

enum MIDIFileError: LocalizedError, Equatable {
    case notAMIDIFile
    case truncated
    case unsupportedFormat(Int)

    var errorDescription: String? {
        switch self {
        case .notAMIDIFile: "That is not a MIDI file."
        case .truncated: "The MIDI file ends in the middle of something."
        case .unsupportedFormat(let format): "MIDI file format \(format) is not supported."
        }
    }
}

enum MIDIFile {
    /// The default tempo when a file never states one: 120 BPM, half a second
    /// per quarter note, which is what the specification says to assume.
    static let defaultMicrosecondsPerQuarter = 500_000

    /// Reads `data` into the events to play, in time order.
    ///
    /// Format 0 and 1 both come out as one stream: format 1's tracks are meant
    /// to sound together, so merging them by tick is what playing them means.
    /// Format 2's tracks are independent sequences rather than parts of one
    /// piece, and picking one for the user would be a guess.
    static func parse(_ data: Data) throws -> MIDIFileContents {
        var reader = Reader(data)
        guard reader.string(4) == "MThd" else { throw MIDIFileError.notAMIDIFile }
        let headerLength = try reader.uint32()
        let format = Int(try reader.uint16())
        let trackCount = Int(try reader.uint16())
        let division = Int(try reader.uint16())
        // The header is six bytes today and the format reserves the right to
        // grow it, so anything past what we read is skipped rather than assumed
        // absent.
        try reader.skip(Int(headerLength) - 6)
        guard format == 0 || format == 1 else { throw MIDIFileError.unsupportedFormat(format) }

        // Every track's events, still in ticks, tagged with the track they came
        // from so a stable sort can keep same-tick events in their original
        // order within a track.
        var tagged: [(tick: Int, order: Int, track: Int, bytes: [UInt8])] = []
        for track in 0..<trackCount {
            // A file may claim more tracks than it carries; what is there is
            // what plays.
            guard reader.canRead(8) else { break }
            let chunk = reader.string(4)
            let length = Int(try reader.uint32())
            guard chunk == "MTrk" else {
                // An unknown chunk type is to be skipped, says the spec.
                try reader.skip(length)
                continue
            }
            let end = reader.offset + length
            var tick = 0
            var runningStatus: UInt8?
            var order = 0
            while reader.offset < end {
                tick += Int(try reader.variableLength())
                // Nil means the data ran out, and the loop has to stop on it:
                // the cursor does not advance past the end, so carrying on
                // would spin here for ever.
                guard let bytes = try readEvent(&reader, runningStatus: &runningStatus) else { break }
                // Empty means read and stepped over rather than kept - see
                // readEvent, which does that to the bytes that have no
                // business in a file but turn up in one anyway.
                guard !bytes.isEmpty else { continue }
                tagged.append((tick, order, track, bytes))
                order += 1
            }
            // Trust the chunk length over where the events happened to end -
            // a track that lies about its own contents must not swallow the
            // next one.
            reader.offset = min(end, reader.count)
        }

        // Tempo changes have to be applied in tick order across every track,
        // since one track's tempo governs all of them.
        tagged.sort { a, b in
            a.tick != b.tick ? a.tick < b.tick
                : (a.track != b.track ? a.track < b.track : a.order < b.order)
        }

        var events: [MIDIFileEvent] = []
        var seconds: TimeInterval = 0
        var lastTick = 0
        var tempo = defaultMicrosecondsPerQuarter
        // The latest moment any track declares itself over. The whole reason
        // the meta events are still here: this is the one thing they say that
        // outlives them, and it is what the file's length actually is.
        var declaredEnd: TimeInterval = 0
        for entry in tagged {
            seconds += ticksToSeconds(entry.tick - lastTick, division: division, tempo: tempo)
            lastTick = entry.tick
            if let newTempo = setTempo(in: entry.bytes) {
                // Read, followed, and not sent: a tempo change is an
                // instruction to this player, not to the device.
                tempo = newTempo
                continue
            }
            if isEndOfTrack(entry.bytes) {
                // The latest of them, not the first: in a format 1 file the
                // parts end where the longest one does.
                declaredEnd = max(declaredEnd, seconds)
                continue
            }
            guard isPlayable(entry.bytes) else { continue }
            events.append(MIDIFileEvent(time: seconds, bytes: entry.bytes))
        }
        // A file with no End of Track anywhere - truncated, or written by
        // something careless - falls back to its own last event, which is
        // what the length used to be for every file.
        return MIDIFileContents(events: events,
                                duration: max(declaredEnd, events.last?.time ?? 0))
    }

    /// How long `ticks` last at the current tempo.
    ///
    /// Two divisions exist and they are not variations of one thing. A positive
    /// division is ticks per quarter note, so the tempo decides how long a tick
    /// is; a negative one is SMPTE, where the top byte is a (negative) frame
    /// rate and the low byte ticks per frame - real time, which no tempo change
    /// can alter.
    static func ticksToSeconds(_ ticks: Int, division: Int, tempo: Int) -> TimeInterval {
        guard ticks != 0 else { return 0 }
        if division & 0x8000 == 0 {
            let perQuarter = max(1, division)
            return TimeInterval(ticks) * TimeInterval(tempo) / 1_000_000 / TimeInterval(perQuarter)
        }
        // 29 stands for 29.97 drop-frame, which is what the value actually
        // means wherever it appears.
        let frames = TimeInterval(256 - (division >> 8))
        let perFrame = TimeInterval(max(1, division & 0xFF))
        let rate = frames == 29 ? 29.97 : frames
        return TimeInterval(ticks) / (rate * perFrame)
    }

    /// Whether these bytes are something to put on the wire. Meta events are
    /// not; everything else in a file is.
    private static func isPlayable(_ bytes: [UInt8]) -> Bool {
        guard let status = bytes.first else { return false }
        return status != 0xFF
    }

    /// Whether these bytes are the End of Track meta event, which is where the
    /// file says it stops - as opposed to where it last made a sound.
    private static func isEndOfTrack(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0x2F
    }

    /// The new tempo in microseconds per quarter note, if this is a Set Tempo
    /// meta event.
    private static func setTempo(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 5, bytes[0] == 0xFF, bytes[1] == 0x51 else { return nil }
        return (Int(bytes[2]) << 16) | (Int(bytes[3]) << 8) | Int(bytes[4])
    }

    /// One event's bytes, empty for one that was read and stepped over, or nil
    /// when the data has run out.
    ///
    /// Meta events come back whole, tagged with their 0xFF, and are dropped
    /// later - the tempo reader and the length reader above need to see them
    /// first. Empty is different from both: the cursor has advanced correctly
    /// past something that is not going anywhere.
    private static func readEvent(_ reader: inout Reader, runningStatus: inout UInt8?) throws -> [UInt8]? {
        guard let first = reader.peek() else { return nil }

        if first == 0xFF {
            // Meta: FF type length data. Kept whole so the tempo reader above
            // can look at it; dropped when it is anything else.
            _ = try reader.byte()
            let type = try reader.byte()
            let length = Int(try reader.variableLength())
            let data = try reader.bytes(length)
            runningStatus = nil
            // The length is the file's own framing, not part of the event, so
            // it comes off here - as it does for SysEx below.
            return [0xFF, type] + data
        }

        if first == 0xF0 || first == 0xF7 {
            // SysEx, and the F7 escape that continues one or carries arbitrary
            // bytes. The length is the file's own framing rather than part of
            // the message, so it comes off here.
            let status = try reader.byte()
            let length = Int(try reader.variableLength())
            let data = try reader.bytes(length)
            runningStatus = nil
            // An F0 event's payload is written without its leading F0, which
            // has to go back on for the message to be a message.
            return status == 0xF0 ? [0xF0] + data : data
        }

        if first >= 0xF1 {
            // System common and real time. Neither belongs in a track - 0xF0
            // and 0xF7 above are the only system bytes a file may carry - but
            // they turn up in files dumped from a live stream, and each has
            // its own number of data bytes, never the two a channel message
            // has. Reading them as a channel message is what desynchronises
            // every delta time after it, and a whole track then plays as noise
            // at nonsensical moments.
            //
            // Read to be stepped over rather than kept: a clock byte belongs
            // to the stream it was recorded from, not to this playback, and a
            // song position means nothing to a file already playing.
            let status = try reader.byte()
            let dataCount = switch status {
            case 0xF1, 0xF3: 1              // quarter frame, song select
            case 0xF2: 2                    // song position
            default: 0                      // tune request, and the real-time bytes
            }
            // Real time may interrupt a running-status run without ending it,
            // which is the whole point of it being one byte anywhere. The rest
            // of system common ends it.
            if status < 0xF8 { runningStatus = nil }
            _ = try reader.bytes(dataCount)
            return []
        }

        let status: UInt8
        if first & 0x80 != 0 {
            status = try reader.byte()
            runningStatus = status
        } else {
            // Running status: the byte is data, and the status is whatever the
            // last one was. A file that starts a track this way is broken.
            guard let running = runningStatus else { throw MIDIFileError.truncated }
            status = running
        }
        let dataCount = (status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0 ? 1 : 2
        return [status] + (try reader.bytes(dataCount))
    }

    /// A cursor over the file's bytes. Every read is bounds-checked, because a
    /// truncated or hostile file is a file someone will drop on this sooner or
    /// later, and reading past the end must be an error rather than a crash.
    private struct Reader {
        let data: [UInt8]
        var offset = 0

        init(_ data: Data) { self.data = [UInt8](data) }

        var count: Int { data.count }
        func canRead(_ n: Int) -> Bool { offset + n <= data.count }
        func peek() -> UInt8? { offset < data.count ? data[offset] : nil }

        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw MIDIFileError.truncated }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func bytes(_ n: Int) throws -> [UInt8] {
            guard n >= 0, canRead(n) else { throw MIDIFileError.truncated }
            defer { offset += n }
            return Array(data[offset..<offset + n])
        }

        mutating func string(_ n: Int) -> String {
            guard canRead(n) else { return "" }
            defer { offset += n }
            return String(decoding: data[offset..<offset + n], as: UTF8.self)
        }

        mutating func uint16() throws -> UInt16 {
            let pair = try bytes(2)
            return UInt16(pair[0]) << 8 | UInt16(pair[1])
        }

        mutating func uint32() throws -> UInt32 {
            let quad = try bytes(4)
            return quad.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }

        mutating func skip(_ n: Int) throws {
            guard n >= 0 else { return }
            guard canRead(n) else { throw MIDIFileError.truncated }
            offset += n
        }

        /// A variable-length quantity: seven bits per byte, high bit set on
        /// every byte but the last. Capped at four bytes, which is the most the
        /// format allows and also what stops a run of 0x80s spinning here.
        mutating func variableLength() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = try self.byte()
                value = (value << 7) | UInt32(byte & 0x7F)
                if byte & 0x80 == 0 { return value }
            }
            return value
        }
    }
}
