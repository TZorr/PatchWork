//
//  EnvelopeDrawing.swift
//  PatchWork
//
//  Shared envelope-curve drawing: one routine paints ADSR, AD and MSEG
//  alike, and only the shape-specific point list differs per type.
//

import SwiftUI

// The axis convention, shared by all three envelope shapes: attack, decay and
// release each span up to two units and a held segment a fixed one, so the
// curve's horizontal extent means the same thing across two elements instead
// of rescaling to whichever stage happens to be longest.
let envelopeStageSpan: CGFloat = 2
let envelopeHoldSpan: CGFloat = 1
private let envelopePad: CGFloat = 6

/// The area a curve is drawn in, inside a canvas of `size`.
///
/// Public because operating an envelope means hitting its nodes, and a
/// second copy of this
/// arithmetic would be free to disagree with the one that draws them - which
/// is the one thing a hit test must never do.
func envelopePlot(in size: CGSize) -> CGRect {
    CGRect(origin: .zero, size: size).insetBy(dx: envelopePad, dy: envelopePad)
}

/// The envelope's (time, level) corners plus the length of its axis.
///
/// All three shapes reduce to a polyline, which is why one function draws them
/// all and only this one builds the shape. ADSR runs up to the peak, down to
/// the sustain level, holds there, then falls; AD has no held segment at all -
/// up and straight back down, the one-shot shape; an MSEG has no named stages,
/// just N nodes, each one's time being the length of the run into it.
func envelopePoints(_ element: CanvasElement) -> (points: [(t: CGFloat, level: CGFloat)], axis: CGFloat) {
    let ceiling = element.valueCeiling
    /// One row's value as a fraction of its own domain.
    func unit(_ index: Int) -> CGFloat {
        valueFraction(element.parameterValue(index), ceiling: ceiling)
    }

    switch element.type {
    case .mseg:
        var points: [(t: CGFloat, level: CGFloat)] = [(0, 0)]
        var elapsed: CGFloat = 0
        // Ceiling, not floor: in Release mode the row count is odd, one short
        // for the last node's level - which `unit` already answers as 0 past
        // the end, the same release-to-zero ADSR gets from a hardcoded one.
        let nodes = (element.parameters.count + 1) / 2
        for node in 0..<max(0, nodes) {
            elapsed += unit(node * 2) * envelopeStageSpan
            points.append((elapsed, min(max(unit(node * 2 + 1), 0), 1)))
        }
        return (points, CGFloat(max(1, nodes)) * envelopeStageSpan)

    case .adsr:
        let attack = unit(0) * envelopeStageSpan
        let decay = unit(1) * envelopeStageSpan
        let sustain = unit(2)
        let release = unit(3) * envelopeStageSpan
        let t1 = attack, t2 = attack + decay
        let t3 = t2 + envelopeHoldSpan
        let axis = 3 * envelopeStageSpan + envelopeHoldSpan
        return ([(0, 0), (t1, 1), (t2, sustain), (t3, sustain), (t3 + release, 0)], axis)

    default:
        // AD. Releasing the key during the attack drops onto the decay slope
        // from wherever it had got to, which is the device's business rather
        // than that of a curve drawn at rest.
        let attack = unit(0) * envelopeStageSpan
        let decay = unit(1) * envelopeStageSpan
        return ([(0, 0), (attack, 1), (attack + decay, 0)], 2 * envelopeStageSpan)
    }
}

/// Every grabbable corner: which point it is, which row is its time, and which
/// is its level - or nil where there is none.
///
/// Not every corner is a handle. ADSR's held segment ends follow entirely from
/// the sustain level and the hold's fixed width, and both envelopes' final
/// corners land at zero by definition, so neither has a level to carry.
///
/// An MSEG's are generated from its own rows - two per node - which is the
/// whole difference between it and the fixed shapes. In Release mode the last
/// node has no level row, and that falls out of the row count being odd rather
/// than being named.
func envelopeHandles(_ element: CanvasElement) -> [(point: Int, timeRow: Int, levelRow: Int?)] {
    switch element.type {
    case .ad:
        return [(1, 0, nil), (2, 1, nil)]
    case .adsr:
        return [(1, 0, nil), (2, 1, 2), (4, 3, nil)]
    case .mseg:
        let total = element.parameters.count
        let nodes = (total + 1) / 2
        return (0..<max(0, nodes)).map { node in
            (node + 1, node * 2, node * 2 + 1 < total ? node * 2 + 1 : nil)
        }
    default:
        return []
    }
}

/// Every corner of the curve in the plot's coordinates, origin first.
///
/// Shared by the drawing and by the hit test, for the reason above: the dot
/// that is drawn and the point that can be grabbed cannot disagree.
func envelopeNodes(_ element: CanvasElement, plot: CGRect) -> [CGPoint] {
    guard plot.width > 0, plot.height > 0 else { return [] }
    let (points, axis) = envelopePoints(element)
    guard axis > 0 else { return [] }
    return points.map { point in
        CGPoint(
            x: plot.minX + (point.t / axis) * plot.width,
            y: plot.maxY - point.level * plot.height
        )
    }
}

/// A point in the plot read back as (time along the axis, level 0...1).
///
/// The inverse of `envelopeNodes`, and the reason a node can be dragged to
/// where the pointer *is* rather than by however far it has moved.
func envelopeAt(_ element: CanvasElement, plot: CGRect, point: CGPoint) -> (time: CGFloat, level: CGFloat) {
    guard plot.width > 0, plot.height > 0 else { return (0, 0) }
    let (_, axis) = envelopePoints(element)
    let time = (point.x - plot.minX) / plot.width * axis
    let level = (plot.maxY - point.y) / plot.height
    return (max(0, time), min(max(level, 0), 1))
}

/// Baseline, area-under-curve gradient, polyline and handle dots for an
/// envelope shape already reduced to (time, level) points on a 0...axis /
/// 0...1 domain. `handleIndices` are which corners get a dot - not every
/// corner is draggable (a held segment's own corners follow entirely from
/// other values), so not every corner should look like it is.
func drawEnvelope(in context: inout GraphicsContext, size: CGSize, element: CanvasElement, accentColor: Color) {
    let plot = envelopePlot(in: size)
    let points = envelopeNodes(element, plot: plot)
    // Which corners get a dot: the handles and only the handles - a corner
    // that follows from other values should not look like one you can take
    // hold of.
    let handleIndices = envelopeHandles(element).map(\.point)
    guard let first = points.first else { return }

    var baseline = Path()
    baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
    baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
    context.stroke(baseline, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

    var area = Path()
    area.move(to: first)
    for point in points.dropFirst() { area.addLine(to: point) }
    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: plot.maxY))
    area.closeSubpath()
    context.fill(
        area,
        with: .linearGradient(
            Gradient(colors: [accentColor.opacity(0.35), accentColor.opacity(0)]),
            startPoint: CGPoint(x: plot.midX, y: plot.minY),
            endPoint: CGPoint(x: plot.midX, y: plot.maxY)
        )
    )

    var curve = Path()
    curve.move(to: first)
    for point in points.dropFirst() { curve.addLine(to: point) }
    context.stroke(
        curve,
        with: .color(accentColor),
        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    )

    // A dot per *handle*, not per corner - see the handleIndices doc above.
    for index in handleIndices where index < points.count {
        let center = points[index]
        let radius: CGFloat = 2.5
        let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(dot, with: .color(accentColor))
    }
}
