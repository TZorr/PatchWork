//
//  ParameterTableView.swift
//  PatchWork
//
//  The Inspector's lower half when Value List is off: one row per
//  addressable parameter, which is what makes every type one thing. A knob
//  has one parameter, an ADSR four, an MSEG two per node, and all of them
//  are entered here the same way.
//
//  What sits between the name and the value follows the element's output,
//  because that is the only thing the parameters disagree on - a CC number
//  each, an NRPN pair each, or a SysEx line each. The protocol, channel and
//  resolution are the same for all of them and are set in the form above.
//  Columns come from OutputProtocol.parameterColumns.
//
//  The first column is not editable: an ADSR's rows are always attack,
//  decay, sustain and release in that order, and a typed name could
//  disagree with the shape the curve is drawn from. Nor is Parsed, which
//  is derived from the template beside it - see SysEx.parse.
//

import SwiftUI

struct ParameterTableView: View {
    @Binding var element: CanvasElement

    @Environment(\.appAccentColor) private var accentColor

    private var columns: [ParameterColumn] { element.output.parameterColumns }
    private var names: [String] {
        ParameterSchema.parameterNames(for: element.type, parameterCount: element.parameters.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
                GridRow {
                    ForEach(columns) { column in
                        Text(column.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Divider()
                    .gridCellColumns(columns.count)

                ForEach(Array(element.parameters.enumerated()), id: \.element.id) { row, _ in
                    GridRow {
                        Text(row < names.count ? names[row] : "\(row + 1)")
                            .font(.caption2)
                            .lineLimit(1)

                        ForEach(columns.dropFirst()) { column in
                            cell(column: column, row: row)
                        }
                    }
                }
            }

            // Only an MSEG gains and loses nodes - the other envelopes'
            // shapes are fixed by what they are, and a pad's axes are its
            // axes.
            if element.traits.contains(.variableNodes) {
                HStack(spacing: 8) {
                    Button {
                        addNode()
                    } label: {
                        Label("Add Node", systemImage: "plus")
                    }
                    .disabled(element.nodeCount >= ElementOptions.msegMaxNodes)

                    Button {
                        removeNode()
                    } label: {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(element.nodeCount <= 1)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
        }
    }

    /// Two rows per node, which keeps the list's parity and so keeps
    /// whatever Release said still true - a release-shaped list stays odd,
    /// a held one stays even, without either being re-derived here.
    private func addNode() {
        let next = (element.parameters.map(\.cc).max() ?? ParameterSchema.firstAddress - 1) + 1
        let middle = CanvasLayout.ccRange.upperBound / 2
        element.parameters.append(ElementParameter(cc: next, value: middle))
        element.parameters.append(ElementParameter(cc: next + 1, value: middle))
    }

    private func removeNode() {
        element.parameters.removeLast(min(2, element.parameters.count))
    }

    @ViewBuilder
    private func cell(column: ParameterColumn, row: Int) -> some View {
        switch column {
        case .cc:
            intCell(intBinding(row, \.cc, range: CanvasLayout.ccRange))
        case .msb:
            intCell(intBinding(row, msbKeyPath, range: CanvasLayout.ccRange))
        case .lsb:
            intCell(intBinding(row, lsbKeyPath, range: CanvasLayout.ccRange))
        case .template:
            TextField("", text: $element.parameters[row].sysex)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
        case .parsed:
            // Derived, never edited: the template is the input and this is what
            // it came to - one token per byte, F0 and F7 filled in, VAL
            // expanded to as many slots as the value format takes, and the
            // checksum's bracket replaced by CS where its byte will land. So a
            // line can be counted against the manual.
            //
            // A complaint takes its place when the line is unsound, in the
            // accent so it reads as this cell telling you something rather
            // than as a byte you typed.
            let parsed = SysEx.parse(element.parameters[row].sysex, format: element.valueFormat)
            Text(parsed.problem.isEmpty
                 ? (parsed.tokens.isEmpty ? "—" : parsed.tokens.joined(separator: " "))
                 : parsed.problem)
                .font(.caption2)
                .foregroundStyle(parsed.problem.isEmpty
                                 ? (parsed.tokens.isEmpty ? AnyShapeStyle(.tertiary)
                                                          : AnyShapeStyle(.secondary))
                                 : AnyShapeStyle(accentColor))
                .textSelection(.enabled)
                .lineLimit(2)
        case .value:
            // The element's own domain, not a fixed 7 bits: the
            // resolution belongs to the element, so widening it widens
            // every parameter at once.
            intCell(intBinding(row, \.value, range: element.valueRange))
        case .name:
            // Drawn by the GridRow itself, ahead of these cells - it is the
            // row's own label rather than a field. See `body`.
            EmptyView()
        }
    }

    private func intCell(_ binding: Binding<Int>) -> some View {
        TextField("", value: binding, format: .number)
            .textFieldStyle(.roundedBorder)
            .font(.caption2)
            .monospacedDigit()
    }

    /// MSB and LSB are one column pair serving two protocols: NRPN's
    /// parameter number and Program's bank select. Which storage they
    /// edit follows the output rather than being one shared pair of
    /// fields, so switching protocol doesn't silently rewrite the other's
    /// numbers.
    private var msbKeyPath: WritableKeyPath<ElementParameter, Int> {
        element.output == .program ? \.bankMSB : \.paramMSB
    }

    private var lsbKeyPath: WritableKeyPath<ElementParameter, Int> {
        element.output == .program ? \.bankLSB : \.paramLSB
    }

    private func intBinding(
        _ row: Int, _ keyPath: WritableKeyPath<ElementParameter, Int>, range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { element.parameters[row][keyPath: keyPath] },
            set: { element.parameters[row][keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

#Preview {
    @Previewable @State var knob = CanvasElement(type: .knob, rect: .zero)
    @Previewable @State var adsr = CanvasElement(type: .adsr, rect: .zero)

    VStack(alignment: .leading, spacing: 20) {
        ParameterTableView(element: $knob)
        ParameterTableView(element: $adsr)
    }
    .frame(width: 280)
    .padding()
}
