//
//  ElementMessages.swift
//  PatchWork
//
//  What a whole element sends, and what a whole layout sends - the step
//  between MIDIPlanner (which knows one parameter) and MIDIEngine (which
//  knows the wire).
//
//  One row is one parameter with an address of its own, so this is the
//  planner run over each of them.
//  What differs from a single-parameter control is only how many addresses
//  there are, which is why the same call covers a knob and an ADSR.
//

import Foundation

extension CanvasElement {
    /// Everything this element sends, one parameter after another.
    ///
    /// Empty for a type that addresses nothing - a Header, a Label, the
    /// display elements, the action buttons. `ElementTraits.sends` is the
    /// same answer the Inspector uses to decide whether to offer an output
    /// section at all, so a type cannot end up sending without having
    /// somewhere to configure it.
    var midiMessages: [MIDIMessage] {
        guard traits.contains(.sends) else { return [] }
        return parameters.flatMap { parameter in
            MIDIPlanner.messages(
                output: output,
                channel: channel,
                ceiling: valueCeiling,
                parameter: parameter,
                value: sentValue(for: parameter),
                checksum: checksum,
                valueFormat: valueFormat
            )
        }
    }

    /// What a parameter actually transmits, which is not always what it
    /// stores: what a control *holds* and what it *sends* only coincide for
    /// the continuous ones.
    private func sentValue(for parameter: ElementParameter) -> Int {
        switch type {
        case .checkbox:
            // Off and on at the two ends of the element's own domain, so a
            // 14-bit checkbox sends 16383 rather than a 7-bit 127 that the
            // receiving end would read as a small number.
            return checked ? valueCeiling : 0

        case .radio, .combobox:
            // These hold a *position* and send the number their value table
            // pairs with it - which is what the table is for. Reading the
            // stored parameter value instead would send the same number
            // whichever segment was picked.
            let index = selected - 1
            if values.indices.contains(index) {
                return values[index].number
            }
            // No entry to read a number off: the position stands in for it,
            // so an unfilled strip still sends something that tells its
            // segments apart rather than sending nothing at all.
            return max(0, index)

        default:
            return parameter.value
        }
    }
}

extension Array where Element == CanvasElement {
    /// Every element's messages, in canvas order - what Send All sends.
    ///
    /// In placement order rather than sorted by address: a panel is read
    /// the way it was built, and a device that cares about the order of two
    /// unrelated parameters is a device with worse problems.
    var midiMessages: [MIDIMessage] {
        flatMap(\.midiMessages)
    }
}
