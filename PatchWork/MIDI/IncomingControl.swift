//
//  IncomingControl.swift
//  PatchWork
//
//  What an arriving message does to the layout: which control it is
//  addressed to, and how that control reads the number back.
//
//  The inverse of ElementMessages, and deliberately next to nothing else -
//  an element that sends CC 74 on channel 3 is the element an incoming CC 74
//  on channel 3 belongs to, and the two statements must not drift apart.
//
//  This only ever runs in active mode; the editor is where nothing outside
//  it may type. That gate lives in ContentView, with the mode.
//

import Foundation

/// Which property operating a control changes.
///
/// A type absent from here cannot be operated at all. The envelopes and pads
/// are exactly that: their value is a shape rather than a number, so they
/// are moved by grabbing a node, which is its own step.
enum LiveProperty {
    /// The single parameter's value: a knob or a fader.
    case value
    /// A checkbox's tick.
    case checked
    /// A radio strip's or combo box's chosen entry.
    case selected

    static func of(_ type: ElementType) -> LiveProperty? {
        switch type {
        case .knob, .slider: .value
        case .checkbox: .checked
        case .radio, .combobox: .selected
        // The envelopes and the pads have a shape rather than a number, the
        // furniture and the display elements have nothing to move, and the
        // buttons are pressed rather than set.
        case .ad, .adsr, .mseg, .xyPad, .xyQuad,
             .header, .label, .led, .status, .monitor,
             .random, .sendAll, .panic, .midiPlayer: nil
        }
    }
}

/// What an arriving message would do to a control - the answer to "would this
/// move anything", carried rather than performed.
///
/// It exists so that finding out can be a **read**. Writing to the layout is
/// what repaints the panel, and the layout lives in `@State`, whose setter
/// fires whether or not the value differs - so a write that changes nothing
/// still costs a full redraw of every element. Asking first is therefore worth
/// a type.
nonisolated enum LiveChange: Equatable {
    case value(Int)
    case checked(Bool)
    case selected(Int)
}

extension CanvasElement {
    /// Whether `incoming` is addressed to this control.
    ///
    /// Only a single-parameter control can be addressed as a whole. An
    /// element that holds several rows is not itself addressed - its rows
    /// are, one at a time - and none of those types can be moved by a
    /// message anyway (see LiveProperty), so matching one would raise a
    /// question nothing could answer yet.
    ///
    /// SysEx never matches. Recognising a payload means matching a stored
    /// template against arriving bytes with the placeholders standing for
    /// anything - real work, and its own step. Half-doing it here would mean
    /// controls quietly reacting to the wrong messages, which is worse than
    /// not reacting.
    func matches(_ incoming: IncomingMessage) -> Bool {
        guard parameters.count == 1, let parameter = parameters.first else { return false }
        guard incoming.channel == clampChannel(channel) else { return false }

        switch output {
        case .cc:
            return incoming.kind == .controlChange && incoming.number == clamp7(parameter.cc)
        case .nrpnMSBLSB, .nrpnLSBMSB:
            // Both variants address the same parameter - they differ only in
            // the order the two data-entry halves are *sent*, which is gone
            // by the time the decoder has reassembled them.
            let address = (clamp7(parameter.paramMSB) << 7) | clamp7(parameter.paramLSB)
            return incoming.kind == .nrpn && incoming.number == address
        case .program:
            // A Program Change has no address beyond its channel.
            return incoming.kind == .programChange
        case .sysEx:
            // Never matches - see the note above.
            return false
        }
    }

    /// Moves this control to what arrived, and says whether anything changed.
    ///
    /// Each type reads the number back the way it would have written it: a
    /// radio strip looks the value up in its own table rather than treating
    /// it as a position, and a checkbox reads MIDI's half-way convention.
    ///
    /// The return value matters for more than repainting: an echo of what
    /// this panel just sent costs a comparison instead of a write.
    func resolved(_ incoming: IncomingMessage) -> LiveChange? {
        switch LiveProperty.of(type) {
        case .value:
            let wanted = min(max(incoming.value, 0), valueCeiling)
            guard parameters.indices.contains(0), parameters[0].value != wanted else { return nil }
            return .value(wanted)

        case .checked:
            // 64 is where MIDI puts a switch: below is off, at or above is on.
            let wanted = incoming.value >= 64
            guard checked != wanted else { return nil }
            return .checked(wanted)

        case .selected:
            // The nearest entry by its stored number, not by position - the
            // entries are what this control means, and their numbers need be
            // neither consecutive nor sorted. With no entries there is
            // nothing to land on, so nothing moves.
            guard !values.isEmpty else { return nil }
            let nearest = values.indices.min {
                abs(values[$0].number - incoming.value) < abs(values[$1].number - incoming.value)
            }
            guard let nearest else { return nil }
            let wanted = nearest + 1     // Selected is 1-based, as in the Inspector.
            guard selected != wanted else { return nil }
            return .selected(wanted)

        case nil:
            return nil
        }
    }

    /// Performs what `resolved` worked out. Only ever called with a change
    /// this element itself produced, which is why it can be this short.
    mutating func apply(_ change: LiveChange) {
        switch change {
        case .value(let wanted):
            guard parameters.indices.contains(0) else { return }
            parameters[0].value = wanted
        case .checked(let wanted):
            checked = wanted
        case .selected(let wanted):
            selected = wanted
        }
    }

    /// Moves this control to what arrived, and says whether anything changed.
    @discardableResult
    mutating func apply(_ incoming: IncomingMessage) -> Bool {
        guard let change = resolved(incoming) else { return false }
        apply(change)
        return true
    }
}

extension Array where Element == CanvasElement {
    /// Applies everything that arrived to whatever it addresses, and says
    /// whether the canvas needs redrawing at all.
    ///
    /// One message can move several controls: two knobs may perfectly well
    /// be pointed at the same CC, and both should follow the device rather
    /// than only whichever happens to be first.
    ///
    /// Discardable because the app never needs the answer: it asks
    /// `wouldChange` first, and by the time it applies it already knows. The
    /// Bool stays for the harness, which checks the two agree.
    @discardableResult
    mutating func apply(_ messages: [IncomingMessage]) -> Bool {
        var changed = false
        for message in messages {
            for index in indices where self[index].matches(message) {
                if self[index].apply(message) { changed = true }
            }
        }
        return changed
    }

    /// Whether any of this would move anything - **without touching a thing.**
    ///
    /// The question the caller has to ask first. The layout lives in `@State`,
    /// which has no `_modify`: a `mutating` call on it is a get, a copy, a
    /// mutation and then an unconditional `set`, and that `set` marks the whole
    /// canvas dirty whether or not a single element moved. So a controller
    /// streaming a CC this panel does not even use was repainting every element
    /// on it, sixty times a second, to change nothing.
    ///
    /// Reading is free by comparison: `matches` and `resolved` allocate nothing.
    ///
    /// A batch whose messages cancel each other out - the same control set to
    /// two different values, ending where it started - still answers true here,
    /// because each message is weighed against the state as it stands now. That
    /// is one needless repaint in a case that essentially does not arise, and
    /// the alternative is carrying a running copy of the layout to ask about.
    func wouldChange(for messages: [IncomingMessage]) -> Bool {
        for message in messages {
            for index in indices where self[index].matches(message) {
                if self[index].resolved(message) != nil { return true }
            }
        }
        return false
    }
}
