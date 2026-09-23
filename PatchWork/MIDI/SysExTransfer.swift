//
//  SysExTransfer.swift
//  PatchWork
//
//  How fast bytes are allowed to leave.
//
//  Nothing in MIDI says a device has to keep up. A synth from 1988 reads its
//  serial port into a buffer of a few dozen bytes and parses it between other
//  work; hand it a patch dump at full 31,250 baud and it drops whatever
//  arrived while busy - silently, since SysEx has no flow control and no
//  error to report. What comes back is a patch with wrong bytes, or nothing.
//  So the fix is in the sender: send less at once, wait in between.
//
//  Three numbers, the three every device manual argues about:
//
//      Chunk   how many bytes go out in one packet
//      Break   how long to wait before the next one
//      Timeout how long to wait for the device to say "got it"
//
//  A unit of transfer is one chunk of a long SysEx *or* one whole short
//  message - the break falls between units either way, which matters: a
//  panel's Send All is a hundred small messages back to back, flooding a
//  small buffer just as thoroughly as one long dump.
//
//  **These belong to the layout, not the application.** A .pwork panel is
//  built for one device, and how slowly it needs to be spoken to is a fact
//  about the device - it travels with the panel rather than being re-dialled
//  each time one opens. See PatchWorkDocument, optional the same way and for
//  the same reason as `windows` and `appearance`.
//
//  Defaults are 256 bytes and 10 ms - not the fastest the app can go (it used
//  to send 4096-byte packets with no gap at all), deliberately: 10 ms is
//  invisible to a hand on a knob (a forty-message Send All finishes in
//  0.4 s) while being the difference between arriving and not on old gear.
//

import Foundation

nonisolated struct SysExTransfer: Codable, Equatable {
    /// How the sender decides the next unit may go.
    ///
    /// Two, not the three that were sketched. An "adaptive" strategy - start
    /// fast, back off on failure - needs a failure to react to, and without a
    /// handshake there is none: `MIDISend` returns success whether the device
    /// digested the bytes or dropped them on the floor, which is the whole
    /// reason this file exists. Adaptive is therefore only ever "handshake
    /// with backoff", a variation on the second case rather than a third one,
    /// and nothing has asked for it yet.
    enum Strategy: String, Codable, CaseIterable, Identifiable {
        /// Unit, wait, unit, wait. Blind, and right for the overwhelming
        /// majority of devices - almost none of them acknowledge anything.
        case fixedDelay = "Fixed Delay"
        /// Unit, then wait for the device to answer before the next one.
        /// Only some protocols do this (Roland's handshaking dumps, Kawai,
        /// parts of the Yamaha bulk spec) and it needs an Input port chosen,
        /// since the reply arrives there.
        case handshake = "Handshake"

        var id: Self { self }
    }

    var strategy: Strategy = .fixedDelay
    /// Bytes per packet. Only SysEx is ever split - every other MIDI message
    /// is at most three bytes.
    var chunkBytes: Int = 256
    /// The gap between units, in milliseconds. Zero is a real answer: it
    /// means send as fast as CoreMIDI will take it.
    var breakMS: Int = 10
    /// How long a handshake waits for the device's reply before deciding it
    /// is not coming. Ignored by Fixed Delay, which is not listening.
    var timeoutMS: Int = 100
    /// How many times a unit is sent again after a timeout before the
    /// transfer gives up and says so.
    var retries: Int = 3

    /// What the Chunk menu offers. 16 at the bottom because that is the size
    /// the oldest gear is happiest with, 4096 at the top because that is the
    /// most a packet can honestly describe - see `maxChunkBytes`.
    static let chunkChoices = [16, 32, 64, 128, 256, 512, 1024, 2048, 4096]

    /// The ceiling on a chunk, and not a matter of taste: a `MIDIPacket`'s
    /// length field is a `UInt16` that CoreMIDI does not enforce, so a bigger
    /// packet silently wraps its own length and loses most of itself. See
    /// MIDIEngine.packetBytes, which is this same number by definition.
    static let maxChunkBytes = 4096

    /// The chunk actually used, whatever the stored number says.
    ///
    /// Clamped here rather than trusted, because these arrive from a JSON
    /// file a person may have edited: a zero would divide a message into
    /// infinitely many pieces, and anything past the ceiling would lose bytes
    /// without a word.
    var chunk: Int { min(max(chunkBytes, 1), Self.maxChunkBytes) }

    /// The break in seconds, which is what the clock and the timestamps want.
    /// Clamped to a second: a gap longer than that is not a slow device, it
    /// is a typo, and it would leave the app apparently hung.
    var breakSeconds: TimeInterval { min(max(Double(breakMS), 0), 1000) / 1000 }

    /// The handshake timeout, floored at a millisecond so a zero cannot turn
    /// every chunk into an instant failure.
    var timeout: Duration { .milliseconds(min(max(timeoutMS, 1), 10_000)) }

    /// How many extra attempts a unit gets. Bounded, for the reason the
    /// others are: a file could otherwise ask for a million.
    var retryLimit: Int { min(max(retries, 0), 20) }

    /// What the toolbar says it is set to, in one line.
    var summary: String {
        switch strategy {
        case .fixedDelay:
            "\(chunk) bytes, \(breakMS) ms apart"
        case .handshake:
            "\(chunk) bytes, waiting for a reply (\(timeoutMS) ms, \(retryLimit) retries)"
        }
    }
}
