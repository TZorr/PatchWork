//
//  ControlOperation.swift
//  PatchWork
//
//  What happens when someone actually uses a control. The third member of
//  the per-type trio: ElementSchema declares what a control has, the Widgets
//  draw it, and this decides what the mouse does to it.
//
//  Operating a control writes straight into its own properties - the same
//  ones the Inspector edits. That sounds reckless and is the reason
//  ContentView snapshots every element on the way into active mode and puts
//  them back on the way out: while the layout is live, "the value" and "the
//  configured default" are the same field, so every widget draws the live
//  value without having to be told that anything is different. Nothing here
//  knows about modes, and no widget needed a second value.
//
//  Only the single-value controls are here. An envelope or a pad is operated
//  by grabbing a node - it moves a stage's length and its level at once, so
//  it is neither dragged like a knob nor clicked like a segment - and that is
//  its own step, kept separate for that reason.
//

import CoreGraphics
import Foundation

enum ControlOperation {
    /// Vertical points of drag covering a control's whole range.
    ///
    /// Dragging is vertical for both the knob and the fader: a knob is round
    /// and has no axis of its own, and vertical is the gesture every DAW
    /// uses for one.
    static let dragRange: CGFloat = 150

    /// How much slower a Shift-drag is. 8 rather than something larger
    /// because it has to stay a drag: past that the gesture needs more screen
    /// than there is.
    static let fineDragFactor: CGFloat = 8

    /// Types whose value is dragged rather than clicked.
    static func isContinuous(_ type: ElementType) -> Bool {
        type == .knob || type == .slider
    }

    /// Whether the mouse can do anything to this type at all in active mode.
    static func isOperable(_ type: ElementType) -> Bool {
        LiveProperty.of(type) != nil
    }

    /// How near the pointer has to be to grab an envelope's node, in points.
    ///
    /// Generous next to the 2.5-point dot that marks one: the dot says where
    /// the node is, this says where you can grab it, and the second should be
    /// the easier target.
    static let nodeGrabDistance: CGFloat = 9

    /// Envelopes, whose value is a shape rather than a number.
    static func hasNodes(_ type: ElementType) -> Bool {
        type == .ad || type == .adsr || type == .mseg
    }

    /// Pads, whose two values move together under one point.
    static func isPad(_ type: ElementType) -> Bool {
        type == .xyPad || type == .xyQuad
    }

    /// Pads with more than one point.
    ///
    /// A single-point pad's "wherever you click" model needs no point index at
    /// all; a pad with two needs the envelope's grab-and-hold model instead, or
    /// a fast drag would jump to whichever point is nearer the moment the
    /// pointer crossed between them.
    static func isMultiPad(_ type: ElementType) -> Bool {
        type == .xyQuad
    }

    /// Whether the mouse can move this type by position rather than by
    /// distance - an envelope's node or a pad's point.
    static func isGrabbable(_ type: ElementType) -> Bool {
        hasNodes(type) || isPad(type)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

extension CanvasElement {
    /// The value a continuous control is holding right now, which is what a
    /// drag has to be measured from.
    var continuousValue: Int { parameterValue(0) }

    /// The nearest entry in the element's value list, or `value` untouched.
    ///
    /// A control carrying named values has no meaningful position between two
    /// of them - "halfway between Saw and Square" is not a waveform - so a
    /// drag lands on entries rather than sliding past them. It is also what
    /// keeps the readout honest: it names the entry the value *is*, not the
    /// one it is nearest.
    ///
    /// Gated on `useValues`, unlike a Radio's or Combobox's own entries: for a
    /// knob the list is a property that may or may not be in force, and that
    /// switch is what says which.
    func snappedToValues(_ value: Int) -> Int {
        guard useValues, !values.isEmpty else { return value }
        let nearest = values.min {
            abs($0.number - value) < abs($1.number - value)
        }
        return nearest?.number ?? value
    }

    /// Moves a continuous control by `dy` points up from where it was
    /// grabbed, and says whether the value actually changed.
    ///
    /// `dy` is measured from the start of the gesture against the value the
    /// control held then - not accumulated per mouse move. An accumulated
    /// delta drifts: each step rounds, and a slow drag up and back down does
    /// not return to where it began.
    ///
    /// `fine` is the Shift-drag. `dragRange` of travel covering the whole
    /// range is precise enough for a 7-bit control and useless for a 14-bit
    /// one, where it is over a hundred steps per point; the fine divisor
    /// makes the same gesture worth a fraction of that.
    mutating func dragContinuous(from startValue: Int, by dy: CGFloat, fine: Bool) -> Bool {
        guard ControlOperation.isContinuous(type), !parameters.isEmpty else { return false }
        // A list in force turns the travel into stops rather than numbers -
        // see displayFraction for why, and for the Nord Lead that asked for
        // it. The gesture below is the same one, counted in entries.
        if valueListActive { return dragEntries(from: startValue, by: dy, fine: fine) }
        let range = valueRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return false }
        let reach = ControlOperation.dragRange * (fine ? ControlOperation.fineDragFactor : 1)
        // Plain `rounded()` - half away from zero, Swift's own default and
        // what a drag reads as. The tie-breaking rule is not something this
        // gesture should be picking on anyone's behalf.
        let moved = startValue + Int((dy * CGFloat(span) / reach).rounded())
        let wanted = snappedToValues(min(max(moved, range.lowerBound), range.upperBound))
        guard parameters[0].value != wanted else { return false }
        parameters[0].value = wanted
        return true
    }

    /// A point in the canvas's own space, expressed inside this element.
    ///
    /// The conversion is one subtraction and would hardly deserve a name,
    /// except that getting it wrong is invisible: a press read in the wrong
    /// space still lands somewhere, just always on the same segment. Naming it
    /// is what lets it be checked.
    func localPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - x, y: point.y - y)
    }

    /// Clicks a discrete control at `point` within an element of `size`.
    /// Returns whether anything changed.
    mutating func press(at point: CGPoint, in size: CGSize) -> Bool {
        switch type {
        case .radio:
            guard size.width > 0 else { return false }
            let count = max(1, segmentCount)
            // Which segment the pointer is over, clamped: a click on the very
            // right edge divides out to `count` exactly, one past the last.
            let index = min(count - 1, max(0, Int(point.x / (size.width / CGFloat(count)))))
            guard selected != index + 1 else { return false }
            selected = index + 1
            return true

        case .checkbox:
            checked.toggle()
            return true

        case .combobox:
            // Steps to the next entry, wrapping.
            //
            // **The fallback, not the usual path.** On the canvas a click
            // opens the real list (see ComboBoxView); this is what stepping
            // means for anyone who has no view to put a popup over, which is
            // every headless caller including the tests.
            let count = max(1, ValueList.entryCount(values))
            selected = (max(1, selected) % count) + 1
            return true

        // Everything else is dragged, grabbed, or not operable at all -
        // see LiveProperty and ControlOperation.isGrabbable.
        case .knob, .slider, .ad, .adsr, .mseg, .xyPad, .xyQuad,
             .header, .label, .led, .status, .monitor,
             .random, .sendAll, .panic, .midiPlayer:
            return false
        }
    }

    // ── Envelopes ────────────────────────────────────────────────────────

    /// Which handle is under `point`, as an index into `envelopeHandles`, or
    /// nil for none within reach.
    ///
    /// Nearest wins rather than first: two corners can overlap when a stage is
    /// set to no time at all, and grabbing the one you are actually pointing at
    /// matters more than a stable order.
    func nodeIndex(at point: CGPoint, plot: CGRect) -> Int? {
        let nodes = envelopeNodes(self, plot: plot)
        var best: Int?
        var bestDistance = ControlOperation.nodeGrabDistance
        for (index, handle) in envelopeHandles(self).enumerated() {
            guard handle.point < nodes.count else { continue }
            let distance = nodes[handle.point].distance(to: point)
            if distance <= bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Moves one corner of the curve to where the pointer is, and says whether
    /// anything changed.
    ///
    /// To the pointer, not by however far it travelled: a curve is read by
    /// looking at it, so the corner should be under the finger rather than
    /// somewhere an accumulated delta has carried it.
    ///
    /// A stage's time is the length of the run *into* its corner, so what the
    /// pointer's x gives is the corner's place on the axis and the stage's own
    /// time is that minus where the previous corner sits. Clamped at that
    /// previous corner: dragging one leftward past its neighbour would give the
    /// stage a negative length, and a curve that runs backwards is not a curve.
    mutating func dragNode(_ handle: Int, to point: CGPoint, plot: CGRect) -> Bool {
        let handles = envelopeHandles(self)
        guard handles.indices.contains(handle) else { return false }
        let (pointIndex, timeRow, levelRow) = handles[handle]
        let (points, _) = envelopePoints(self)
        guard pointIndex < points.count, pointIndex > 0,
              parameters.indices.contains(timeRow) else { return false }

        let (time, level) = envelopeAt(self, plot: plot, point: point)
        let span = min(max(time - points[pointIndex - 1].t, 0), envelopeStageSpan)
        let ceiling = valueCeiling
        let wantedTime = min(max(Int((span / envelopeStageSpan * CGFloat(ceiling)).rounded()), 0), ceiling)

        var moved = false
        if parameters[timeRow].value != wantedTime {
            parameters[timeRow].value = wantedTime
            moved = true
        }
        if let levelRow, parameters.indices.contains(levelRow) {
            let wantedLevel = min(max(Int((level * CGFloat(ceiling)).rounded()), 0), ceiling)
            if parameters[levelRow].value != wantedLevel {
                parameters[levelRow].value = wantedLevel
                moved = true
            }
        }
        return moved
    }

    // ── Pads ─────────────────────────────────────────────────────────────

    /// Which of a pad's points is nearest the pointer.
    ///
    /// Always answers, unlike `nodeIndex`: a pad's field has no empty area to
    /// miss - every position belongs to whichever point is closer.
    func padPointIndex(at point: CGPoint, plot: CGRect) -> Int {
        var best = 0
        var bestDistance: CGFloat?
        for (index, pair) in padPoints(self).enumerated() {
            guard let node = padNode(self, plot: plot, point: pair) else { continue }
            let distance = node.distance(to: point)
            if bestDistance == nil || distance < bestDistance! {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// Puts one of a pad's points where the pointer is, and says which of its
    /// two rows that changed.
    ///
    /// Reports rather than assumes: sliding along one axis leaves the other
    /// alone, and sending an unchanged value would be one message per mouse
    /// move saying nothing.
    ///
    /// An inverted axis sends the opposite of where the point sits, so the drag
    /// itself still feels ordinary - `padNode` mirrors the same flag back the
    /// other way to put the point where it was dropped.
    mutating func dragPad(_ index: Int, to point: CGPoint, plot: CGRect) -> Bool {
        let pairs = padPoints(self)
        guard pairs.indices.contains(index), plot.width > 0, plot.height > 0 else { return false }
        let pair = pairs[index]
        let ceiling = valueCeiling

        let xFraction = min(max((point.x - plot.minX) / plot.width, 0), 1)
        // Up is more, so the vertical fraction is measured from the bottom.
        let yFraction = min(max((plot.maxY - point.y) / plot.height, 0), 1)

        var moved = false
        for (row, fraction) in [(pair.x, xFraction), (pair.y, yFraction)] {
            guard parameters.indices.contains(row) else { continue }
            var wanted = min(max(Int((fraction * CGFloat(ceiling)).rounded()), 0), ceiling)
            if parameters[row].inverted { wanted = ceiling - wanted }
            if parameters[row].value != wanted {
                parameters[row].value = wanted
                moved = true
            }
        }
        return moved
    }

    /// The stepped half of `dragContinuous`, for a control whose value list is
    /// in force.
    ///
    /// Measured from the start of the gesture, exactly as the continuous one
    /// is and for the same reason: an accumulated delta drifts, and a slow
    /// drag up and back down should return to the entry it began on. What is
    /// stored is still the entry's own `number` - the index is how far the
    /// hand has moved, never what goes on the wire.
    private mutating func dragEntries(from startValue: Int, by dy: CGFloat, fine: Bool) -> Bool {
        let entries = orderedValues
        let steps = entries.count - 1
        guard steps > 0 else { return false }
        // The index the gesture began on, found from the value it began with -
        // not from where the control is now, which a previous move may have
        // shifted.
        var startIndex = entries.firstIndex { $0.number == startValue }
        if startIndex == nil {
            startIndex = entries.indices.min {
                abs(entries[$0].number - startValue) < abs(entries[$1].number - startValue)
            }
        }
        let reach = ControlOperation.dragRange * (fine ? ControlOperation.fineDragFactor : 1)
        let moved = (startIndex ?? 0) + Int((dy * CGFloat(steps) / reach).rounded())
        let wanted = entries[min(max(moved, 0), steps)].number
        guard parameters[0].value != wanted else { return false }
        parameters[0].value = wanted
        return true
    }

    /// Picks entry `index` (0-based) outright - what a dropdown reports back.
    ///
    /// Clamped to the entry count rather than to the list's length, the same
    /// way the drawing clamps: a shortened list leaves Selected pointing past
    /// the end, and lengthening it again should restore the old pick.
    mutating func choose(entry index: Int) -> Bool {
        let chosen = min(max(1, index + 1), max(1, ValueList.entryCount(values)))
        guard selected != chosen else { return false }
        selected = chosen
        return true
    }

    /// Puts a bipolar control back on its zero, and says whether it moved.
    ///
    /// Only a bipolar one has a zero to go back to: on a control running 0
    /// upward there is no value the gesture obviously means, and landing on
    /// the low end would be a reset rather than a return to the middle.
    ///
    /// The middle of its own bounds, from the same function the readout
    /// centres on - so the value this lands on is exactly the one the control
    /// then shows as 0, whatever its ceiling is. Snapped to the value list
    /// for the same reason a drag is.
    mutating func recentre() -> Bool {
        guard bipolar, ControlOperation.isContinuous(type), !parameters.isEmpty else { return false }
        // With a list in force the middle is the middle *stop*: the entry
        // nearest the numeric centre can be anywhere once the numbers run out
        // of order, which is exactly the case this list exists for.
        let wanted: Int
        if valueListActive {
            let entries = orderedValues
            wanted = entries[entries.count / 2].number
        } else {
            wanted = snappedToValues(centerValue(valueRange))
        }
        guard parameters[0].value != wanted else { return false }
        parameters[0].value = wanted
        return true
    }
}
