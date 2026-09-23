//
//  EditorCanvasView.swift
//  PatchWork
//
//  The editor surface. Always exactly fills the space between the Library
//  and Inspector panels - grows and shrinks with the window, no fixed size
//  and no scrolling. Placed elements are clamped to those live bounds (see
//  `clamped(_:to:)` below) so dragging or resizing past an edge stops
//  right at it instead of sliding the element somewhere unreachable. New
//  elements are placed directly from a Library click (see ContentView),
//  not from a canvas click - clicking a placed element selects it (shown
//  in Inspector), Command-clicking adds it to the selection or takes it back
//  out, and clicking empty canvas clears the selection.
//  Right-click (or long-press) a placed element for a Delete option.
//  Elements can be dragged to reposition them - the whole selection moves
//  together - and, when exactly one is selected, resized from any of its
//  four corner handles. Handles only on a lone selection: four grips on each
//  of six elements is noise, and what a group resize should even mean is a
//  question nobody has asked yet.
//
//  All of that is the *editor*. In active mode the surface shows the same
//  elements with none of it: no grid, no selection, nothing to drag, resize,
//  duplicate or delete. A panel in use should look and behave like a panel.
//

import SwiftUI

struct EditorCanvasView: View {
    /// The canvas's own coordinate space, so a gesture can say where it
    /// happened in terms of the page rather than of whichever view it is
    /// attached to.
    ///
    /// Needed because `.offset` moves a view on screen **without moving its
    /// layout position**: an element view is laid out at the canvas's origin
    /// and drawn wherever its rect says, so the gesture's own "local" space
    /// starts at the top left of the *canvas*, not of the element. Reading a
    /// press position that way put every Radio click in its last segment,
    /// since a strip at x=500 divides out well past its own width.
    static let space = "PatchWorkCanvas"

    @Binding var elements: [CanvasElement]
    /// Every selected element. A set rather than one id: aligning and packing
    /// are what a selection is *for*, and neither means anything to one
    /// element.
    @Binding var selection: Set<CanvasElement.ID>
    /// The connected MIDI output's name, for the Status element to show.
    /// Nil when nothing is connected, which is what it reports.
    var status: MIDIStatus = .idle
    /// True while the layout is being used rather than arranged.
    var active: Bool = false
    /// True while the arrangement is nailed down: nothing moves, resizes,
    /// duplicates or is deleted. Selecting still works - picking an element to
    /// look at its properties is not moving it, and a locked panel you could
    /// not even inspect would be a worse tool than an unlocked one.
    var locked: Bool = false
    /// The element Learn is waiting on, if any - drawn as armed.
    var armedElementID: CanvasElement.ID?
    /// Called with an element whose value a gesture just changed, so it can
    /// be sent. The canvas has no MIDI of its own - see ContentView.
    var onOperated: (CanvasElement) -> Void = { _ in }
    /// An action button on the panel was pressed. What each one does is
    /// ContentView's business - the canvas only knows one was.
    var onTriggered: (CanvasElement) -> Void = { _ in }
    /// A .mid file was dropped on a MIDI Player element. Which element it
    /// landed on does not matter - there is one player.
    var onDropFile: (URL) -> Void = { _ in }
    /// Elements were deleted from the context menu. The canvas can remove them
    /// itself, but anything *pointing* at one - a Learn run, say - lives above
    /// it and has to be told.
    var onDeleted: (Set<CanvasElement.ID>) -> Void = { _ in }

    /// Which elements a right-click acts on: the whole selection when the click
    /// landed inside it, otherwise just what it landed on.
    private func targeted(_ element: CanvasElement) -> Set<CanvasElement.ID> {
        selection.contains(element.id) ? selection : [element.id]
    }

    /// Which element is being dragged and how far it has come, so the rest of
    /// the selection can follow it live.
    ///
    /// Held here rather than in each row because it is one gesture moving
    /// several views: the dragged row carries its own `@GestureState` offset
    /// as before (an ancestor moving out from under an active gesture is what
    /// caused the old jitter), and the others read this.
    @State private var groupDrag: GroupDrag?
    /// The live rubber-band rectangle, in the canvas's own space - drawn
    /// while dragging on empty canvas, nil once the drag ends or before one
    /// has begun. A click on empty canvas is the same gesture with near-zero
    /// travel, same as a row's own click-vs-drag split (see PlacedElementRow).
    @State private var marquee: CGRect?
    /// Whether Command is held, so a marquee drag can extend the existing
    /// selection instead of replacing it - the same convention a single
    /// element's own click already uses. Tracked the same way
    /// PlacedElementRow tracks its own: a gesture's value carries no
    /// modifiers, so this listens for them separately.
    @State private var heldModifiers: EventModifiers = []

    /// The window's own, supplied by AppKit - see CanvasUndo.
    @Environment(\.undoManager) private var undoManager
    @Environment(\.appAccentColor) private var accentColor

    private struct GroupDrag: Equatable {
        let id: CanvasElement.ID
        let translation: CGSize
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size

            ZStack(alignment: .topLeading) {
                CanvasGrid(size: canvasSize, active: active)
                    .equatable()
                    .overlay(
                        Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )

                ForEach(elements) { element in
                    PlacedElementRow(
                        element: element,
                        isSelected: selection.contains(element.id),
                        isLoneSelection: selection == [element.id] && !locked,
                        isArmed: element.id == armedElementID,
                        canvasSize: canvasSize,
                        status: status,
                        active: active,
                        locked: locked,
                        // Follows the drag only while some *other* element is
                        // the one being dragged; the dragged row has its own
                        // live offset.
                        groupTranslation: groupDrag.map {
                            $0.id != element.id && selection.contains(element.id)
                                ? $0.translation : .zero
                        } ?? .zero,
                        onSelect: { extending in
                            if extending {
                                // Command toggles, on the press and at once, so
                                // a wrongly added element comes off the same
                                // way it went on. Command rather than Shift
                                // because that is what macOS means by a
                                // discontiguous selection - and because Shift
                                // already means the fine drag in active mode,
                                // so one modifier now has one meaning.
                                if selection.contains(element.id) {
                                    selection.remove(element.id)
                                } else {
                                    selection.insert(element.id)
                                }
                            } else if !selection.contains(element.id) {
                                // Pressing inside an existing selection keeps
                                // it - otherwise picking one up to drag the
                                // group would throw the group away first.
                                // Pressing anything else selects that one
                                // alone, immediately.
                                selection = [element.id]
                            }
                        },
                        onGroupDrag: { translation in
                            groupDrag = translation.map { GroupDrag(id: element.id, translation: $0) }
                        },
                        onCommitMove: { translation in
                            let moving = selection.contains(element.id) ? selection : [element.id]
                            let previous = elements
                            for index in elements.indices where moving.contains(elements[index].id) {
                                var rect = elements[index].rect
                                rect.origin.x = CanvasLayout.snapped(rect.minX + translation.width)
                                rect.origin.y = CanvasLayout.snapped(rect.minY + translation.height)
                                elements[index].setRect(clamped(rect, to: canvasSize))
                            }
                            CanvasUndo.register(undoManager, binding: $elements, previous: previous,
                                                 actionName: moving.count > 1 ? "Move Elements" : "Move Element")
                        },
                        onCommitRect: { newRect in
                            if let index = elements.firstIndex(where: { $0.id == element.id }) {
                                let previous = elements
                                elements[index].setRect(clamped(newRect, to: canvasSize))
                                CanvasUndo.register(undoManager, binding: $elements, previous: previous, actionName: "Resize Element")
                            }
                        },
                        onDuplicate: {
                            // A right-click inside the selection acts on all of
                            // it; outside, only on the element under the
                            // pointer - otherwise a click beside the selection
                            // would reach for one it is not pointing at.
                            let targets = targeted(element)
                            let copies = elements.filter { targets.contains($0.id) }
                                .map { $0.duplicated() }
                            let previous = elements
                            elements.append(contentsOf: copies)
                            selection = Set(copies.map(\.id))
                            CanvasUndo.register(undoManager, binding: $elements, previous: previous,
                                                 actionName: copies.count > 1 ? "Duplicate Elements" : "Duplicate Element")
                        },
                        onDelete: {
                            let targets = targeted(element)
                            let previous = elements
                            elements.removeAll { targets.contains($0.id) }
                            selection.subtract(targets)
                            onDeleted(targets)
                            CanvasUndo.register(undoManager, binding: $elements, previous: previous,
                                                 actionName: targets.count > 1 ? "Delete Elements" : "Delete Element")
                        },
                        onOperate: { change in
                            guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
                            guard change(&elements[index]) else { return }
                            // Only when something actually changed: a drag is
                            // a stream of mouse moves, and a message per move
                            // saying the same thing would flood the port.
                            onOperated(elements[index])
                        },
                        onTrigger: { onTriggered(element) },
                        onDropFile: onDropFile
                    )
                }

                // Drawn last, over every element, while a rubber-band drag
                // is live - the same reason a marquee always renders on top
                // in any editor that has one.
                if let marquee {
                    Rectangle()
                        .fill(accentColor.opacity(0.12))
                        .overlay(Rectangle().stroke(accentColor, lineWidth: 1))
                        .frame(width: marquee.width, height: marquee.height)
                        .offset(x: marquee.minX, y: marquee.minY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                // A zero-minimum-distance drag, the same shape as
                // PlacedElementRow's own click-vs-drag gesture: a plain
                // click clears the selection exactly as the old
                // SpatialTapGesture here did, and any real movement instead
                // grows a rubber band and selects whatever it touches.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        marquee = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                    }
                    .onEnded { value in
                        defer { marquee = nil }
                        let isClick = abs(value.translation.width) < 1 && abs(value.translation.height) < 1
                        guard !isClick else {
                            selection.removeAll()
                            return
                        }
                        guard let marquee else { return }
                        let hit = elements.filter { marquee.intersects($0.rect) }
                        if heldModifiers.contains(.command) {
                            selection.formUnion(hit.map(\.id))
                        } else {
                            selection = Set(hit.map(\.id))
                        }
                    },
                including: active ? .subviews : .all
            )
            .onModifierKeysChanged(mask: [.command]) { _, held in
                heldModifiers = held
            }
            .coordinateSpace(.named(Self.space))
        }
    }
}

#Preview {
    EditorCanvasView(elements: .constant([]), selection: .constant([]))
        .frame(width: 600, height: 400)
}

/// The page and its ruling.
///
/// **Dots, not lines**: at 8 points a line grid reads as a solid tint and
/// fights the elements drawn on it, while dots
/// stay a reference. It is also the snap step, so what you see is what things
/// land on.
///
/// Equatable and used with `.equatable()` so a drag does not re-run several
/// thousand dot placements on every frame - the grid changes when the canvas
/// resizes or the mode flips, and at no other time.
private struct CanvasGrid: View, Equatable {
    let size: CGSize
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(Color(nsColor: .textBackgroundColor)))

            // No grid while the layout is live: the raster is scaffolding for
            // placing things, and a panel in use should look like a panel.
            guard !active else { return }

            let step = CanvasLayout.grid
            var dots = Path()
            var y = step
            while y < size.height {
                var x = step
                while x < size.width {
                    dots.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(.secondary.opacity(0.35)))
        }
    }
}

/// Keeps a rect within `bounds` (the canvas's current top-left-origin
/// frame): position clamped to [0, bounds - size], size capped to not
/// exceed the bounds, floored at the smaller of `CanvasLayout.
/// minimumElementSize` and the bounds themselves so a tiny window can't
/// force a negative size.
private func clamped(_ rect: CGRect, to bounds: CGSize) -> CGRect {
    let w = min(rect.width, bounds.width).clamped(lowerBound: min(CanvasLayout.minimumElementSize, bounds.width))
    let h = min(rect.height, bounds.height).clamped(lowerBound: min(CanvasLayout.minimumElementSize, bounds.height))
    let x = min(max(rect.minX, 0), max(0, bounds.width - w))
    let y = min(max(rect.minY, 0), max(0, bounds.height - h))
    return CGRect(x: x, y: y, width: w, height: h)
}

private extension CGFloat {
    func clamped(lowerBound: CGFloat) -> CGFloat { Swift.max(self, lowerBound) }
}

/// The four corner handles a selected element resizes from. Each keeps the
/// opposite corner anchored while dragged.
private enum ResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var isLeftEdge: Bool { self == .topLeft || self == .bottomLeft }
    var isTopEdge: Bool { self == .topLeft || self == .topRight }

    /// Applies a drag translation to `rect` from this corner, with the
    /// opposite corner staying fixed.
    ///
    /// Written in edges rather than in origin-and-size, and for a reason: the
    /// two edges the pointer moves are the two that snap, and the anchored ones
    /// must not drift by a rounding step. Floored at
    /// `CanvasLayout.minimumElementSize` by moving the *dragged* edge back,
    /// never the anchored one.
    func resized(_ rect: CGRect, by translation: CGSize) -> CGRect {
        var left = rect.minX, top = rect.minY, right = rect.maxX, bottom = rect.maxY
        if isLeftEdge {
            left = CanvasLayout.snapped(rect.minX + translation.width)
        } else {
            right = CanvasLayout.snapped(rect.maxX + translation.width)
        }
        if isTopEdge {
            top = CanvasLayout.snapped(rect.minY + translation.height)
        } else {
            bottom = CanvasLayout.snapped(rect.maxY + translation.height)
        }

        let floor = CanvasLayout.minimumElementSize
        if right - left < floor {
            if isLeftEdge { left = right - floor } else { right = left + floor }
        }
        if bottom - top < floor {
            if isTopEdge { top = bottom - floor } else { bottom = top + floor }
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

private struct ResizeState {
    let corner: ResizeCorner
    let translation: CGSize
}

/// One placed element's view plus its interaction: select on click, drag to
/// reposition, resize from a corner handle when selected, right-click to
/// duplicate or delete. Live drag/resize is a transient `@GestureState`
/// offset, clamped against `canvasSize` on every frame so the element
/// can never be dragged or resized somewhere outside the visible canvas -
/// only the final geometry is committed back to `elements`.
private struct PlacedElementRow: View {
    let element: CanvasElement
    let isSelected: Bool
    /// Whether this element is the *only* one selected - which is when the
    /// resize handles appear.
    let isLoneSelection: Bool
    /// Whether Learn is waiting on this element.
    let isArmed: Bool
    let canvasSize: CGSize
    let status: MIDIStatus
    let active: Bool
    let locked: Bool
    /// How far the rest of the selection has been dragged by another element.
    let groupTranslation: CGSize
    /// True when Shift was held, meaning add to the selection rather than
    /// replace it.
    var onSelect: (Bool) -> Void
    /// The live drag, for the rest of the selection to follow. Nil on release.
    var onGroupDrag: (CGSize?) -> Void
    /// A finished move, applied to the whole selection.
    var onCommitMove: (CGSize) -> Void
    var onCommitRect: (CGRect) -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    /// Applies a change to this element and reports whether it changed, so
    /// only a real change is sent. See EditorCanvasView.onOperated.
    var onOperate: ((inout CanvasElement) -> Bool) -> Void
    var onTrigger: () -> Void
    var onDropFile: (URL) -> Void

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var resizeState: ResizeState?
    /// The value the control held when the gesture began. A drag is measured
    /// against this rather than accumulated per mouse move: an accumulated
    /// delta rounds at every step and drifts, so a slow drag up and back down
    /// would not return to where it started.
    @State private var dragStartValue: Int?
    /// The modifiers held right now. Tracked separately because neither a
    /// tap's nor a drag's gesture value carries them.
    ///
    /// Two of them matter and they are deliberately different keys: **Command**
    /// adds to the selection in the editor, **Shift** is the fine drag in
    /// active mode. They used to share Shift, which meant one modifier stood
    /// for two things depending on the mode.
    @State private var heldModifiers: EventModifiers = []
    /// Whether this gesture has already settled the selection. A drag reports
    /// many changes and the selection is decided once, on the press.
    @State private var didSelect = false

    @Environment(\.appAccentColor) private var accentColor

    private var liveRect: CGRect {
        var rect = element.rect
        if let resizeState {
            rect = resizeState.corner.resized(rect, by: resizeState.translation)
        } else if locked {
            // Nailed down: the press still selects, but nothing follows the
            // pointer. Ignoring the translation here rather than dropping the
            // gesture is what keeps a locked element selectable.
            return clamped(rect, to: canvasSize)
        } else {
            // Its own gesture if it is the one being dragged, otherwise the
            // group's - only one of the two is ever non-zero.
            let translation = dragTranslation == .zero ? groupTranslation : dragTranslation
            // Snapped here rather than on release, so the element never
            // renders off-grid for a frame and the drag itself shows where it
            // will land. Clamping comes after: at the far edge an element is
            // held on the page rather than kept on the grid.
            rect.origin.x = CanvasLayout.snapped(rect.minX + translation.width)
            rect.origin.y = CanvasLayout.snapped(rect.minY + translation.height)
        }
        return clamped(rect, to: canvasSize)
    }

    var body: some View {
        // Handles are siblings of the element view, not nested inside it -
        // if they were nested, the element's own highPriorityGesture would
        // out-rank them (a highPriorityGesture beats gestures attached by
        // its *own* subviews), and a corner drag would just move the whole
        // element instead of resizing it.
        //
        // The outer ZStack itself carries no offset/position of its own -
        // that was the cause of a jitter/lag bug: the move gesture lives on
        // the element view below, and this ZStack used to be repositioned
        // live from that *same* gesture's own translation. Since the
        // gesture's view sits inside the view being repositioned, every
        // frame fed the gesture's own output back into the coordinate
        // space it measures touches against, and the drag chased itself.
        // Each gestured view now carries its own live offset directly, so
        // no ancestor moves out from under an active gesture.
        let rect = liveRect

        ZStack(alignment: .topLeading) {
            PlacedElementView(
                element: element, status: status,
                isSelected: isSelected && !active,
                active: active,
                onOperate: onOperate,
                onTrigger: onTrigger,
                onDropFile: onDropFile
            )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                // Disabled rather than swapped for a gesture-free branch, so
                // the element view itself is the same view in both modes and
                // switching cannot make SwiftUI rebuild it from scratch.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onChanged { value in
                            // The selection changes on the **press**, before
                            // any of this moves anything.
                            //
                            // It used to happen on release, and that was a
                            // real bug rather than a nicety: with A selected,
                            // pressing B left the selection on A, so B's live
                            // translation was published to the group and A
                            // moved along with it - then the commit moved only
                            // B, because B was still not in the selection, and
                            // A sprang back to where it had started.
                            if !didSelect {
                                didSelect = true
                                onSelect(heldModifiers.contains(.command))
                            }
                            guard !locked else { return }
                            onGroupDrag(value.translation)
                        }
                        .onEnded { value in
                            didSelect = false
                            onGroupDrag(nil)
                            guard !locked else { return }
                            // A zero-distance drag is a click, and there is
                            // nothing to commit for one - which matters,
                            // because a move snaps, so committing one would let
                            // a mere click shift an off-grid element from an
                            // older file.
                            let isClick = abs(value.translation.width) < 1
                                && abs(value.translation.height) < 1
                            if !isClick { onCommitMove(value.translation) }
                        },
                    including: active ? .subviews : .all
                )
                // The active-mode gesture: this one operates the control
                // instead of moving it. Each is gated so only ever one of the
                // two is live, rather than both being attached and racing.
                // Only the types this row operates on their behalf. An
                // envelope's or a pad's node is grabbed at a position inside
                // the widget's own canvas, so those carry their own gesture -
                // and a highPriorityGesture here would outrank it.
                .highPriorityGesture(
                    operateGesture(in: rect),
                    // A Combobox is left out although it is operable: on the
                    // canvas a click opens its list rather than stepping it,
                    // and that list is the widget's own (see ComboBoxView).
                    including: active && ControlOperation.isOperable(element.type)
                        && element.type != .combobox ? .all : .subviews
                )
                // Double-click a bipolar control to return it to its zero.
                // Safe alongside the drag above: a double-click is also two
                // zero-distance drags, and a zero-distance drag changes a
                // continuous control by nothing.
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { onOperate { $0.recentre() } },
                    including: active && element.bipolar && ControlOperation.isContinuous(element.type)
                        ? .all : .subviews
                )
                .onModifierKeysChanged(mask: [.shift, .command]) { _, held in
                    heldModifiers = held
                }
                .contextMenu {
                    // Empty in active mode: nothing here is an action a live
                    // panel offers, and duplicating or deleting an element
                    // mid-performance would be editing the design.
                    if !active {
                        // Disabled rather than hidden while locked: an empty
                        // menu says nothing, and these two are exactly what a
                        // lock is holding back.
                        Button("Duplicate", action: onDuplicate)
                            .disabled(locked)
                        Button("Delete", role: .destructive, action: onDelete)
                            .disabled(locked)
                    }
                }

            if isArmed {
                // Dashed rather than solid, and over the element rather than
                // instead of its selection border: armed is a different thing
                // from selected, and while Learn is waiting it is both.
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }

            if isLoneSelection && !active {
                ForEach(ResizeCorner.allCases, id: \.self) { corner in
                    resizeHandle(for: corner, in: rect)
                }
            }
        }
    }

    /// Operating the control, in active mode.
    ///
    /// A discrete control acts on the press, which is what a button should
    /// do. A continuous one tracks the drag from where it was grabbed.
    private func operateGesture(in rect: CGRect) -> some Gesture {
        // Measured in the canvas's own space and shifted by the element's
        // own position, rather than trusting the gesture's "local" one: the
        // element view is *offset* into place, which moves what you see
        // without moving where it was laid out, so its local space starts at
        // the canvas's top left. Only a Radio ever read that position, which
        // is why it alone landed in the wrong segment - a knob and a fader
        // use the translation, which no offset can disturb, and a checkbox
        // does not care where it was hit.
        DragGesture(minimumDistance: 0, coordinateSpace: .named(EditorCanvasView.space))
            .onChanged { value in
                if dragStartValue == nil {
                    dragStartValue = element.continuousValue
                    if !ControlOperation.isContinuous(element.type) {
                        onOperate {
                            $0.press(at: $0.localPoint(fromCanvas: value.startLocation),
                                     in: rect.size)
                        }
                    }
                }
                guard ControlOperation.isContinuous(element.type) else { return }
                let start = dragStartValue ?? 0
                // Up is more, and the gesture's y grows downward.
                let dy = -value.translation.height
                let fine = heldModifiers.contains(.shift)
                onOperate { $0.dragContinuous(from: start, by: dy, fine: fine) }
            }
            .onEnded { _ in dragStartValue = nil }
    }

    @ViewBuilder
    private func resizeHandle(for corner: ResizeCorner, in rect: CGRect) -> some View {
        let handleSize: CGFloat = 9
        Circle()
            .fill(accentColor)
            .frame(width: handleSize, height: handleSize)
            .position(
                x: rect.minX + corner.unitPoint.x * rect.width,
                y: rect.minY + corner.unitPoint.y * rect.height
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($resizeState) { value, state, _ in
                        state = ResizeState(corner: corner, translation: value.translation)
                    }
                    .onEnded { value in
                        onCommitRect(corner.resized(element.rect, by: value.translation))
                    }
            )
    }
}
