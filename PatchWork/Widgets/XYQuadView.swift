//
//  XYQuadView.swift
//  PatchWork
//
//  Two-point XY pad - no dragging either point yet, but all four axis
//  values are real, editable as the X1/Y1/X2/Y2 rows of the Inspector's
//  parameter table.
//
//  Same ruled field as XYPadView (drawPadField/drawPadPoint, shared - see
//  PadDrawing.swift), twice the point, so two axes can be swept against
//  each other. Each point gets its own numbered, coloured readout line -
//  numbered as well as coloured, so which line belongs to which point
//  still reads in greyscale.
//
//  A fresh quad starts at (40, 40) and (88, 88) - off-centre and apart
//  rather than both centred like a plain pad's (64, 64): centred, the two
//  points would start stacked on each other and neither could be told
//  apart.
//

import SwiftUI

struct XYQuadView: View {
    let element: CanvasElement
    var isSelected: Bool = false
    var active: Bool = false
    var onOperate: ((inout CanvasElement) -> Bool) -> Void = { _ in }

    @Environment(\.appAccentColor) private var accentColor

    /// Point 1 in the accent, point 2 in the label color - scheme-adaptive
    /// rather than a literal white, which would read as white-on-white in
    /// Light Mode. Indexed
    /// modulo the list so a pad with more points than colours cannot walk
    /// off the end.
    private var colors: [Color] { [accentColor, Color(nsColor: .labelColor)] }

    var body: some View {
        VStack(spacing: 2) {
            PadSurface(element: element, active: active, onOperate: onOperate) { context, plot in
                let pairs = padPoints(element)
                let lineHeight: CGFloat = 13

                // All readout lines first, then all points - a point can land
                // anywhere including its own readout's corner, and it is the
                // reading, so the numbers are the check on it and go underneath.
                for (index, pair) in pairs.enumerated() {
                    // Fitted like the plain pad's, for the same reason: two
                    // 14-bit numbers and a line number do not fit a narrow
                    // field at full size.
                    let text = "\(index + 1)  \(element.parameterValue(pair.x)) · \(element.parameterValue(pair.y))"
                    context.draw(
                        fittedText(
                            text, in: context,
                            maxWidth: plot.width - 6, color: colors[index % colors.count],
                            largest: 9, smallest: 6
                        ),
                        at: CGPoint(x: plot.minX + 3, y: plot.minY + 1 + CGFloat(index) * lineHeight),
                        anchor: .topLeading
                    )
                }

                for (index, pair) in pairs.enumerated() {
                    guard let point = padNode(element, plot: plot, point: pair) else { continue }
                    drawPadPoint(in: &context, plot: plot, point: point, color: colors[index % colors.count])
                }
            }

            Text(element.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .cardChrome(isSelected: isSelected)
    }
}

#Preview {
    HStack {
        XYQuadView(element: CanvasElement(type: .xyQuad, rect: CGRect(x: 0, y: 0, width: 200, height: 220)))
        XYQuadView(element: CanvasElement(type: .xyQuad, rect: CGRect(x: 0, y: 0, width: 200, height: 220)), isSelected: true)
    }
    .frame(width: 420, height: 220)
    .padding()
}
