//
//  PanelDivider.swift
//  PatchWork
//
//  A divider you can drag, between a side panel and the canvas.
//
//  Hand-rolled rather than reached for via HSplitView: three panes where the
//  middle must take all the slack and the outer two come and go with the
//  mode is exactly where HSplitView starts making its own decisions about
//  widths, with no way to check the result except by reading it. Twenty
//  lines that do one thing.
//
//  The visible line stays one point - a seam, not a control - while the part
//  that takes the drag is wider, for the same reason an element's resize
//  grips catch a wider area than they draw: the line says where the edge is,
//  the hit area says where you can take hold of it.
//
//  **The drag is measured in global space, and it has to be.** This view is
//  a sibling of the panel it resizes, so changing that width re-lays the row
//  out and moves *this* view - a translation in local space would be
//  measured against an origin the gesture's own output is dragging around,
//  the same self-referential jitter an element's drag once had (see
//  EditorCanvasView), from the opposite direction. Global coordinates are
//  screen coordinates, and the screen does not move.
//

import SwiftUI

struct PanelDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    /// Which side of the canvas this divider is on. A divider on the canvas's
    /// leading edge grows its panel as it is dragged right; one on the
    /// trailing edge grows its panel as it is dragged *left*, so the
    /// translation counts the other way.
    let edge: HorizontalEdge

    /// The width the panel had when the drag began. A drag reports how far it
    /// has come in total, so measuring from the start is what keeps the edge
    /// under the pointer instead of accelerating away from it.
    @State private var widthAtStart: CGFloat?

    private let hitWidth: CGFloat = 8

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: hitWidth)
            .overlay(Divider())
            .contentShape(Rectangle())
            .onHover { inside in
                // Pushed and popped rather than set: the cursor belongs to
                // whoever is under it, and a plain `set` would leave the
                // resize arrows behind after the pointer had moved on.
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = widthAtStart ?? width
                        widthAtStart = start
                        let delta = edge == .leading ? value.translation.width : -value.translation.width
                        width = min(max(start + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in widthAtStart = nil }
            )
    }
}
