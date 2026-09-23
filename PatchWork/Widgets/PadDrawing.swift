//
//  PadDrawing.swift
//  PatchWork
//
//  Drawing shared by XYPadView and XYPadQuadView: one ruled field and one
//  point routine that both call, rather than each drawing its own from
//  scratch.
//

import SwiftUI

/// A pad's field and the gesture that moves its point, wrapped around whatever
/// readout the pad draws over it.
///
/// The gesture is on the *canvas* rather than on the element for the same reason
/// the envelope's is (see EnvelopeView): the plot is inset inside the canvas and
/// the canvas sits above a name strip, so a position taken from the element's
/// bounds would be off by that strip's height.
struct PadSurface: View {
    let element: CanvasElement
    let active: Bool
    let onOperate: ((inout CanvasElement) -> Bool) -> Void
    /// Everything drawn over the field - the readouts and the points.
    let content: (inout GraphicsContext, CGRect) -> Void

    /// Which point this gesture took hold of, for as long as it lasts.
    ///
    /// A single-point pad has nothing to choose, so a press anywhere is that
    /// point. A pad with two needs the envelope's grab-and-hold model instead,
    /// or a fast drag would jump to whichever point was nearer the moment the
    /// pointer crossed between them.
    @State private var grabbed: Int?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plot = padPlot(in: size)
                guard plot.width > 0, plot.height > 0 else { return }
                drawPadField(in: &context, plot: plot)
                content(&context, plot)
            }
            .contentShape(Rectangle())
            .gesture(dragPoint(in: proxy.size), including: active ? .all : .subviews)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dragPoint(in size: CGSize) -> some Gesture {
        let plot = padPlot(in: size)
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if grabbed == nil {
                    // A pad always answers: its field has no empty area to
                    // miss, so a click anywhere puts the nearest point there -
                    // which is what a pad is for.
                    grabbed = element.padPointIndex(at: value.startLocation, plot: plot)
                }
                guard let point = grabbed else { return }
                onOperate { $0.dragPad(point, to: value.location, plot: plot) }
            }
            .onEnded { _ in grabbed = nil }
    }
}

/// The area a pad's point(s) move in, inside a view of `size`.
func padPlot(in size: CGSize, padding: CGFloat = 8) -> CGRect {
    CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
}

/// The ruled field and its frame - draw_xy's and draw_xy_quad's shared top
/// half. 8 faint divisions say where you are; the frame says where the
/// limits are, which a grid of identical lines does not say on its own.
func drawPadField(in context: inout GraphicsContext, plot: CGRect, divisions: Int = 8) {
    var grid = Path()
    for step in 1..<divisions {
        let fraction = CGFloat(step) / CGFloat(divisions)
        let x = plot.minX + fraction * plot.width
        let y = plot.minY + fraction * plot.height
        grid.move(to: CGPoint(x: x, y: plot.minY))
        grid.addLine(to: CGPoint(x: x, y: plot.maxY))
        grid.move(to: CGPoint(x: plot.minX, y: y))
        grid.addLine(to: CGPoint(x: plot.maxX, y: y))
    }
    context.stroke(grid, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
    context.stroke(Path(plot), with: .color(.secondary.opacity(0.3)), lineWidth: 1.2)
}

/// One point's dashed crosshair, soft glow and ringed dot - drawn in that
/// order so each layer stays subordinate to what's drawn over it, the
/// crosshair reading the point's position out rather than competing with
/// it.
func drawPadPoint(in context: inout GraphicsContext, plot: CGRect, point: CGPoint, color: Color) {
    var crosshair = Path()
    crosshair.move(to: CGPoint(x: plot.minX, y: point.y))
    crosshair.addLine(to: CGPoint(x: plot.maxX, y: point.y))
    crosshair.move(to: CGPoint(x: point.x, y: plot.minY))
    crosshair.addLine(to: CGPoint(x: point.x, y: plot.maxY))
    context.stroke(crosshair, with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))

    let glowRadius: CGFloat = 11
    context.fill(
        Path(ellipseIn: CGRect(x: point.x - glowRadius, y: point.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
        with: .radialGradient(
            Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
            center: point, startRadius: 0, endRadius: glowRadius
        )
    )

    let dotRadius: CGFloat = 5
    let dot = Path(ellipseIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    context.fill(dot, with: .color(color))
    context.stroke(dot, with: .color(Color(nsColor: .controlBackgroundColor)), lineWidth: 2)
}

/// Which rows each of a pad's points reads - X first, then Y.
///
/// Inversion is a property of the parameter itself rather than a pair of
/// per-point flags kept alongside, so a point is just its two rows and each
/// row brings its own flag. Shared with
/// the hit test for the same reason the envelope's handles are: the dot that is
/// drawn and the point that can be grabbed must be one statement.
func padPoints(_ element: CanvasElement) -> [(x: Int, y: Int)] {
    switch element.type {
    case .xyPad: [(0, 1)]
    case .xyQuad: [(0, 1), (2, 3)]
    default: []
    }
}

/// Where one of a pad's points sits inside `plot`, or nil for an empty plot.
///
/// Mirrored back against the same flag a drag sent the raw value through, so an
/// inverted axis still shows its point where it was dropped rather than where
/// the number alone would put it.
func padNode(_ element: CanvasElement, plot: CGRect, point: (x: Int, y: Int)) -> CGPoint? {
    guard plot.width > 0, plot.height > 0 else { return nil }
    let ceiling = element.valueCeiling
    var xFraction = valueFraction(element.parameterValue(point.x), ceiling: ceiling)
    var yFraction = valueFraction(element.parameterValue(point.y), ceiling: ceiling)
    if element.isAxisInverted(point.x) { xFraction = 1 - xFraction }
    if element.isAxisInverted(point.y) { yFraction = 1 - yFraction }
    return padPoint(xFraction: xFraction, yFraction: yFraction, in: plot)
}

/// A point's screen position in `plot`, given its value fractions.
/// Up is more, so y is inverted against the screen's own direction.
func padPoint(xFraction: CGFloat, yFraction: CGFloat, in plot: CGRect) -> CGPoint {
    CGPoint(
        x: plot.minX + xFraction * plot.width,
        y: plot.maxY - yFraction * plot.height
    )
}
