//
//  XYPadView.swift
//  PatchWork
//
//  XY pad. Both axis values are editable as the X and Y rows of the
//  Inspector's parameter table.
//
//  A ruled field with a frame (drawPadField, shared with XYQuadView - see
//  PadDrawing.swift), a raw-value readout in the top-left corner, and the point itself (drawPadPoint, also
//  shared) as a dashed crosshair plus a soft glow plus a ringed dot - in
//  that draw order, since each layer has to stay subordinate to the one
//  on top of it.
//
//  A fresh pad starts centred on both axes - (64, 64).
//

import SwiftUI

struct XYPadView: View {
    let element: CanvasElement
    var isSelected: Bool = false
    var active: Bool = false
    var onOperate: ((inout CanvasElement) -> Bool) -> Void = { _ in }

    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        VStack(spacing: 2) {
            PadSurface(element: element, active: active, onOperate: onOperate) { context, plot in
                // Raw values, drawn before the point - the point can land
                // anywhere including this corner, and it is the reading, so the
                // numbers are the check on it and go underneath.
                //
                // Fitted to the field's width: at 14 bits this pair runs to
                // "16383 · 16383", which no longer fits a narrow pad at full
                // size.
                context.draw(
                    fittedText(
                        "\(element.parameterValue(0)) · \(element.parameterValue(1))",
                        in: context,
                        maxWidth: plot.width - 6, color: .secondary, largest: 9, smallest: 6
                    ),
                    at: CGPoint(x: plot.minX + 3, y: plot.minY + 2),
                    anchor: .topLeading
                )
                if let point = padNode(element, plot: plot, point: (x: 0, y: 1)) {
                    drawPadPoint(in: &context, plot: plot, point: point, color: accentColor)
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
    var moved = CanvasElement(type: .xyPad, rect: CGRect(x: 0, y: 0, width: 160, height: 176))
    moved.parameters[0].value = 20
    moved.parameters[1].value = 100
    moved.parameters[1].inverted = true
    return HStack {
        XYPadView(element: CanvasElement(type: .xyPad, rect: CGRect(x: 0, y: 0, width: 160, height: 176)))
        XYPadView(element: moved, isSelected: true)
    }
    .frame(width: 340, height: 176)
    .padding()
}
