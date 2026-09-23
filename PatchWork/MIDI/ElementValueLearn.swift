//
//  ElementValueLearn.swift
//  PatchWork
//
//  Learn Values: the second question you can ask a device by moving one of
//  its controls. Learn asks *which parameter is this* and writes an address.
//  This asks *which values does it take* and writes the list - step a
//  synth's waveform selector and it reports 0, 16, 32, 48, exactly the
//  numbers a Value List needs and nobody wants to type out of a manual.
//
//  Its own file rather than a function in ElementLearn.swift, whose header
//  says Learn writes the address and never the value. This is the other
//  half; keeping them apart lets each say plainly what it does.
//
//  **Addressed messages only.** `matches` is the filter, so a control has to
//  be pointed somewhere before its values can be collected - ⌘K first, or
//  the number typed. A real precondition: a device streaming an LFO down
//  another CC would otherwise fill the list with a waveform nobody chose.
//
//  Like Learn, this listens to the **Input and nothing else** - both ask
//  `Learn.accepts`, so the two halves cannot drift apart, and for the same
//  reason: the Input is the device the panel is being built for, so its
//  values are what the list is about.
//

import Foundation

extension CanvasElement {
    /// Appends what just arrived to the Value List, and says whether it did.
    ///
    /// Arrival order, not sorted: the order the device steps through its own
    /// values is information - a waveform list reads in the order the front
    /// panel walks it - and sorting would throw that away for a tidiness the
    /// entries can be dragged into later anyway.
    ///
    /// The name is left empty. `ValueList.entryNames` and `nearestEntryName`
    /// already read an unnamed entry out as its own number, so a captured
    /// list is legible the moment it exists and the names get typed over the
    /// top of it.
    ///
    /// Refused, in this order:
    ///
    /// - no list to append to - the type has none, or the switch is off;
    /// - not addressed to this element, which also covers SysEx: `matches`
    ///   never claims a payload, since recognising one means matching a
    ///   stored template against arriving bytes;
    /// - outside the control's resolution - a 7-bit control has no 9000.
    ///   Skipped rather than clamped: clamping would file an entry at 127 that
    ///   nothing ever sent. Min/Max are *not* consulted, because a value list
    ///   defines its own legal values;
    /// - already in the list. This is what makes a knob sweep survivable, and
    ///   what "existing values are skipped" means;
    /// - the list is full. A 14-bit NRPN swept end to end would otherwise
    ///   file thousands of entries before a hand left the knob.
    @discardableResult
    mutating func captureValue(_ incoming: IncomingMessage) -> Bool {
        guard traits.contains(.valueList), useValues else { return false }
        guard values.count < ElementOptions.valueLearnMaxEntries else { return false }
        guard matches(incoming) else { return false }

        // The resolution's own bounds, not valueRange: Min/Max have no say
        // over a value list - see CanvasElement.valueListActive - so a
        // narrowed range must not silently drop entries the device really
        // sends.
        guard (0...valueCeiling).contains(incoming.value) else { return false }
        guard !values.contains(where: { $0.number == incoming.value }) else { return false }

        values.append(ValueEntry(name: "", number: incoming.value))
        return true
    }

    /// Whether Learn Values could collect anything for this element, which is
    /// what greys the checkbox out.
    ///
    /// The same three conditions `matches` imposes, asked ahead of any
    /// message rather than after one fails to arrive: a control with several
    /// rows is not addressed as a whole, and a SysEx payload is not matched
    /// at all.
    ///
    /// Note what is *not* among them: whether the address has been set yet.
    /// There is no such state - `cc` is an `Int` seeded at
    /// `ParameterSchema.firstAddress`, which is a placeholder by intent but a
    /// perfectly real CC 70 by value, and reading the seed back as "not
    /// addressed" would grey the box out on anyone who genuinely wants it.
    var canLearnValues: Bool {
        traits.contains(.valueList) && useValues
            && output != .sysEx && parameters.count == 1
    }
}
