//
//  ComboBoxView.swift
//  PatchWork
//
//  Dropdown field. In active mode a click opens the real list; stepping to
//  the next entry is only the fallback for callers with no view to put a
//  menu over (see ControlOperation.press).
//
//  A real NSMenu rather than SwiftUI's `.popover`: a popover is its own
//  bubble with a callout arrow, which reads as a tooltip, not a combo box.
//  NSMenu is what AppKit's own pull-down controls use, so popping one up
//  flush under the field - rounded corners, hover highlight, checkmark,
//  type-ahead, native scrolling past a screenful - gives the exact look
//  and behaviour of a system combo box for free. It also runs as a real
//  floating window, so it is unaffected by the canvas's own zoom and
//  scroll clipping the way a plain SwiftUI overlay anchored in the same
//  view tree would be.
//
//  A rounded field with the selected entry's name left-aligned, a chevron
//  reserved in its own column on the right so a long entry runs out under
//  its own clip instead of over the arrow. An empty list still shows "1",
//  which is not a placeholder: an entry with no name reads as its own
//  position.
//

import AppKit
import SwiftUI

struct ComboBoxView: View {
    let name: String
    /// The element's entry names, already resolved by ValueList - which
    /// is where the "an unnamed entry reads as its position" rule lives,
    /// and why an empty list still arrives here as one entry called "1".
    var entries: [String] = ["1"]
    /// 1-based.
    var selected: Int = 1
    var isSelected: Bool = false
    /// True while the panel is live - when the list can be opened.
    var active: Bool = false
    /// An entry was chosen, 0-based.
    var onChoose: (Int) -> Void = { _ in }

    @State private var showingEntries = false
    @Environment(\.appAccentColor) private var accentColor

    /// Clamped for drawing only: Selected is bounded by the entry *cap*,
    /// not by this list's own length, so a
    /// shortened list leaves it pointing past the end. The stored value is
    /// left alone, so lengthening the list again restores the old pick.
    private var entryText: String {
        guard !entries.isEmpty else { return "1" }
        return entries[min(max(0, selected - 1), entries.count - 1)]
    }

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                DropdownAnchor(
                    entries: entries, selected: selected,
                    isPresented: $showingEntries, onChoose: onChoose
                )
            )

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .cardChrome(isSelected: isSelected)
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded { showingEntries = true },
            including: active ? .all : .subviews
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let fieldRadius: CGFloat = 6
        let pad: CGFloat = 8
        let chevronWidth: CGFloat = 9
        let chevronHeight: CGFloat = 5
        let margin: CGFloat = 4

        let field = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        guard field.width > 2, field.height > 2 else { return }

        let fieldPath = Path(roundedRect: field, cornerRadius: fieldRadius)
        context.fill(fieldPath, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(fieldPath, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)

        // The chevron's column is reserved before the caption is laid out,
        // so a long entry runs out under its own clip instead of over the
        // arrow.
        let chevronX = field.maxX - pad - chevronWidth / 2
        let captionLeft = field.minX + pad
        let captionWidth = chevronX - chevronWidth / 2 - pad - captionLeft
        if captionWidth > 0 {
            let caption = CGRect(x: captionLeft, y: field.minY, width: captionWidth, height: field.height)
            context.drawLayer { layer in
                layer.clip(to: Path(caption))
                layer.draw(
                    Text(entryText).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary),
                    at: CGPoint(x: caption.minX, y: caption.midY),
                    anchor: .leading
                )
            }
        }

        // Accent-colored, so the one part that says "there is a list
        // behind this" is also the part that reads as interactive.
        let middle = field.midY
        var chevron = Path()
        chevron.move(to: CGPoint(x: chevronX - chevronWidth / 2, y: middle - chevronHeight / 2))
        chevron.addLine(to: CGPoint(x: chevronX, y: middle + chevronHeight / 2))
        chevron.addLine(to: CGPoint(x: chevronX + chevronWidth / 2, y: middle - chevronHeight / 2))
        context.stroke(chevron, with: .color(accentColor), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

/// Sizes and positions itself exactly over the field (see the `.background`
/// above) purely to have a real NSView at the right place and in the right
/// window; it never touches a click itself, so the SwiftUI `TapGesture`
/// above still decides whether a tap opens the list. Setting `isPresented`
/// pops a native `NSMenu` up flush under that frame.
private struct DropdownAnchor: NSViewRepresentable {
    var entries: [String]
    var selected: Int
    @Binding var isPresented: Bool
    var onChoose: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.onChoose = onChoose
        guard isPresented else { return }
        // Not inline: popping the menu up is a nested run loop, and firing
        // it from inside updateNSView - itself driven by the state change
        // that set isPresented - would mutate that same state (clearing it
        // below) while SwiftUI is still applying the update it came from.
        DispatchQueue.main.async {
            isPresented = false
            present(from: nsView, coordinator: context.coordinator)
        }
    }

    private func present(from view: NSView, coordinator: Coordinator) {
        let menu = NSMenu()
        menu.minimumWidth = view.bounds.width
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.target = coordinator
            item.tag = index
            item.state = index + 1 == selected ? .on : .off
            menu.addItem(item)
        }
        // Flipped, so (0, height) is the field's own bottom-left rather
        // than AppKit's usual bottom-up one - i.e. directly under it.
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: view.bounds.height + 2), in: view)
    }

    final class Coordinator: NSObject {
        var onChoose: (Int) -> Void = { _ in }

        @objc func choose(_ sender: NSMenuItem) {
            onChoose(sender.tag)
        }
    }

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

#Preview {
    HStack {
        ComboBoxView(name: "Combobox")
        ComboBoxView(
            name: "Combobox",
            entries: ["Saw", "Square", "Triangle"], selected: 2,
            isSelected: true
        )
    }
    .frame(width: 160, height: 56)
    .padding()
}
