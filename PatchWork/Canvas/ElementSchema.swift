//
//  ElementSchema.swift
//  PatchWork
//
//  The vocabulary: which element types exist, which protocols and formats
//  they can be set to, and which properties each type actually carries.
//
//  Every one of these is an enum rather than a bare `String`: a `switch`
//  over an enum is exhaustive, so adding a type or a protocol makes the
//  compiler name every place that has to answer for it - where a `switch`
//  over a string quietly falls through to `default` and sends the wrong
//  thing.
//
//  **The raw values are the strings themselves.** They are what a .pwork
//  file holds and what the Inspector's menus read, so the enum is a
//  compile-time gain that costs nothing on disk or on screen.
//
//  Which properties a type has is an ElementTraits option set rather than a
//  full property schema describing each one as data (kind, bounds, options,
//  `when` rules) so the inspector could build a form with no per-type branch
//  at all. That is the better end state, but it only pays for itself once
//  properties are numerous and irregular enough that hand-written sections
//  stop scaling - this is the smaller step that keeps InspectorPanel's
//  section list readable in the meantime.
//

import Foundation

/// One of the Inspector's menu-backed choices: a fixed set of options, each
/// with a name to show.
///
/// The pickers read `allCases` off the type itself rather than being handed
/// a list of option strings beside it. A list that lives beside the type it
/// describes can disagree with it - offer an entry the property cannot hold,
/// or miss one it can. `allCases` cannot.
nonisolated protocol InspectorChoice: Hashable, CaseIterable, Identifiable, Sendable
where AllCases == [Self] {
    /// What the menu entry reads.
    var title: String { get }
}

/// Every one of these spells its own name: the raw value is both what a
/// .pwork file holds and what the menu shows, which is why they were
/// readable as bare strings for so long.
///
/// `nonisolated` like everything else in this file: the app target defaults
/// to the main actor, and a default implementation that picked that up would
/// make the *conformance* main-actor-isolated - which is an error in the
/// Swift 6 language mode for types that are themselves nonisolated.
nonisolated extension InspectorChoice where Self: RawRepresentable, RawValue == String {
    var title: String { rawValue }
}

/// Every placeable control. Raw values are what a .pwork file stores and
/// what the Library rows and a fresh element's name read.
nonisolated enum ElementType: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case knob = "Knob"
    case slider = "Slider"
    case xyPad = "XY Pad"
    case xyQuad = "XY Quad"
    case radio = "Radio"
    case checkbox = "Checkbox"
    case combobox = "Combobox"
    case ad = "AD"
    case adsr = "ADSR"
    case mseg = "MSEG"
    case random = "Random"
    case sendAll = "Send All"
    case panic = "Panic"
    case midiPlayer = "MIDI Player"
    case led = "LED"
    case status = "Status"
    case monitor = "Monitor"
    case header = "Header"
    case label = "Label"

    var id: Self { self }
}

/// How a control addresses the device.
nonisolated enum OutputProtocol: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case cc = "CC"
    case nrpnMSBLSB = "NRPN (MSB/LSB)"
    case nrpnLSBMSB = "NRPN (LSB/MSB)"
    case sysEx = "SysEx"
    case program = "Program"

    var id: Self { self }
}

/// How wide a value may be.
nonisolated enum Resolution: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case sevenBit = "7-bit"
    case fourteenBit = "14-bit"

    var id: Self { self }

    /// The largest raw value this resolution reaches.
    ///
    /// This bounds the *value*; which CC number addresses it is a separate
    /// domain that stays 7-bit either way (CanvasLayout.ccRange).
    var ceiling: Int {
        switch self {
        case .sevenBit: 127
        case .fourteenBit: 16383
        }
    }
}

/// How a Label's text sits in its own box.
nonisolated enum LabelAlignment: String, Codable, CaseIterable, Identifiable, InspectorChoice {
    case left = "Left"
    case center = "Center"
    case right = "Right"

    var id: Self { self }
}

/// What one element type carries. Every member maps to one Inspector
/// section; a type carrying none of them still gets Name and Geometry,
/// which everything has.
///
/// An OptionSet rather than a struct of `Bool`s, because what a
/// multi-selection's Inspector shows is the *intersection* of what its
/// elements carry - and `intersection` is then the standard-library
/// operation rather than fifteen hand-written `&&` lines that a new
/// property has to be remembered into.
nonisolated struct ElementTraits: OptionSet, Sendable {
    let rawValue: Int

    /// This control addresses the device, so it gets the
    /// Output/Resolution/Channel block and the Random flag. A Header or a
    /// Monitor does not.
    static let sends = ElementTraits(rawValue: 1 << 0)
    /// One value of its own.
    static let value = ElementTraits(rawValue: 1 << 1)
    /// Draw style only: fills from the middle of the travel outward rather
    /// than from the low end up.
    static let bipolar = ElementTraits(rawValue: 1 << 2)
    /// Pressed to do something rather than to hold a value. Four different
    /// effects behind the one press, and none of them is a value, which is
    /// why a button is never randomisable: a Random button marked Random
    /// would press itself.
    static let button = ElementTraits(rawValue: 1 << 3)
    /// Radio's segment count.
    static let segments = ElementTraits(rawValue: 1 << 4)
    /// Which entry is picked, 1-based.
    static let selected = ElementTraits(rawValue: 1 << 5)
    /// The four envelope stages.
    static let adsrStages = ElementTraits(rawValue: 1 << 6)
    /// Whether the box is ticked.
    static let checked = ElementTraits(rawValue: 1 << 7)
    /// Whether the MSEG's last node is a release node.
    static let releaseNode = ElementTraits(rawValue: 1 << 8)
    /// Whether the heading is a filled bar or a bare separator.
    static let filled = ElementTraits(rawValue: 1 << 9)
    /// Whether the text's alignment is the user's choice - only the Label,
    /// since a heading is always centred.
    static let align = ElementTraits(rawValue: 1 << 10)
    /// Whether it asks for a number of message lines.
    static let lines = ElementTraits(rawValue: 1 << 11)
    /// Whether nodes can be added and removed. Only the MSEG: the other
    /// envelopes' shapes are fixed by what they are.
    static let variableNodes = ElementTraits(rawValue: 1 << 12)
    /// The "Value List" switch.
    static let valueList = ElementTraits(rawValue: 1 << 13)
    /// Whether this type's axes can be sent backwards. True for both
    /// pads: the flag lives on each axis-parameter (see
    /// ElementParameter.inverted), so the plain pad's two and the quad's
    /// four fall out of the parameter count rather than needing separate
    /// declarations.
    static let invertibleAxes = ElementTraits(rawValue: 1 << 14)
    /// Whether this type's value has its own, narrower min/max than the
    /// resolution's 0...ceiling (CanvasElement.parameterMin/parameterMax).
    /// Knob and Slider only - the other addressable types either aren't a
    /// single continuous value (Radio, ADSR, MSEG, the pads) or don't send
    /// at all.
    static let customRange = ElementTraits(rawValue: 1 << 15)
}

extension ElementType {
    /// What this type carries.
    ///
    /// Exhaustive on purpose: a new element type does not compile until it
    /// has said what it carries.
    var traits: ElementTraits {
        switch self {
        case .knob, .slider:
            [.sends, .value, .bipolar, .valueList, .customRange]
        case .radio:
            [.sends, .segments, .selected, .valueList]
        case .combobox:
            [.sends, .selected, .valueList]
        case .checkbox:
            [.sends, .checked]
        case .adsr:
            [.sends, .adsrStages]
        case .ad:
            [.sends]
        case .mseg:
            [.sends, .releaseNode, .variableNodes]
        case .xyPad, .xyQuad:
            [.sends, .invertibleAxes]
        case .header:
            // Addresses nothing, so no output section - but it does carry
            // one property of its own.
            [.filled]
        case .label:
            [.align]
        case .monitor:
            [.lines]
        case .random, .sendAll, .panic, .midiPlayer:
            // Addresses nothing either, like the display elements, but
            // pressed rather than held - see ElementTraits.button.
            [.button]
        case .led, .status:
            // Addresses nothing, so no output section and no Random flag,
            // and nothing to press either.
            []
        }
    }
}

/// The bounds and starting points behind the Inspector's steppers and
/// pickers - the numbers that are not a choice from a list.
///
/// The lists themselves are gone from here: they are each enum's own
/// `allCases` now, which is one fewer thing that can disagree with the
/// type it describes.
enum ElementOptions {
    /// Monitor's line count.
    static let linesRange = 1...24
    static let channels = Array(1...16)
    // A cap on the Selected picker rather than a real limit on list length.
    static let selectedRange = 1...32
    /// How many nodes a fresh MSEG starts with. Only the starting point
    /// now - the real count comes from the element's own parameter list.
    static let msegNodeCount = 4
    /// The cap on an MSEG's nodes: past this the nodes sit closer together
    /// than the handles that drag them.
    static let msegMaxNodes = 12
    /// The cap on what Learn Values will collect into one list - the whole
    /// of a 7-bit range, and a place to stop on a 14-bit one, where a knob
    /// swept end to end has 16384 distinct values to offer. See
    /// CanvasElement.captureValue.
    static let valueLearnMaxEntries = 128
}

/// A control's named entries, as the widgets that show them need to see
/// them.
///
/// Note what this is *not* gated on: a radio strip or a combo box uses
/// its entries whatever the Value List switch says - they **are** their
/// entries, so there that switch only decides which table the Inspector
/// shows. Only a knob or a fader treats it as a real property.
enum ValueList {
    /// How many entries the list holds, at least one. A combo box takes
    /// its length from here rather than from a count property: a dropdown
    /// *is* the entries in it, and a count that could disagree with them
    /// would only be one more thing to keep in step. A radio strip does
    /// have a count of its own - there the segment width is a layout
    /// decision that has to hold whether the values are filled in yet or
    /// not.
    static func entryCount(_ values: [ValueEntry]) -> Int {
        max(1, values.count)
    }

    /// `count` names read out of the list.
    ///
    /// Short lists are filled up with position numbers rather than
    /// blanks: an unnamed entry still has to be tellable from its
    /// neighbour, and a number is what it is until someone names it. An
    /// entry whose name is empty gets the same treatment for the same
    /// reason.
    static func entryNames(_ values: [ValueEntry], count: Int) -> [String] {
        (0..<max(0, count)).map { index in
            guard index < values.count, !values[index].name.isEmpty else {
                return "\(index + 1)"
            }
            return values[index].name
        }
    }

    /// The entries in the order the control steps through them.
    ///
    /// Two orders, because a device's numbers are not always its order. A Nord
    /// Lead's wave types run A1 on CC 5, A2 on CC 2, A3 on CC 8 - ascending by
    /// number would step A2, A1, A3 and the instrument's own display would
    /// disagree with the panel driving it. So `sorted` is a property of the
    /// element, not a fact about lists.
    ///
    /// **Stable.** `sorted(by:)` is not, and two entries sharing a number
    /// would otherwise swap places between one call and the next - a control
    /// whose stops move about while nothing changed. Sorting the indices and
    /// breaking ties on them keeps the typed order where the numbers are equal.
    static func ordered(_ values: [ValueEntry], sorted: Bool) -> [ValueEntry] {
        guard sorted else { return values }
        return values.indices
            .sorted { left, right in
                values[left].number == values[right].number
                    ? left < right
                    : values[left].number < values[right].number
            }
            .map { values[$0] }
    }

    /// The entry whose `number` is numerically closest to `value`, read out
    /// the same way `entryNames` falls back to something rather than leave a
    /// blank: an unnamed entry shows its own number. Nil only when the list
    /// itself is empty - the caller decides what to fall back to then.
    static func nearestEntryName(_ values: [ValueEntry], near value: Int) -> String? {
        guard let match = values.min(by: { abs($0.number - value) < abs($1.number - value) }) else {
            return nil
        }
        return match.name.isEmpty ? "\(match.number)" : match.name
    }
}

/// One column of the Inspector's lower table.
///
/// A case rather than the column's heading text. A `[String]` of headings
/// that ParameterTableView switched on to decide what to put in the cell
/// would make the heading and the behaviour the same thing, so renaming a
/// heading would silently empty its column. Here `title` is free to change
/// and nothing follows it.
nonisolated enum ParameterColumn: CaseIterable, Identifiable, Sendable {
    /// What the row is - derived from the element's type, never typed.
    case name
    case cc
    /// NRPN's parameter number, or Program's bank select - which one
    /// follows the output protocol. See ParameterTableView.
    case msb
    case lsb
    case template
    /// What the template parses to. Derived, never edited.
    case parsed
    case value

    var id: Self { self }

    /// The heading. If the column ever gets cramped, "Param" is the
    /// shortening to reach for - a one-word change with nothing depending
    /// on it.
    var title: String {
        switch self {
        case .name: "Parameter"
        case .cc: "CC"
        case .msb: "MSB"
        case .lsb: "LSB"
        case .template: "Template"
        case .parsed: "Parsed"
        case .value: "Value"
        }
    }
}

extension OutputProtocol {
    /// The table's columns under this protocol: the name, then whatever
    /// addresses a parameter here, then the value. SysEx additionally shows
    /// what its template parses to.
    var parameterColumns: [ParameterColumn] {
        switch self {
        case .cc:
            [.name, .cc, .value]
        case .sysEx:
            [.name, .template, .parsed, .value]
        case .nrpnMSBLSB, .nrpnLSBMSB:
            // Both NRPN variants have both fields - they differ in the
            // order their data entry messages go out, not in which
            // fields exist.
            [.name, .msb, .lsb, .value]
        case .program:
            // Bank Select's two halves, not a program number: the program
            // a control selects *is* its value.
            [.name, .msb, .lsb, .value]
        }
    }
}

/// What one element's parameters are: how many rows there are, and what
/// each of them is called.
enum ParameterSchema {
    /// Where a fresh element's addresses start. Not 0: CC 0 is Bank
    /// Select, and an unconfigured control that switched the device's bank
    /// the first time anyone dragged it would be a nasty surprise. 70
    /// upward is the General MIDI sound-controller range, which is where
    /// these parameters live by convention - close enough to right to be a
    /// hint, obviously placeholder enough to be worth checking against the
    /// manual.
    static let firstAddress = 70

    /// What a fresh element's parameters hold, one per row of the table.
    ///
    /// These are the same numbers each widget view would otherwise
    /// hard-code as an illustration. Seeding them here is what turns them
    /// into real data without changing what anything looks like.
    ///
    /// `default` is a real rule here rather than a fallback for the
    /// unlisted: everything not named below is a single-value control, and
    /// one row is what that means.
    static func defaultValues(for type: ElementType) -> [Int] {
        switch type {
        case .adsr:
            [20, 50, 76, 40]
        case .ad:
            [12, 60]
        case .xyPad:
            // Both axes start centred.
            [64, 64]
        case .xyQuad:
            // Off-centre and apart rather than both centred: centred, the
            // two points would start stacked on each other and neither
            // could be told from the other.
            [40, 40, 88, 88]
        case .mseg:
            // Four nodes as a rising ramp, each at half its time - a ramp
            // reads as "nothing set yet" far better than four nodes
            // stacked at one level would.
            //
            // Seven values, not eight: a fresh MSEG is release-shaped, so
            // its last node stores no Level. The device's own release
            // level is what the curve falls to, the same way ADSR's
            // Release stage never stores one.
            [63, 32, 63, 64, 63, 95, 63]
        default:
            // Mid-travel for a single-value control.
            [64]
        }
    }

    /// A fresh element's parameters: one per row, seeded with that row's
    /// default value and consecutive CC numbers from `firstAddress`.
    static func defaultParameters(for type: ElementType) -> [ElementParameter] {
        defaultValues(for: type).enumerated().map { index, value in
            ElementParameter(cc: firstAddress + index, value: value)
        }
    }

    /// What each row is.
    ///
    /// Derived from the type rather than stored: an ADSR's rows are always
    /// attack, decay, sustain and release in that order, and a stored name
    /// could disagree with the shape the curve is drawn from. A control
    /// with one parameter gets one row called "Value" rather than its own
    /// name - the form above already starts with the name, and a column
    /// repeating it would say nothing.
    /// How many nodes a list of parameters describes - two rows per
    /// node, except a release-shaped last node with only a Time row.
    static func nodeCount(parameterCount: Int) -> Int {
        (parameterCount + 1) / 2
    }

    /// `parameters` reshaped to agree with `releaseNode`: on, the last node
    /// keeps only its Time row; off, every node keeps both.
    ///
    /// Idempotent, which is what lets one function cover every moment the
    /// two have to agree - the toggle flipping on an existing element, a
    /// fresh MSEG, and a loaded file squared up with its own flag.
    static func reshapedForRelease(_ parameters: [ElementParameter], releaseNode: Bool) -> [ElementParameter] {
        guard !parameters.isEmpty else { return parameters }
        let isReleaseShaped = parameters.count % 2 == 1
        if releaseNode, !isReleaseShaped {
            return parameters.dropLast()
        }
        if !releaseNode, isReleaseShaped {
            // Addressed after the highest one already in use, and seeded
            // mid-travel.
            let next = (parameters.map(\.cc).max() ?? firstAddress - 1) + 1
            return parameters + [ElementParameter(cc: next, value: CanvasLayout.ccRange.upperBound / 2)]
        }
        return parameters
    }

    static func parameterNames(for type: ElementType, parameterCount: Int) -> [String] {
        switch type {
        case .adsr:
            ["Attack", "Decay", "Sustain", "Release"]
        case .ad:
            ["Attack", "Decay"]
        case .xyPad:
            ["X", "Y"]
        case .xyQuad:
            ["X1", "Y1", "X2", "Y2"]
        case .mseg:
            // Two per node - a time and a level, each addressed
            // separately because a device addresses them separately too -
            // except a release-shaped last node, which has only a Time.
            // Built from the real row count rather than a fixed node
            // count, so adding a node or flipping Release renames
            // nothing by hand.
            (0..<parameterCount).map { row in
                "\(row / 2 + 1) \(row % 2 == 0 ? "Time" : "Level")"
            }
        default:
            ["Value"]
        }
    }
}
