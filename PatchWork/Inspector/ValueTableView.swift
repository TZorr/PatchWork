//
//  ValueTableView.swift
//  PatchWork
//
//  The Inspector's lower half when Value List is on: the control's named
//  entries, one row of Name and Value each. The other thing that half can
//  show is the parameter table - see InspectorPanel, which switches
//  between them and carries the switch itself, since it belongs to the
//  element rather than to either table.
//
//  Starts empty on a fresh element: the list is the first thing to fill in
//  on a strip or a dropdown, not something to prefill with guesses. Which
//  is why the add button matters more here than it would on a table that
//  always has rows.
//
//  Clearing is the one edit in this panel that goes back through Undo, so
//  it is the one the table does not do itself - see InspectorPanel, which
//  holds the element array CanvasUndo needs a snapshot of.
//

import SwiftUI

struct ValueTableView: View {
    @Binding var element: CanvasElement
    /// Empties the list, undoably. Handed in rather than done here: this
    /// view holds one element and CanvasUndo snapshots the whole array.
    var onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
                GridRow {
                    Text("Name")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Value")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // Spacer column for the per-row delete button, so the
                    // two headings sit over the fields they name rather
                    // than drifting right.
                    Color.clear.frame(width: 16, height: 1)
                }

                Divider()
                    .gridCellColumns(3)

                ForEach(Array(element.values.enumerated()), id: \.element.id) { index, _ in
                    GridRow {
                        TextField("", text: $element.values[index].name)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption2)

                        TextField("", value: numberBinding(index), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption2)
                            .monospacedDigit()

                        Button {
                            element.values.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
            }

            if element.values.isEmpty {
                Text("No entries yet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    element.values.append(ValueEntry(name: "", number: 0))
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }

                // Beside Add rather than tucked away, because Learn Values
                // can now fill this list faster than anyone can empty it a
                // row at a time. Undoable, which is what lets it clear on
                // the click instead of asking first.
                Button(role: .destructive, action: onClearAll) {
                    Label("Clear List", systemImage: "trash")
                }
                .disabled(element.values.isEmpty)
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
    }

    private func numberBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { element.values[index].number },
            // Bounded by the resolution, and by nothing else. Min/Max
            // deliberately do not apply: with a list in force it is the list
            // that defines the legal values, and clamping an entry to a
            // narrowed range would quietly rewrite what the device was told.
            set: { element.values[index].number = (0...element.valueCeiling).clamp($0) }
        )
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

#Preview {
    @Previewable @State var element: CanvasElement = {
        var element = CanvasElement(type: .radio, rect: .zero)
        element.values = [ValueEntry(name: "Saw", number: 0), ValueEntry(name: "Square", number: 64)]
        return element
    }()

    ValueTableView(element: $element, onClearAll: { element.values.removeAll() })
        .frame(width: 280)
        .padding()
}
