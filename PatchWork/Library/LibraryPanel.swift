//
//  LibraryPanel.swift
//  PatchWork
//
//  Left sidebar showing the catalogue of placeable control types. Clicking
//  a row places an instance of that type on the canvas immediately - no
//  arm-then-click-canvas step - so rows are plain buttons, not a
//  List(selection:), since there's no persistent "this row is chosen"
//  state to track anymore.
//

import SwiftUI

private struct LibraryGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [ElementType]
}

private let libraryGroups: [LibraryGroup] = [
    LibraryGroup(title: "Controls", items: [.knob, .slider, .xyPad, .xyQuad, .radio, .checkbox, .combobox]),
    LibraryGroup(title: "Envelopes", items: [.ad, .adsr, .mseg]),
    LibraryGroup(title: "Actions", items: [.random, .sendAll, .panic, .midiPlayer]),
    LibraryGroup(title: "Display", items: [.led, .status, .monitor]),
    LibraryGroup(title: "Furniture", items: [.header, .label]),
]

struct LibraryPanel: View {
    var onSelectType: (ElementType) -> Void
    /// Dragged by the divider beside it - see PanelDivider.
    ///
    /// Taken from outside rather than fixed here. It used to be a hardcoded
    /// `.frame(width: 200)`, which with a second frame around it left this
    /// panel sitting at 200 points centred inside a wider box - and the box
    /// had no background of its own, so the gap read as a white frame that
    /// grew as the divider was dragged.
    var width: CGFloat = 200
    /// False while the arrangement is locked - nothing is placed on a locked
    /// page. Greyed rather than hidden: the catalogue is still worth reading,
    /// and a panel that vanished would say the lock had done something bigger
    /// than it has.
    var enabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            List {
                ForEach(libraryGroups) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            Button {
                                onSelectType(item)
                            } label: {
                                Label(item.title, systemImage: "square.dashed")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    LibraryPanel(onSelectType: { _ in })
}
