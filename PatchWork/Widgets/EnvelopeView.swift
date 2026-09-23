//
//  EnvelopeView.swift
//  PatchWork
//
//  One view for all three envelopes - AD, ADSR and MSEG - because once the
//  shape and the drawing both moved into EnvelopeDrawing.swift there was
//  nothing left to tell them apart here. The one branch that remains per
//  type is `envelopePoints`, and this is the rest.
//
//  In active mode the corners can be grabbed. That gesture is on the *canvas*
//  rather than on the element, and it has to be: the plot is inset inside the
//  canvas and the canvas sits above a name strip, so a pointer position taken
//  from the element's own bounds would be off by the height of that strip - and
//  a node you cannot grab where you can see it is worse than one that does not
//  move at all. Attached here, the coordinates the hit test uses are the very
//  ones the dot was drawn at.
//
//  This is why the row's own operate gesture only claims the single-value types
//  (see EditorCanvasView): a highPriorityGesture on an ancestor outranks one on
//  its own subviews, so the two must not both want the same press.
//

import SwiftUI

struct EnvelopeView: View {
    let element: CanvasElement
    var isSelected: Bool = false
    /// True while the panel is live - when a node can be grabbed.
    var active: Bool = false
    /// Applies a change and reports whether anything moved, so only a real
    /// change is sent. See EditorCanvasView.
    var onOperate: ((inout CanvasElement) -> Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 2) {
            EnvelopeSurface(element: element, active: active, onOperate: onOperate)

            Text(element.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .cardChrome(isSelected: isSelected)
    }
}

/// The curve itself, and the gesture that moves its corners.
private struct EnvelopeSurface: View {
    let element: CanvasElement
    let active: Bool
    let onOperate: ((inout CanvasElement) -> Bool) -> Void

    /// Which handle this gesture took hold of, held for as long as it lasts.
    ///
    /// Grabbed once on the press rather than looked up on every move: the
    /// corner travels with the pointer, so a fresh nearest-node search each
    /// frame would let the drag hop to a neighbour the moment it passed one.
    @State private var grabbed: Int?

    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawEnvelope(in: &context, size: size, element: element, accentColor: accentColor)
            }
            .contentShape(Rectangle())
            .gesture(dragNode(in: proxy.size), including: active ? .all : .subviews)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dragNode(in size: CGSize) -> some Gesture {
        let plot = envelopePlot(in: size)
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if grabbed == nil {
                    // Nothing within reach is a press on empty field, and an
                    // envelope has plenty of that - unlike a pad, where every
                    // position belongs to some point. So it stays nil and the
                    // drag does nothing at all, rather than dragging whichever
                    // corner happened to be least far away.
                    grabbed = element.nodeIndex(at: value.startLocation, plot: plot)
                }
                guard let handle = grabbed else { return }
                onOperate { $0.dragNode(handle, to: value.location, plot: plot) }
            }
            .onEnded { _ in grabbed = nil }
    }
}

#Preview {
    // A local function inside the macro's closure is nonisolated, while the
    // module defaults to the main actor - so it has to say so itself.
    @MainActor func envelope(_ type: ElementType, _ size: CGSize) -> CanvasElement {
        CanvasElement(type: type, rect: CGRect(origin: .zero, size: size))
    }
    return HStack {
        EnvelopeView(element: envelope(.ad, CGSize(width: 208, height: 120)))
        EnvelopeView(element: envelope(.adsr, CGSize(width: 208, height: 120)), isSelected: true)
        EnvelopeView(element: envelope(.mseg, CGSize(width: 280, height: 120)))
    }
    .frame(height: 120)
    .padding()
}
