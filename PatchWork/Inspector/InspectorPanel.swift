//
//  InspectorPanel.swift
//  PatchWork
//
//  Right sidebar for editing the selected element's properties. Section
//  order:
//
//      Name
//      Geometry        X, Y / W, H
//      <type-specific> Bipolar, Checked, Segments, Selected
//      Output          Output / Resolution / Channel
//                      + Checksum / Value Format, on SysEx only
//      <switches>      Value List + Sort + Learn, Random
//      <pad-specific>  Invert per axis - X/Y, or X1/Y1/X2/Y2 on a quad
//      the lower table  Parameters, or Values while Value List is on
//
//  What you configure once and stop looking at (the output block) sits
//  below what you reach for while laying a panel out; the two general
//  switches sit under that, and the pad's axis inversions last because
//  one type has them.
//
//  Which sections a type shows is ElementSchema.swift's ElementTraits,
//  not a string test per section - see that file for where the per-type
//  answers come from.
//

import SwiftUI

struct InspectorPanel: View {
    @Binding var elements: [CanvasElement]
    var selection: Set<CanvasElement.ID>
    /// Which element is collecting arriving values into its Value List, if
    /// any. Owned by ContentView, which is where the messages arrive - see
    /// captureValues(from:) there, and ElementValueLearn.swift for what one
    /// of them does when it lands.
    @Binding var valueLearnID: CanvasElement.ID?
    /// Whether a MIDI Input is chosen at all. Learn reads that device and only
    /// that device - see Learn.accepts - so with none there is nothing for the
    /// checkbox to listen to, and it says so rather than sitting lit over a
    /// silent port.
    var hasInput: Bool = false
    /// Dragged by the divider beside it - see PanelDivider.
    var width: CGFloat = 300

    /// The window's own, for the one edit in this panel that is undoable -
    /// see clearValues(_:).
    @Environment(\.undoManager) private var undoManager

    /// The one selected element's index, or nil.
    ///
    /// Nil for *several* as well as for none - the two still show
    /// differently below, but several now gets `multiForm` rather than the
    /// empty state: a property shows there only when every selected element
    /// has it, and mixed (see MultiField) where they disagree, the same
    /// idea a native Inspector applies to a multi-selection.
    private var selectedIndex: Int? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return elements.firstIndex { $0.id == id }
    }

    /// Every selected element's index, in `elements`' own order - what
    /// `multiForm` edits when more than one is picked.
    private var selectedIndices: [Int] {
        elements.indices.filter { selection.contains(elements[$0].id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if let index = selectedIndex {
                // Scrolls because the sections now outgrow the panel on a
                // type that has most of them, at any realistic window
                // height.
                ScrollView {
                    form(index)
                        .padding(12)
                }
            } else if !selectedIndices.isEmpty {
                ScrollView {
                    multiForm(selectedIndices)
                        .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
            }
        }
        // Set from outside now, and draggable: SysEx asks for four columns,
        // and Template/Parsed are the two widest things in the panel - 300 is
        // where it starts, not where it has to stay.
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func form(_ index: Int) -> some View {
        let traits = elements[index].traits

        VStack(alignment: .leading, spacing: 14) {
            section("Name") {
                TextField("Name", text: $elements[index].name)
                    .textFieldStyle(.roundedBorder)
                Text("Type: \(elements[index].type.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            section("Geometry") {
                HStack(spacing: 8) {
                    numberField("X", value: xBinding(index))
                    numberField("Y", value: yBinding(index))
                }
                HStack(spacing: 8) {
                    numberField("W", value: wBinding(index))
                    numberField("H", value: hBinding(index))
                }
            }

            if traits.contains(.bipolar) {
                Divider()
                Toggle("Bipolar", isOn: $elements[index].bipolar)
                    .font(.caption)
            }

            if traits.contains(.checked) {
                Divider()
                Toggle("Checked", isOn: $elements[index].checked)
                    .font(.caption)
            }

            if traits.contains(.filled) {
                Divider()
                Toggle("Filled", isOn: $elements[index].filled)
                    .font(.caption)
            }

            if traits.contains(.lines) {
                Divider()
                section("Lines") {
                    numberField("N", value: linesBinding(index))
                }
            }

            if traits.contains(.align) {
                Divider()
                section("Align") {
                    choiceField("Al", selection: $elements[index].align)
                }
            }

            if traits.contains(.releaseNode) {
                Divider()
                // Reshapes the rows as it flips, so the flag and the row
                // list can never disagree.
                Toggle("Release", isOn: Binding(
                    get: { elements[index].releaseNode },
                    set: { releaseNode in
                        elements[index].releaseNode = releaseNode
                        elements[index].parameters = ParameterSchema.reshapedForRelease(
                            elements[index].parameters, releaseNode: releaseNode
                        )
                    }
                ))
                .font(.caption)
            }

            if traits.contains(.segments) {
                Divider()
                section("Segments") {
                    numberField("N", value: segmentCountBinding(index))
                }
            }

            if traits.contains(.selected) {
                Divider()
                section("Selected") {
                    numberField("S", value: selectedBinding(index))
                }
            }

            if traits.contains(.sends) {
                Divider()
                // No CC row here: an address belongs to a parameter, not
                // to the element, so it is a column of the table below -
                // an ADSR has four of them and a single form field could
                // only ever edit one.
                section("Output") {
                    outputField("Channel", selection: $elements[index].channel, options: ElementOptions.channels)
                    outputField("Type", selection: $elements[index].output)
                    outputField("Resolution", selection: $elements[index].resolution)
                    // Only for SysEx, and only because only SysEx has them:
                    // the checksum's arithmetic and how VAL expands are the two
                    // things a template cannot say for itself. Gated on the
                    // output's *value* rather than on a per-type trait - every
                    // type that sends can be a SysEx element.
                    if elements[index].output == .sysEx {
                        outputField("Checksum", selection: $elements[index].checksum)
                        outputField("Value Format", selection: $elements[index].valueFormat)
                    }
                }
            }

            if traits.contains(.customRange) {
                Divider()
                // Greyed out under a value list: the list defines the legal
                // values outright, and Min/Max then have nothing left to
                // narrow - see CanvasElement.valueListActive. Shown rather
                // than hidden, so switching the list off brings back fields
                // that were already there instead of new ones.
                section("Range") {
                    numberField("Min", value: $elements[index].rangeMin)
                    numberField("Max", value: $elements[index].rangeMax)
                }
                .disabled(elements[index].valueListActive)
                .help(elements[index].valueListActive
                      ? "The Value List defines the values; Min and Max do not apply"
                      : "The control's own travel")
            }

            if traits.contains(.valueList) || traits.contains(.sends) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if traits.contains(.valueList) {
                        // Learn Values sits beside the switch it depends on
                        // rather than above the table it fills: it is the
                        // second half of "this control has named entries",
                        // and it is meaningless without the first.
                        HStack(spacing: 12) {
                            Toggle("Value List", isOn: $elements[index].useValues)
                            // Order, not whether: ascending by number, or
                            // exactly as typed. A device whose numbers run out
                            // of order is what this exists for.
                            Toggle("Sort", isOn: $elements[index].sortsValues)
                                .disabled(!elements[index].useValues)
                                .help(elements[index].useValues
                                      ? "Off: step the entries in the order they are listed, whatever their numbers"
                                      : "Switch Value List on first")
                            // Just "Learn" beside the switch it belongs to.
                            // The toolbar's Learn is the other one, and the
                            // two are told apart by where they are rather
                            // than by a longer label on one of them.
                            Toggle("Learn", isOn: learnValuesBinding(index))
                                .disabled(!elements[index].canLearnValues || !hasInput)
                                .help(learnValuesHelp(index))
                        }
                    }
                    if traits.contains(.sends) {
                        Toggle("Random", isOn: $elements[index].random)
                    }
                }
                .font(.caption)
                // An arm on a list that no longer exists would go on
                // swallowing every message that arrived, invisibly.
                .onChange(of: elements[index].canLearnValues) { _, possible in
                    if !possible, valueLearnID == elements[index].id { valueLearnID = nil }
                }
            }

            if traits.contains(.invertibleAxes) {
                Divider()
                // One toggle per axis, labelled from the row's own name -
                // which gives "Invert X"/"Invert Y" on a plain pad and
                // "Invert X1"…"Invert Y2" on a quad, without this having to
                // know that either pad exists.
                VStack(alignment: .leading, spacing: 6) {
                    let names = ParameterSchema.parameterNames(
                        for: elements[index].type,
                        parameterCount: elements[index].parameters.count
                    )
                    ForEach(Array(elements[index].parameters.enumerated()), id: \.element.id) { axis, _ in
                        Toggle(
                            "Invert \(axis < names.count ? names[axis] : "\(axis + 1)")",
                            isOn: $elements[index].parameters[axis].inverted
                        )
                    }
                }
                .font(.caption)
            }

            // The lower half, and the one place it can show two different
            // things: a control's named entries while Value List is on,
            // its addressable parameters otherwise. Only for types that
            // send - a Header or a Monitor addresses nothing, so a table
            // of addresses would be a form with nowhere to go.
            if traits.contains(.sends) {
                Divider()
                if traits.contains(.valueList) && elements[index].useValues {
                    section("Values") {
                        ValueTableView(element: $elements[index],
                                       onClearAll: { clearValues(index) })
                    }
                } else {
                    section("Parameters") {
                        ParameterTableView(element: $elements[index])
                    }
                }
            }
        }
    }

    /// The multi-selection form: everything `form(_:)` shows except
    /// Geometry and the lower Parameters/Values table, which stay
    /// single-selection only - a rect that means something for several
    /// elements at once would be "align" or "pack", commands this app does
    /// not have, and the table's rows have no natural correspondence across
    /// elements whose parameter counts differ (1 for a Knob, up to two
    /// dozen for an MSEG). Sections gate on the *intersection* of every
    /// selected element's own traits, so a Knob and a Label selected
    /// together show only what both actually have (Name), the same way a
    /// native Inspector handles a mixed-type selection.
    @ViewBuilder
    private func multiForm(_ indices: [Int]) -> some View {
        // Only what every one of them carries. `intersection` outright,
        // rather than the hand-written fifteen-line `intersected(with:)`
        // this used to call - a new trait joins the set and this keeps
        // working, where before it had to be remembered into that function
        // or would silently survive a mixed selection it had no business in.
        let traits = indices.dropFirst().reduce(elements[indices[0]].traits) {
            $0.intersection(elements[$1].traits)
        }
        // Value-gated like form(_:)'s own Checksum/Value Format rows, just
        // extended to "every one of them" rather than one element's output.
        let allSysEx = indices.allSatisfy { elements[$0].output == .sysEx }

        let name = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.name)
        let bipolar = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.bipolar)
        let checked = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.checked)
        let filled = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.filled)
        let lines = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.lines)
        let align = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.align)
        let segmentCount = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.segmentCount)
        let selected = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.selected)
        let channel = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.channel)
        let output = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.output)
        let resolution = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.resolution)
        let checksum = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.checksum)
        let valueFormat = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.valueFormat)
        let useValues = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.useValues)
        // Via sortsValues, not the optional storage behind it: a tri-state
        // over Bool? would show "mixed" for every element saved before the
        // property existed, which is not what those files disagree about.
        let sortValues = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.sortsValues)
        let random = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.random)
        let rangeMin = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.rangeMin)
        let rangeMax = MultiField(elements: $elements, indices: indices, keyPath: \CanvasElement.rangeMax)

        VStack(alignment: .leading, spacing: 14) {
            section("Name") {
                mixedTextField(name)
                Text("\(indices.count) elements selected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if traits.contains(.bipolar) {
                Divider()
                MixedToggle(title: "Bipolar", value: bipolar.value, onToggle: bipolar.set)
            }

            if traits.contains(.checked) {
                Divider()
                MixedToggle(title: "Checked", value: checked.value, onToggle: checked.set)
            }

            if traits.contains(.filled) {
                Divider()
                MixedToggle(title: "Filled", value: filled.value, onToggle: filled.set)
            }

            if traits.contains(.lines) {
                Divider()
                section("Lines") { mixedIntField("N", field: lines, range: ElementOptions.linesRange) }
            }

            if traits.contains(.align) {
                Divider()
                section("Align") { mixedChoiceField("Al", field: align) }
            }

            if traits.contains(.segments) {
                Divider()
                section("Segments") { mixedIntField("N", field: segmentCount, range: CanvasLayout.segmentCountRange) }
            }

            if traits.contains(.selected) {
                Divider()
                section("Selected") { mixedIntField("S", field: selected, range: ElementOptions.selectedRange) }
            }

            if traits.contains(.sends) {
                Divider()
                section("Output") {
                    mixedOutputField("Channel", field: channel, options: ElementOptions.channels)
                    mixedOutputField("Type", field: output)
                    mixedOutputField("Resolution", field: resolution)
                    if allSysEx {
                        mixedOutputField("Checksum", field: checksum, )
                        mixedOutputField("Value Format", field: valueFormat, )
                    }
                }
            }

            if traits.contains(.customRange) {
                Divider()
                // The widest possible bound, not each element's own ceiling:
                // a mixed 7-bit/14-bit selection's per-element rangeMin/
                // rangeMax setter does the real, element-specific clamping -
                // this is only the outer sanity check on what gets typed.
                section("Range") {
                    mixedIntField("Min", field: rangeMin, range: 0...Resolution.fourteenBit.ceiling)
                    mixedIntField("Max", field: rangeMax, range: 0...Resolution.fourteenBit.ceiling)
                }
            }

            if traits.contains(.valueList) || traits.contains(.sends) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if traits.contains(.valueList) {
                        MixedToggle(title: "Value List", value: useValues.value, onToggle: useValues.set)
                        MixedToggle(title: "Sort", value: sortValues.value, onToggle: sortValues.set)
                    }
                    if traits.contains(.sends) {
                        MixedToggle(title: "Random", value: random.value, onToggle: random.set)
                    }
                }
            }
        }
    }

    private func mixedTextField(_ field: MultiField<String>) -> some View {
        TextField("Multiple", text: Binding(get: { field.value ?? "" }, set: { field.set($0) }))
            .textFieldStyle(.roundedBorder)
    }

    private func mixedIntField(_ label: String, field: MultiField<Int>, range: ClosedRange<Int>) -> some View {
        labeledField(label) {
            TextField("Multiple", text: Binding(
                get: { field.value.map(String.init) ?? "" },
                set: { text in
                    guard let parsed = Int(text) else { return }
                    field.set(range.clamp(parsed))
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func mixedChoiceField<Option: InspectorChoice>(
        _ label: String, field: MultiField<Option>
    ) -> some View {
        labeledField(label) {
            Picker(label, selection: field.binding) {
                if field.value == nil {
                    Text("Multiple").tag(Optional<Option>.none)
                }
                ForEach(Option.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
            }
            .labelsHidden()
            .font(.caption)
        }
    }

    /// The Output section's own mixed row shape - see `outputField` for why
    /// the label is wider and the picker pushed to the trailing edge.
    private func mixedOutputField<Option: Hashable & CustomStringConvertible>(
        _ label: String, field: MultiField<Option>, options: [Option]
    ) -> some View {
        mixedOutputRow(label, field: field) {
            ForEach(options, id: \.self) { option in
                Text(option.description).tag(Optional(option))
            }
        }
    }

    /// The same row for a choice that knows its own options.
    private func mixedOutputField<Option: InspectorChoice>(
        _ label: String, field: MultiField<Option>
    ) -> some View {
        mixedOutputRow(label, field: field) {
            ForEach(Option.allCases) { option in
                Text(option.title).tag(Optional(option))
            }
        }
    }

    private func mixedOutputRow<Option: Hashable, Entries: View>(
        _ label: String, field: MultiField<Option>, @ViewBuilder entries: () -> Entries
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer(minLength: 8)
            Picker(label, selection: field.binding) {
                if field.value == nil {
                    Text("Multiple").tag(Optional<Option>.none)
                }
                entries()
            }
            .labelsHidden()
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // ── Learn Values ─────────────────────────────────────────────────────

    /// The Learn Values checkbox, over state that lives a level up.
    ///
    /// A derived binding rather than a property on the element: which
    /// element is armed is a state of the session, not of the design, and
    /// storing it would save it into the .pwork file and reopen armed.
    private func learnValuesBinding(_ index: Int) -> Binding<Bool> {
        let id = elements[index].id
        return Binding(
            get: { valueLearnID == id },
            set: { valueLearnID = $0 ? id : nil }
        )
    }

    /// Why the checkbox is greyed out, or what it does when it is not.
    /// The same three conditions `matches` imposes, said in words - see
    /// CanvasElement.canLearnValues.
    private func learnValuesHelp(_ index: Int) -> String {
        let element = elements[index]
        if !element.useValues { return "Switch Value List on first" }
        if !hasInput { return "Choose a MIDI Input first - Learn listens to that device" }
        if element.output == .sysEx {
            return "SysEx cannot be matched against arriving bytes yet"
        }
        if element.parameters.count != 1 {
            return "Only a control with a single parameter is addressed as a whole"
        }
        return "Move this control on the device to collect the values it takes"
    }

    /// Empties the selected element's Value List, undoably.
    ///
    /// The one Inspector edit that registers with Undo, and it earns it by
    /// being the one that is neither a keystroke nor reversible by typing
    /// the old thing back - see CanvasUndo, which explains why the rest of
    /// this panel deliberately does not. Capturing does not register
    /// either: a turning knob would file one Undo step per entry.
    private func clearValues(_ index: Int) {
        guard elements.indices.contains(index), !elements[index].values.isEmpty else { return }
        let previous = elements
        elements[index].values.removeAll()
        CanvasUndo.register(undoManager, binding: $elements, previous: previous,
                            actionName: "Clear Value List")
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // .number resolves to FloatingPointFormatStyle<Double>, not <CGFloat> -
    // Swift treats the two as distinct types for this generic even though
    // they're bit-identical on 64-bit, so this bridges through Double.
    // .precision(.fractionLength(0)) keeps the display an integer even if a
    // stray sub-pixel value ever slips through (drag/resize commits round
    // already - see EditorCanvasView - but this is the display's own
    // guarantee, not a hope that upstream rounding was applied).
    private func numberField(_ label: String, value: Binding<CGFloat>) -> some View {
        let doubleValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0.rounded()) }
        )
        return labeledField(label) {
            TextField(label, value: doubleValue, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        labeledField(label) {
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func choiceField<Option: Hashable & CustomStringConvertible>(
        _ label: String, selection: Binding<Option>, options: [Option]
    ) -> some View {
        labeledField(label) {
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .labelsHidden()
            .font(.caption)
        }
    }

    /// The same row for a choice that knows its own options - which is every
    /// one of them except Channel, whose options are the numbers 1...16.
    /// Nothing to pass, so nothing to pass wrongly.
    private func choiceField<Option: InspectorChoice>(
        _ label: String, selection: Binding<Option>
    ) -> some View {
        labeledField(label) {
            Picker(label, selection: selection) {
                ForEach(Option.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .font(.caption)
        }
    }

    /// The Output section's own row shape: a wider, spelled-out label (this
    /// is the one section dense enough with abbreviations - Out/Res/Ch/Sum/Fmt
    /// - that they stopped being readable), and the picker pushed to the
    /// row's trailing edge rather than hugging the label. Each picker still
    /// sizes to its own selected text - "Channel" reads "3" where "Type"
    /// reads "NRPN (MSB/LSB)" - a fixed width was tried and dropped: a
    /// menu-style Picker sizes itself to the selected option regardless of
    /// the frame it's offered, so forcing one just clipped the wider rows
    /// instead of evening them out.
    private func outputField<Option: Hashable & CustomStringConvertible>(
        _ label: String, selection: Binding<Option>, options: [Option]
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer(minLength: 8)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .labelsHidden()
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    /// The Output section's row for a choice that knows its own options.
    private func outputField<Option: InspectorChoice>(
        _ label: String, selection: Binding<Option>
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer(minLength: 8)
            Picker(label, selection: selection) {
                ForEach(Option.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledField<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            field()
        }
    }

    // Geometry - x/y floored at 0 (an element can't sit off the canvas's
    // top/left edge), w/h floored at the same minimum resize enforces, so
    // typing a value here can't produce a state dragging couldn't. Not
    // upper-bounded against the live canvas size - Inspector has no path
    // to EditorCanvasView's GeometryReader-derived size, but PlacedElementRow
    // re-clamps against it on every render anyway, so an over-large value
    // just displays clamped until the next drag/resize commits a sane one.
    private func xBinding(_ index: Int) -> Binding<CGFloat> {
        Binding(get: { elements[index].x }, set: { elements[index].x = max(0, $0) })
    }

    private func yBinding(_ index: Int) -> Binding<CGFloat> {
        Binding(get: { elements[index].y }, set: { elements[index].y = max(0, $0) })
    }

    private func wBinding(_ index: Int) -> Binding<CGFloat> {
        Binding(
            get: { elements[index].w },
            set: { elements[index].w = max(CanvasLayout.minimumElementSize, $0) }
        )
    }

    private func hBinding(_ index: Int) -> Binding<CGFloat> {
        Binding(
            get: { elements[index].h },
            set: { elements[index].h = max(CanvasLayout.minimumElementSize, $0) }
        )
    }

    private func segmentCountBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { elements[index].segmentCount },
            set: { elements[index].segmentCount = CanvasLayout.segmentCountRange.clamp($0) }
        )
    }

    private func linesBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { elements[index].lines },
            set: { elements[index].lines = ElementOptions.linesRange.clamp($0) }
        )
    }

    private func selectedBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { elements[index].selected },
            set: { elements[index].selected = ElementOptions.selectedRange.clamp($0) }
        )
    }

}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

#Preview {
    InspectorPanel(elements: .constant([]), selection: [], valueLearnID: .constant(nil),
                   hasInput: true)
}
