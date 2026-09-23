//
//  CanvasElement.swift
//  PatchWork
//
//  One placed instance of a library type. Geometry is x/y/w/h - top-left
//  origin in the canvas's own coordinate space, not the scroll view's.
//  `name` is user-editable and starts out equal to `type`.
//  Everything after `h` is a property only some types read - which ones is
//  declared in ElementSchema.swift's ElementTraits rather than inferred
//  from a field being non-default. They are stored flat here rather than
//  in a per-type bag: the set is known at compile time, small enough to
//  read at a glance, and a flat struct keeps Codable synthesis free.
//
//  The one exception is `parameters`, which is a list because its length
//  is a per-type fact (a knob has one addressable part, an ADSR four, an
//  MSEG two per node). Anything that is per-*parameter* rather than
//  per-element lives in there - the addresses and the values - while the
//  protocol, channel and resolution stay out here, because one envelope
//  speaks one protocol on one channel.
//

import Foundation
import CoreGraphics

struct CanvasElement: Identifiable, Codable {
    // var, not let: a `let` with a default UUID() initializer is legal but
    // Codable synthesis then silently skips decoding it (Swift warns "will
    // not be decoded"), so every load would mint fresh random ids instead
    // of restoring the saved ones.
    var id = UUID()
    let type: ElementType
    var name: String
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    /// One per addressable part - always at least one, so the table and
    /// the widgets read a uniform array with no per-type branch. See
    /// ParameterSchema.parameterNames for what each entry is called.
    var parameters: [ElementParameter]
    /// The named entries this control can carry, shown in the lower table
    /// instead of the parameters while `useValues` is on. Empty on a fresh
    /// element - the list is the first thing to fill in, not something to
    /// prefill with guesses.
    var values: [ValueEntry]
    var segmentCount: Int
    var bipolar: Bool
    var checked: Bool
    /// MSEG only: whether its last node is a release node, storing no
    /// Level of its own and falling to the device's own release level -
    /// the same way ADSR's Release stage never stores one.
    ///
    /// Spelled out rather than called `release`, because an ADSR's fourth
    /// *parameter row* is also called "Release", and `element.release`
    /// next to that would read as the stage.
    var releaseNode: Bool
    /// Header only: a filled bar starts a section, a bare one separates
    /// within it. One element with a checkbox saying which, rather than two
    /// library types that differ only in how they are drawn.
    var filled: Bool
    /// Label only: how its text sits in its own box. A label is a caption
    /// beside something and takes the alignment its own property asks for,
    /// where a heading spans its section and is always centred.
    var align: LabelAlignment
    /// Monitor only: how many message lines it asks for. What it actually
    /// shows is this or however many fit, whichever is fewer - see
    /// MonitorView.
    var lines: Int
    var selected: Int
    var output: OutputProtocol
    var resolution: Resolution
    var channel: Int
    /// Which checksum a SysEx template's brackets close with, and how VAL
    /// expands on the wire. Both belong to the *element*, like the protocol and
    /// the channel: one control speaks one dialect, whatever its parameters
    /// address.
    var checksum: ChecksumMode
    var valueFormat: ValueFormat
    var useValues: Bool
    /// Whether the value list runs in ascending numeric order, or exactly as
    /// it was typed. See `sortsValues`, which is what everything reads.
    ///
    /// **Optional on purpose, and not a `Bool` with a default.** This struct
    /// uses synthesized `Codable`, whose decoder calls `decode` rather than
    /// `decodeIfPresent` for a non-optional property - a default value does
    /// not enter into it. A plain `Bool` here would therefore throw
    /// `keyNotFound` on every .pwork file written before this property
    /// existed, the shipped Presets included. Optional storage behind a
    /// non-optional accessor is the same arrangement parameterMin/rangeMin
    /// already use, for a smaller reason.
    var sortValues: Bool?
    var random: Bool
    /// A custom lower/upper bound narrower than the resolution's own 0...
    /// ceiling - Knob and Slider only (see ElementTraits.customRange). Nil
    /// on every other type and on a fresh Knob/Slider, so an old .pwork
    /// file with neither key still decodes and keeps the full range it
    /// always had.
    var parameterMin: Int?
    var parameterMax: Int?

    var rect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    /// The largest value this element's parameters may reach, from its own
    /// resolution - 127 at 7 bits, 16383 at 14. Per element rather than
    /// global: one panel can hold a 7-bit CC knob next to a 14-bit NRPN
    /// fader, and each bounds its own fields, its own drawing and its own
    /// readout.
    var valueCeiling: Int { resolution.ceiling }

    /// What this element's type carries - which Inspector sections it gets,
    /// whether it sends, whether it can be rolled. See ElementTraits.
    var traits: ElementTraits { type.traits }

    /// The same as a range, for clamping - 0...valueCeiling unless
    /// parameterMin/parameterMax narrow it (Knob/Slider only). Ordered
    /// defensively rather than trusted, the same tolerance parameterValue
    /// gives a short parameter list: a hand-edited .pwork file is outside
    /// this type's control, and a backwards min/max would otherwise crash
    /// every place that reads this range instead of just reading oddly.
    var valueRange: ClosedRange<Int> {
        let lower = parameterMin ?? 0
        let upper = parameterMax ?? valueCeiling
        return lower <= upper ? lower...upper : upper...lower
    }

    /// Real, non-optional numbers behind parameterMin/parameterMax - what
    /// the Inspector's Min/Max fields actually bind to (via a plain
    /// WritableKeyPath, same as segmentCount or channel), rather than the
    /// stored optionals themselves. Each setter clamps into 0...valueCeiling
    /// and against its sibling, then re-clamps this element's own parameter
    /// values into the resulting range - a knob already past a newly
    /// narrowed Max should stop sending its old value immediately, not just
    /// look clamped.
    var rangeMin: Int {
        get { parameterMin ?? 0 }
        set {
            let upperBound = parameterMax ?? valueCeiling
            parameterMin = min(max(newValue, 0), upperBound)
            clampParameterValues()
        }
    }

    var rangeMax: Int {
        get { parameterMax ?? valueCeiling }
        set {
            let lowerBound = parameterMin ?? 0
            parameterMax = min(max(newValue, lowerBound), valueCeiling)
            clampParameterValues()
        }
    }

    private mutating func clampParameterValues() {
        // A value list defines the legal values outright, so Min/Max have
        // nothing to say about them - see valueListActive. Without this,
        // typing in the Min field would drag a perfectly good entry value off
        // its entry, and nothing on screen would explain why.
        guard !valueListActive else { return }
        let range = valueRange
        for row in parameters.indices {
            parameters[row].value = min(max(parameters[row].value, range.lowerBound), range.upperBound)
        }
    }

    /// The parameters' values in row order - what the widgets draw from.
    var parameterValues: [Int] { parameters.map(\.value) }

    /// One parameter's value, tolerating a list shorter than the type
    /// expects. Nothing in the app produces that today, but a saved file
    /// is outside this type's control, and a curve drawn from four rows
    /// should not be able to crash on a file that only has three.
    func parameterValue(_ index: Int, fallback: Int = 0) -> Int {
        index < parameters.count ? parameters[index].value : fallback
    }

    /// Whether the value list actually governs this control.
    ///
    /// Three things at once, and all three matter: the type has to be one that
    /// carries a list, the switch has to be on, and the list has to have
    /// something in it. An empty list in force would mean a control with no
    /// positions at all.
    var valueListActive: Bool {
        traits.contains(.valueList) && useValues && !values.isEmpty
    }

    /// Ascending by number, or exactly as typed - see ValueList.ordered.
    var sortsValues: Bool {
        get { sortValues ?? true }
        set { sortValues = newValue }
    }

    /// The entries in the order this control steps through them.
    var orderedValues: [ValueEntry] { ValueList.ordered(values, sorted: sortsValues) }

    /// Which stop the control is on.
    ///
    /// By exact number first, and only then by nearest. The fallback is not
    /// decoration: a hand-edited file, or a resolution narrowed under a value
    /// that was legal at 14 bits, leaves a value sitting on no entry at all,
    /// and a control has to be somewhere.
    var valueIndex: Int {
        let entries = orderedValues
        guard !entries.isEmpty else { return 0 }
        let value = parameterValue(0)
        if let exact = entries.firstIndex(where: { $0.number == value }) { return exact }
        return entries.indices.min {
            abs(entries[$0].number - value) < abs(entries[$1].number - value)
        } ?? 0
    }

    /// Where the control sits on its travel, 0...1.
    ///
    /// With a list in force this counts *stops*, not numbers. A wave selector
    /// on CC 0, 1, 2 and 3 is four positions spread across the whole travel,
    /// where reading its numbers against a 0...127 domain would bunch all four
    /// into the first three percent of it and make the control unusable. It is
    /// also what lets an unsorted list run forwards: with A1 on 5, A2 on 2 and
    /// A3 on 8, a value-derived angle would jump backwards between the first
    /// two.
    var displayFraction: CGFloat {
        guard valueListActive else {
            let range = valueRange
            return valueFraction(parameterValue(0),
                                 floor: range.lowerBound, ceiling: range.upperBound)
        }
        let steps = orderedValues.count - 1
        guard steps > 0 else { return 0 }
        return CGFloat(valueIndex) / CGFloat(steps)
    }

    /// What the control prints in the middle of itself: the entry's name while
    /// a list is in force, or nil to go on showing the number.
    ///
    /// An unnamed entry reads out as its own number, the same fallback
    /// `ValueList.entryNames` makes - a blank stop would look like a fault.
    var valueCaption: String? {
        guard valueListActive else { return nil }
        let entries = orderedValues
        guard entries.indices.contains(valueIndex) else { return nil }
        let entry = entries[valueIndex]
        return entry.name.isEmpty ? "\(entry.number)" : entry.name
    }

    /// How many nodes this element's parameters describe - MSEG only.
    var nodeCount: Int { ParameterSchema.nodeCount(parameterCount: parameters.count) }

    /// The axis-inversion flags in row order - only the pads read these.
    var invertedAxes: [Bool] { parameters.map(\.inverted) }

    /// Whether one axis is inverted, tolerating a short list for the same
    /// reason parameterValue does.
    func isAxisInverted(_ index: Int) -> Bool {
        index < parameters.count && parameters[index].inverted
    }

    init(type: ElementType, rect: CGRect) {
        self.type = type
        self.name = type.title
        self.x = rect.origin.x.rounded()
        self.y = rect.origin.y.rounded()
        self.w = rect.width.rounded()
        self.h = rect.height.rounded()
        self.parameters = ParameterSchema.defaultParameters(for: type)
        self.values = []
        self.segmentCount = 4
        self.bipolar = false
        self.checked = false
        // Default on: a fresh envelope should look like the shape most
        // devices actually have, an ADSR-style release, not a fixed level
        // nobody asked for.
        self.releaseNode = true
        // A heading is filled unless it is asked to be a separator.
        self.filled = true
        self.align = .left
        // One line is a perfectly good monitor - it shows the newest
        // message, which is usually the question - but six is a useful
        // window on a burst.
        self.lines = 6
        self.selected = 1
        self.output = .cc
        self.resolution = .sevenBit
        self.channel = 1
        self.checksum = .roland
        self.valueFormat = .oneByte
        // Type-dependent: on for the types that *are* their entries, so a
        // fresh strip or dropdown opens on its list - the first thing to
        // fill in - while a knob opens on its address, the only thing it has.
        self.useValues = type == .radio || type == .combobox
        // Ascending is the ordinary case; a device whose numbers run out of
        // order is the exception someone switches this off for.
        self.sortValues = true
        self.random = false
        self.parameterMin = nil
        self.parameterMax = nil
    }

    /// Commits a new rect, snapping to whole pixels - drag/resize gestures
    /// produce sub-pixel floats, but this model always stores whole
    /// numbers, so Inspector's number fields never show something like
    /// 105.015625. The one place geometry
    /// is written after construction (EditorCanvasView's onCommitRect)
    /// goes through this rather than assigning x/y/w/h directly.
    mutating func setRect(_ rect: CGRect) {
        x = rect.origin.x.rounded()
        y = rect.origin.y.rounded()
        w = rect.width.rounded()
        h = rect.height.rounded()
    }

    /// A copy with a fresh id, offset diagonally so it doesn't land exactly
    /// on top of the original. Keeps the (possibly user-edited) name and cc
    /// as-is rather than resetting them, unlike a fresh library placement.
    ///
    /// `self` copied wholesale, then the four things that must *not* be
    /// shared put right. Assigning all seventeen properties onto a fresh
    /// element one at a time would make every new property a line somebody
    /// has to remember to add here, silently taking the constructor's
    /// default in the duplicate until they do. A struct is already a copy;
    /// only identity needs deciding.
    func duplicated(offset: CGFloat = 20) -> CanvasElement {
        var copy = self
        copy.id = UUID()
        copy.setRect(rect.offsetBy(dx: offset, dy: offset))
        // Fresh ids on the rows too: the arrays are value types so the data
        // is already copied, but two elements sharing row identities would
        // be a trap waiting for whatever reads them next.
        copy.parameters = parameters.map { parameter in
            var fresh = parameter
            fresh.id = UUID()
            return fresh
        }
        copy.values = values.map { entry in
            var fresh = entry
            fresh.id = UUID()
            return fresh
        }
        return copy
    }
}

/// Shared canvas geometry constants - needed by both EditorCanvasView
/// (which draws the canvas and floors resizing) and ContentView (which
/// picks where a newly library-placed element lands), so they live here
/// rather than duplicated or buried private in one view file.
enum CanvasLayout {
    static let size = CGSize(width: 960, height: 600)
    static let defaultElementSize: CGFloat = 80
    static let minimumElementSize: CGFloat = 40

    /// The snap step, and the spacing of the dot grid - one number, because
    /// a grid you can see and a grid things land on had better be the same
    /// grid.
    ///
    /// Fixed rather than scaled with the window: the grid is what element
    /// positions are expressed in, so a spacing that changed with the window
    /// size would silently re-space a layout every time it was resized. The
    /// page follows the window; its ruling does not.
    static let grid: CGFloat = 8

    /// `value` rounded to the nearest grid line.
    ///
    /// Used by the gestures - a drag, a resize, a placement - and
    /// deliberately **not** by the Inspector's number fields. Snapping is a
    /// help while dragging and an obstruction while typing: a coordinate
    /// typed into a field is exact by definition, and having 341 jump to 344
    /// mid-keystroke would fight the user for the field.
    static func snapped(_ value: CGFloat) -> CGFloat {
        (value / grid).rounded() * grid
    }
    static let ccRange = 0...127
    static let segmentCountRange = 1...8
    // A separate constant from ccRange even though currently identical:
    // this bounds the value itself (which grows to 0...16383 once 14-bit
    // resolution exists), ccRange bounds which CC *number* addresses it
    // (always 7-bit, even in 14-bit value mode) - the two would diverge the
    // moment either changes independently of the other.
    static let valueRange = 0...127

    /// A fresh placement's starting size. Most types are a square; a type
    /// whose shape reads better wide or tall gets its own default here
    /// rather than starting squeezed into a square and needing an
    /// immediate manual resize.
    static func defaultSize(for type: ElementType) -> CGSize {
        switch type {
        case .adsr:
            CGSize(width: 160, height: 100)
        case .slider:
            CGSize(width: 56, height: 160)
        case .radio:
            CGSize(width: 240, height: 56)
        case .combobox:
            CGSize(width: 160, height: 56)
        case .checkbox:
            CGSize(width: 120, height: 32)
        case .xyPad:
            CGSize(width: 160, height: 176)
        case .xyQuad:
            CGSize(width: 200, height: 220)
        case .mseg:
            CGSize(width: 280, height: 120)
        case .ad:
            CGSize(width: 208, height: 120)
        case .led:
            CGSize(width: 64, height: 40)
        case .status:
            CGSize(width: 368, height: 152)
        case .monitor:
            CGSize(width: 320, height: 104)
        case .header:
            CGSize(width: 200, height: 28)
        case .label:
            CGSize(width: 120, height: 24)
        case .random, .sendAll, .panic:
            CGSize(width: 112, height: 40)
        case .midiPlayer:
            CGSize(width: 200, height: 96)
        case .knob:
            CGSize(width: defaultElementSize, height: defaultElementSize)
        }
    }
}
