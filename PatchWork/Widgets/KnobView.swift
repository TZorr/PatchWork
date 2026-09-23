//
//  KnobView.swift
//  PatchWork
//
//  Knob dial, drawn from the element's own value: an unfilled track for the
//  full travel, an accent arc over it for how much is used, a body disc with
//  the raw number in the middle, and a 90° gap at the bottom - the track
//  sweeps 270° rather than a full circle, so where it starts and ends can be
//  told apart.
//
//  Card chrome only, unlike Status/Monitor's header-and-groups treatment:
//  at the default 80x80 there is nothing to group, and a header bar would
//  shrink the dial itself, the one thing this widget is for.
//

import SwiftUI

struct KnobView: View {
    let name: String
    var value: Int = 64
    /// The element's own value domain - 0...127 at 7 bits, 0...16383 at 14,
    /// or a narrower custom range (CanvasElement.valueRange).
    var floor: Int = 0
    var ceiling: Int = 127
    var bipolar: Bool = false
    /// Where the control sits on its travel, 0...1, when the caller has
    /// already worked it out. Nil means derive it from `value` as before.
    ///
    /// Handed in for a value list, whose stops are positions rather than
    /// numbers - see CanvasElement.displayFraction.
    var fractionOverride: CGFloat? = nil
    /// What to print instead of the number. Nil keeps the reading.
    ///
    /// **Not fitted to the width.** The number shrinks to fit because a
    /// reading with a digit missing is a different number; a name that is too
    /// long is just a name that is too long, and shrinking it would make every
    /// control on a panel a different size. Choosing short ones is the panel
    /// author's business.
    var readoutOverride: String? = nil
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    private var fraction: CGFloat {
        fractionOverride ?? valueFraction(value, floor: floor, ceiling: ceiling)
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
        let margin: CGFloat = 6
        let arcWidth: CGFloat = 4
        let diameter = min(size.width, size.height) - margin * 2
        guard diameter > 0 else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = diameter / 2 - arcWidth / 2

        // Degrees measured clockwise from 3 o'clock (screen coordinates,
        // y down) - 135 to 405 sweeps lower-left, over the top, to
        // lower-right, leaving a 90° gap centered on 6 o'clock. Built as an
        // explicit polyline rather than Path.addArc so the sweep direction
        // is unambiguous regardless of that API's clockwise-flag semantics.
        let trackStart = 135.0
        let trackSweep = 270.0

        context.stroke(
            arcPath(center: center, radius: radius, startDegrees: trackStart, endDegrees: trackStart + trackSweep),
            with: .color(.secondary.opacity(0.25)),
            style: StrokeStyle(lineWidth: arcWidth, lineCap: .round)
        )

        // Bipolar fills from the middle of the travel toward the value
        // rather than from the low end up - what a pan or tune control
        // wants. Exactly at the midpoint the span is 0 and nothing fills,
        // which is the sign handling itself.
        let fillStart = bipolar ? trackStart + trackSweep / 2 : trackStart
        let fillEnd = bipolar
            ? trackStart + trackSweep / 2 + trackSweep * (fraction - 0.5)
            : trackStart + trackSweep * fraction
        context.stroke(
            arcPath(center: center, radius: radius, startDegrees: fillStart, endDegrees: fillEnd),
            with: .color(accentColor),
            style: StrokeStyle(lineWidth: arcWidth, lineCap: .round)
        )

        let bodyRadius = radius - arcWidth
        guard bodyRadius > 0 else { return }
        let face = Path(ellipseIn: CGRect(x: center.x - bodyRadius, y: center.y - bodyRadius, width: bodyRadius * 2, height: bodyRadius * 2))
        context.fill(face, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(face, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)

        // Drawn at the centre - `at:` centres on the point by default,
        // where `in:` positions within a rectangle and does not.
        //
        // Fitted rather than clipped: a 14-bit reading is five digits
        // where a 7-bit one is three, and a value with its last digit cut
        // off reads as a different value. So the font steps down until the
        // text fits instead of letting the disc crop it.
        // A name is drawn at its own size and allowed to be cropped - see
        // readoutOverride. Only the number is fitted.
        if let caption = readoutOverride {
            var text = context.resolve(Text(caption).font(.system(size: 11, weight: .medium)))
            text.shading = .foreground
            context.draw(text, at: center)
        } else {
            let readout = valueReadout(value, bipolar: bipolar, floor: floor, ceiling: ceiling)
            context.draw(fittedText(readout, in: context, maxWidth: bodyRadius * 2 - 4), at: center)
        }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, startDegrees: Double, endDegrees: Double) -> Path {
        var path = Path()
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let radians = (startDegrees + (endDegrees - startDegrees) * t) * .pi / 180
            let point = CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

#Preview {
    HStack {
        KnobView(name: "Knob", value: 20)
        KnobView(name: "Knob", value: 12000, ceiling: 16383, isSelected: true)
    }
    .frame(width: 80, height: 80)
    .padding()
}
