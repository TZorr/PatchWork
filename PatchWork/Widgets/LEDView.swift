//
//  LEDView.swift
//  PatchWork
//
//  The input lamp, lit by arriving MIDI. A rounded lamp shape that keeps its
//  place whether lit or dark, a soft glow behind it only when lit.
//
//  Whether it is lit is passed in rather than timed here: the flash belongs
//  to the arriving stream, not to this element, and every LED on a panel is
//  watching the same input. MIDIActivity owns that timer so two lamps
//  cannot disagree about it.
//

import SwiftUI

struct LEDView: View {
    let name: String
    /// Whether input arrived within the flash window. See MIDIActivity.
    var lit: Bool = false
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

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
        let margin: CGFloat = 4
        let lamp = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        guard lamp.width > 0, lamp.height > 0 else { return }

        if lit {
            let glowRadius = max(lamp.width, lamp.height) / 2
            let center = CGPoint(x: lamp.midX, y: lamp.midY)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                with: .radialGradient(
                    Gradient(colors: [accentColor.opacity(0.47), accentColor.opacity(0)]),
                    center: center, startRadius: 0, endRadius: glowRadius
                )
            )
        }

        let lampPath = Path(roundedRect: lamp, cornerRadius: 6)
        context.fill(lampPath, with: .color(lit ? accentColor : Color(nsColor: .controlBackgroundColor)))
        context.stroke(lampPath, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)
    }
}

#Preview {
    HStack {
        LEDView(name: "LED")
        LEDView(name: "LED", lit: true)
        LEDView(name: "LED", lit: true, isSelected: true)
    }
    .frame(width: 96, height: 40)
    .padding()
}
