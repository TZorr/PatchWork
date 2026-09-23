//
//  HelpView.swift
//  PatchWork
//
//  The app's own Help window - a plain reference of every keyboard shortcut
//  and the handful of concepts (modes, Lock, Learn, Value List) a first-time
//  reader has no other way to discover, since none of them are spelled out
//  anywhere in the UI itself. Opened from the Help menu (⌘?), not a document
//  window, so it stays a singleton rather than one per canvas tab.
//

import SwiftUI

private struct HelpItem: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String?
    let detail: String
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [HelpItem]
}

private let helpSections: [HelpSection] = [
    HelpSection(title: "Modes", items: [
        HelpItem(title: "Editor / Active Mode", shortcut: "⌘R", detail: "Switches the panel between arranging it (Editor Mode) and using it (Active Mode). Active Mode hides the grid and turns off dragging, resizing and selecting."),
        HelpItem(title: "Lock", shortcut: "⌘L", detail: "Freezes the arrangement so nothing moves, resizes, duplicates or gets deleted by accident. Selecting and inspecting still work."),
    ]),
    HelpSection(title: "Canvas & Selection", items: [
        HelpItem(title: "Select", shortcut: nil, detail: "Click a placed element to select it and show its properties in the Inspector. Click empty canvas to clear the selection."),
        HelpItem(title: "Add to selection", shortcut: "⌘-Click", detail: "Command-click an element to add it to the selection, or take it back out."),
        HelpItem(title: "Rubber-band select", shortcut: nil, detail: "Drag on empty canvas to select every element inside the rectangle."),
        HelpItem(title: "Move", shortcut: nil, detail: "Drag a selected element - or the whole selection together - to reposition it. Snaps to an 8-point grid."),
        HelpItem(title: "Resize", shortcut: nil, detail: "With exactly one element selected, drag one of its four corner handles."),
        HelpItem(title: "Cycle selection", shortcut: "⇥ / ⇧⇥", detail: "Steps the selection forward or backward through every element on the canvas."),
        HelpItem(title: "Clear selection", shortcut: "⎋", detail: "Deselects everything."),
        HelpItem(title: "Delete", shortcut: "⌫", detail: "Deletes the selected element(s). Also available by right-clicking one."),
        HelpItem(title: "Select All", shortcut: "⌘A", detail: "Selects every element on the canvas."),
        HelpItem(title: "Copy / Paste", shortcut: "⌘C / ⌘V", detail: "Copies the selected elements; pasting adds duplicates offset by one grid step and selects them."),
    ]),
    HelpSection(title: "Value List", items: [
        HelpItem(title: "Copy Value List", shortcut: nil, detail: "Copies just the selected element's Value List (its named entries) on its own, independent of copying the whole element. Available once the element's Value List switch is on."),
        HelpItem(title: "Paste Value List", shortcut: nil, detail: "Applies the copied Value List to every selected element that can carry one (Knob, Slider, Radio, Combobox), turning its Value List switch on. Elements that can't carry one are left untouched."),
    ]),
    HelpSection(title: "MIDI", items: [
        HelpItem(title: "Learn", shortcut: "⌘K", detail: "Arms Learn on the selected element: move a control on the connected Controller and its address fills in automatically. Press again to cancel."),
        HelpItem(title: "Send All", shortcut: nil, detail: "Sends every element's current value - useful to resync a device after it's reconnected."),
        HelpItem(title: "Panic", shortcut: nil, detail: "Sends All Notes Off and Reset on every channel."),
        HelpItem(title: "Output / Input / Controller", shortcut: nil, detail: "Output is the port the panel sends to. Input is a device reporting back to it. Controller is a control surface whose messages also reach the Output."),
    ]),
    HelpSection(title: "File", items: [
        HelpItem(title: "Open…", shortcut: "⌘O", detail: "Opens a saved .pwork layout."),
        HelpItem(title: "Save…", shortcut: "⌘S", detail: "Saves the current layout."),
        HelpItem(title: "Undo / Redo", shortcut: "⌘Z / ⇧⌘Z", detail: "Standard undo, covering layout edits like moving, deleting, pasting and pasting a Value List."),
        HelpItem(title: "Rename Tab…", shortcut: nil, detail: "Names an unsaved or freshly opened window's tab. In the Window menu."),
    ]),
]

struct HelpView: View {
    var body: some View {
        List {
            ForEach(helpSections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        HelpRow(item: item)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 600)
        .navigationTitle("PatchWork Help")
    }
}

private struct HelpRow: View {
    let item: HelpItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Color.clear
                }
            }
            .frame(width: 64, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    HelpView()
}
