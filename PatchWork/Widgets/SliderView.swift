//
//  SliderView.swift
//  PatchWork
//
//  Vertical fader, drawn from the same value field KnobView reads: value
//  readout above the travel (not on the thumb, which
//  would push it near either end past the element's own bounds), a thin
//  track filled from the bottom up to the thumb, and a ring-style thumb
//  matching the knob's two-tone look so the two controls read as one
//  family.
//

import SwiftUI

struct SliderView: View {
    let name: String
    var value: Int = 64
    /// Readout only, unlike the knob's arc: a fader fills from the bottom
    /// whatever this says, because it reads as "how much" regardless of
    /// what its numbers mean.
    var bipolar: Bool = false
    /// The element's own value domain - 0...127 at 7 bits, 0...16383 at 14,
    /// or a narrower custom range (CanvasElement.valueRange).
    var floor: Int = 0
    var ceiling: Int = 127
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
            Text(readoutOverride ?? valueReadout(value, bipolar: bipolar,
                                                 floor: floor, ceiling: ceiling))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary)
                // Five digits at 14 bits, on an element that can be 56pt
                // wide - shrink rather than clip, since a reading with a
                // digit missing is a different number. A name gets no such
                // treatment: see readoutOverride.
                .lineLimit(1)
                .minimumScaleFactor(readoutOverride == nil ? 0.6 : 1)
                .padding(.horizontal, 2)
                .padding(.top, 4)

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
        let trackWidth: CGFloat = 4
        let thumbMinDiameter: CGFloat = 12
        let thumbMaxDiameter: CGFloat = 20
        let thumbRingWidth: CGFloat = 2.5
        let margin: CGFloat = 4

        let travel = CGRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2)
        guard travel.width > 0, travel.height > 0 else { return }

        // The thumb's diameter comes from the element's *width*, not its
        // height - a narrow slider gets a narrow thumb - then the travel
        // it rides is inset by that same radius at both ends, or a round
        // thumb centered at either extreme would overhang the element.
        let thumbDiameter = min(max(thumbMinDiameter, travel.width - 4), thumbMaxDiameter)
        let radius = thumbDiameter / 2
        guard travel.height > thumbDiameter else { return }

        let centerX = travel.midX
        let topY = travel.minY + radius
        let bottomY = travel.maxY - radius
        let thumbY = bottomY - (bottomY - topY) * fraction

        let track = CGRect(x: centerX - trackWidth / 2, y: topY, width: trackWidth, height: bottomY - topY)
        context.fill(Path(roundedRect: track, cornerRadius: trackWidth / 2), with: .color(.secondary.opacity(0.25)))

        // Filled from the bottom up - a fader reads as "how much", so the
        // accent grows out of the low end regardless of what that end
        // means numerically.
        var filled = track
        filled.origin.y = thumbY
        filled.size.height = track.maxY - thumbY
        context.fill(Path(roundedRect: filled, cornerRadius: trackWidth / 2), with: .color(accentColor))

        let thumbCenter = CGPoint(x: centerX, y: thumbY)
        let thumbRadius = radius - thumbRingWidth / 2
        let thumbPath = Path(ellipseIn: CGRect(
            x: thumbCenter.x - thumbRadius, y: thumbCenter.y - thumbRadius,
            width: thumbRadius * 2, height: thumbRadius * 2
        ))
        context.fill(thumbPath, with: .color(Color(nsColor: .controlBackgroundColor)))
        context.stroke(thumbPath, with: .color(accentColor), lineWidth: thumbRingWidth)
    }
}

#Preview {
    HStack {
        SliderView(name: "Slider", value: 20)
        SliderView(name: "Slider", value: 12000, ceiling: 16383, isSelected: true)
    }
    .frame(width: 56, height: 160)
    .padding()
}
