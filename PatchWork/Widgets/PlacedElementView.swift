//
//  PlacedElementView.swift
//  PatchWork
//
//  Dispatches to a per-type on-canvas look. Every ElementType has one now,
//  and the switch below is exhaustive rather than ending in a fallback -
//  which means a newly added type does not compile until it has been given
//  a view, instead of silently drawing as a dashed box. Random/Send All/
//  Panic share one, being visually identical.
//
//  Takes the whole element rather than a growing list of flat parameters
//  (name, type, segmentCount, ...): as more per-type properties land (see
//  CanvasElement.segmentCount, the first one), each dispatch case reads
//  whatever it needs straight off `element` instead of this view's own
//  signature having to grow with every new property some single type
//  happens to want.
//

import SwiftUI

struct PlacedElementView: View {
    let element: CanvasElement
    /// The live MIDI side - what LED, Status and Monitor display. Defaults
    /// to idle so the many elements that ignore it can still be previewed
    /// without one.
    var status: MIDIStatus = .idle
    var isSelected: Bool = false
    /// True while the panel is live. Only the grabbable types read it - they
    /// carry their own gesture (see EnvelopeView), unlike the ones the row
    /// operates on their behalf.
    var active: Bool = false
    var onOperate: ((inout CanvasElement) -> Bool) -> Void = { _ in }
    /// A button was pressed. Separate from `onOperate`, which carries a value
    /// that changed: a button has no value, it has an effect.
    var onTrigger: () -> Void = {}
    /// A .mid file was dropped on a MIDI Player.
    var onDropFile: (URL) -> Void = { _ in }

    var body: some View {
        switch element.type {
        case .ad, .adsr, .mseg:
            // One view for all three: the shape branches per type inside
            // envelopePoints, and nothing else about them differs.
            EnvelopeView(element: element, isSelected: isSelected,
                         active: active, onOperate: onOperate)
        // Both pass `name` rather than a substituted entry name: with a value
        // list the entry is shown *inside* the control now, and having it
        // under there as well would be the same word twice with nothing left
        // saying which parameter this is.
        case .knob:
            KnobView(
                name: element.name,
                value: element.parameterValue(0),
                floor: element.valueRange.lowerBound, ceiling: element.valueRange.upperBound,
                bipolar: element.bipolar,
                fractionOverride: element.valueListActive ? element.displayFraction : nil,
                readoutOverride: element.valueCaption,
                isSelected: isSelected
            )
        case .slider:
            SliderView(
                name: element.name,
                value: element.parameterValue(0), bipolar: element.bipolar,
                floor: element.valueRange.lowerBound, ceiling: element.valueRange.upperBound,
                fractionOverride: element.valueListActive ? element.displayFraction : nil,
                readoutOverride: element.valueCaption,
                isSelected: isSelected
            )
        case .radio:
            RadioView(
                name: element.name,
                segmentCount: element.segmentCount,
                entries: ValueList.entryNames(element.values, count: element.segmentCount),
                selected: element.selected,
                isSelected: isSelected
            )
        case .combobox:
            ComboBoxView(
                name: element.name,
                entries: ValueList.entryNames(element.values, count: ValueList.entryCount(element.values)),
                selected: element.selected,
                isSelected: isSelected,
                active: active,
                onChoose: { index in onOperate { $0.choose(entry: index) } }
            )
        case .checkbox:
            CheckboxView(name: element.name, checked: element.checked, isSelected: isSelected)
        case .xyPad:
            XYPadView(element: element, isSelected: isSelected,
                      active: active, onOperate: onOperate)
        case .xyQuad:
            XYQuadView(element: element, isSelected: isSelected,
                       active: active, onOperate: onOperate)
        case .led:
            LEDView(name: element.name, lit: status.activity.inputLit, isSelected: isSelected)
        case .status:
            StatusView(
                name: element.name,
                outputName: status.outputName, inputName: status.inputName,
                controllerNames: status.controllerNames,
                sentLines: status.activity.sentLines,
                isSelected: isSelected
            )
        case .monitor:
            // The history is read here rather than inside the element so the
            // element stays a view of lines it was given, not a thing that
            // knows where messages come from.
            MonitorView(
                name: element.name,
                lines: element.lines,
                history: status.activity.recent(element.lines),
                isSelected: isSelected
            )
        case .header:
            HeaderView(name: element.name, filled: element.filled, isSelected: isSelected)
        case .label:
            LabelView(name: element.name, align: element.align, isSelected: isSelected)
        case .random, .sendAll, .panic:
            ActionButtonView(
                name: element.name, systemImage: Self.actionIcon(for: element.type),
                isSelected: isSelected, active: active, onTrigger: onTrigger
            )
        case .midiPlayer:
            MIDIPlayerView(name: element.name, isSelected: isSelected,
                           active: active, player: status.player,
                           onDrop: onDropFile, onTrigger: onTrigger)
        }
    }

    /// The same icon each type's own toolbar button already carries (see
    /// ContentView's Send All / Panic), so the placed button and the
    /// command that does the same thing read as one action.
    ///
    /// Only reached for the three types that route here - the switch above
    /// is what guarantees it, so `default` is the Panic icon rather than a
    /// question mark nobody would ever see.
    private static func actionIcon(for type: ElementType) -> String {
        switch type {
        case .random: "shuffle"
        case .sendAll: "paperplane"
        default: "exclamationmark.octagon" // Panic
        }
    }
}

#Preview {
    HStack {
        PlacedElementView(element: CanvasElement(type: .knob, rect: CGRect(x: 0, y: 0, width: 80, height: 80)))
            .frame(width: 80, height: 80)
        PlacedElementView(element: CanvasElement(type: .adsr, rect: CGRect(x: 0, y: 0, width: 160, height: 100)), isSelected: true)
            .frame(width: 160, height: 100)
    }
    .padding()
}
