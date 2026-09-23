//
//  ElementRandom.swift
//  PatchWork
//
//  Rolling a control's value. What a Random button presses.
//
//  Each type is rolled **the way it is read**: a control carrying named values
//  lands on one of them rather than between two, a checkbox is a coin, and an
//  envelope or a pad rolls every row it has - because a shape with one stage
//  rerolled is not a new shape, it is the same shape with a dent in it.
//
//  Separate from ControlOperation because a roll is not a gesture: nothing is
//  pointed at, nothing is dragged, and what it writes is decided by the type
//  alone. It reports whether anything moved, the same way a drag does, so the
//  caller sends the result the same way it sends a gesture.
//

import Foundation

extension CanvasElement {
    /// Whether this element takes part in a roll.
    ///
    /// Its own flag, and only for types that have one: **a Random button marked
    /// for randomising would be a button that presses itself.**
    var isRandomisable: Bool {
        random && !traits.contains(.button)
    }

    /// Rolls this element's value, and says whether anything changed.
    ///
    /// Deliberately not seeded or injectable: the one thing a caller needs to
    /// know is whether to send, and a roll that landed on the value it already
    /// held is a roll that changed nothing.
    mutating func randomise() -> Bool {
        var generator = SystemRandomNumberGenerator()
        return randomise(using: &generator)
    }

    /// The same roll against a generator you provide - which is what makes the
    /// invariants testable without asserting on luck.
    mutating func randomise<G: RandomNumberGenerator>(using generator: inout G) -> Bool {
        let ceiling = valueCeiling

        switch type {
        case .ad, .adsr, .mseg, .xyPad, .xyQuad:
            // Every row, for the reason in the file header.
            var moved = false
            for row in parameters.indices {
                let wanted = Int.random(in: 0...ceiling, using: &generator)
                if parameters[row].value != wanted {
                    parameters[row].value = wanted
                    moved = true
                }
            }
            return moved

        case .knob, .slider:
            // On an entry, not between two: "halfway between Saw and Square"
            // is not a waveform. Only when the list is actually in force -
            // that is what the Value List switch says.
            let wanted: Int
            if useValues, !values.isEmpty, let entry = values.randomElement(using: &generator) {
                wanted = entry.number
            } else {
                wanted = Int.random(in: valueRange, using: &generator)
            }
            guard parameters.indices.contains(0), parameters[0].value != wanted else { return false }
            parameters[0].value = wanted
            return true

        case .checkbox:
            let wanted = Bool.random(using: &generator)
            guard checked != wanted else { return false }
            checked = wanted
            return true

        case .radio:
            let wanted = Int.random(in: 1...max(1, segmentCount), using: &generator)
            guard selected != wanted else { return false }
            selected = wanted
            return true

        case .combobox:
            let wanted = Int.random(in: 1...max(1, ValueList.entryCount(values)), using: &generator)
            guard selected != wanted else { return false }
            selected = wanted
            return true

        case .header, .label, .led, .status, .monitor,
             .random, .sendAll, .panic, .midiPlayer:
            // Furniture, the display elements, the buttons - nothing to roll.
            return false
        }
    }
}

extension Array where Element == CanvasElement {
    /// Rolls every element marked Random, and returns those that moved - so the
    /// caller sends exactly what changed and nothing else.
    ///
    /// One pass over the canvas, and each element that moved goes out the same
    /// way a gesture on it would, which keeps the protocol rules in the one
    /// place that has them.
    mutating func randomiseMarked() -> [CanvasElement] {
        var rolled: [CanvasElement] = []
        for index in indices where self[index].isRandomisable {
            if self[index].randomise() { rolled.append(self[index]) }
        }
        return rolled
    }
}
