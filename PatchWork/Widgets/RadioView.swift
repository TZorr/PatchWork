//
//  RadioView.swift
//  PatchWork
//
//  Segmented strip - no clicking to change the selected segment, but the
//  segment count, which one is picked and what each is called are all
//  real: the count and selection come from the element, the labels from
//  its value list.
//
//  One segment filled solid accent (dark text on it, light text
//  elsewhere), a divider on every other segment's left edge, no divider
//  where the accent fill already makes the boundary obvious.
//
//  No solid panel fill under the strip: every widget here already sits on
//  the shared .ultraThinMaterial card background, and a second opaque fill
//  underneath would just cover that up for no benefit - the non-selected
//  segments show the card material straight through instead.
//

import SwiftUI

struct RadioView: View {
    let name: String
    var segmentCount: Int = 4
    /// One label per segment, already resolved by ValueList - which fills
    /// a short list up with position numbers and ignores anything past
    /// the segment count. Empty only if this view is built without them.
    var entries: [String] = []
    /// 1-based - these are positions on a strip, and the first one is the
    /// 1st.
    var selected: Int = 1
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    /// Clamped for drawing only: Selected is bounded by the segment *cap*,
    /// not by this element's own
    /// count, so turning the count down leaves it pointing past the end.
    /// The stored value is left alone, so turning the count back up
    /// restores the old pick.
    private var selectedIndex: Int {
        min(max(0, selected - 1), segmentCount - 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .cardChrome(isSelected: isSelected)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let cornerRadius: CGFloat = 6
        let panel = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
        guard panel.width > 0, panel.height > 0 else { return }

        context.clip(to: Path(roundedRect: panel, cornerRadius: cornerRadius))

        let segmentWidth = panel.width / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            let cell = CGRect(x: panel.minX + CGFloat(index) * segmentWidth, y: panel.minY, width: segmentWidth, height: panel.height)

            if index == selectedIndex {
                context.fill(Path(cell), with: .color(accentColor))
            } else if index > 0 {
                var divider = Path()
                divider.move(to: CGPoint(x: cell.minX, y: cell.minY))
                divider.addLine(to: CGPoint(x: cell.minX, y: cell.maxY))
                context.stroke(divider, with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }

            // Falls back to the position number for the same reason
            // ValueList does, so a view built without entries still reads
            // as a numbered strip rather than a blank one.
            let label = index < entries.count ? entries[index] : "\(index + 1)"
            let textColor: Color = index == selectedIndex ? Color(nsColor: .controlBackgroundColor) : .primary
            // Clipped to its own cell: a label is a word rather than a
            // single digit, and one too
            // long for its segment would otherwise run across the divider
            // into its neighbour and read as that segment's name.
            context.drawLayer { layer in
                layer.clip(to: Path(cell))
                layer.draw(
                    Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(textColor),
                    at: CGPoint(x: cell.midX, y: cell.midY)
                )
            }
        }
    }
}

#Preview {
    HStack {
        RadioView(name: "Radio")
        RadioView(
            name: "Radio",
            segmentCount: 4, entries: ["Saw", "Sqr", "3", "4"], selected: 2,
            isSelected: true
        )
    }
    .frame(width: 240, height: 56)
    .padding()
}
