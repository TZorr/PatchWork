//
//  CheckboxView.swift
//  PatchWork
//
//  Checkbox. The one control that breaks every other widget's
//  bottom-name-strip convention, on purpose: the box is small and
//  square, so a caption centered under it would sit under a lot of
//  nothing and make a row of checkboxes twice as tall as it needs to be -
//  the name goes beside it instead, vertically centered across the whole
//  element.
//
//  The tick follows the element's own `checked` property, editable in
//  Inspector and toggled by a click in active mode. The value a checkbox
//  sends is derived from it rather than stored - see
//  ElementMessages.sentValue - which means the parameter's Value column is
//  not what a checkbox actually transmits.
//

import SwiftUI

struct CheckboxView: View {
    let name: String
    var checked: Bool = false
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    private let boxSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 9) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: boxSize, height: boxSize)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .cardChrome(isSelected: isSelected)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let box = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)

        if checked {
            context.fill(box, with: .color(accentColor))
            // Same dark-on-accent reading the radio strip's selected
            // segment uses, rather than a plain white tick.
            var tick = Path()
            tick.move(to: CGPoint(x: size.width * 0.27, y: size.height * 0.53))
            tick.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.70))
            tick.addLine(to: CGPoint(x: size.width * 0.75, y: size.height * 0.32))
            context.stroke(tick, with: .color(Color(nsColor: .controlBackgroundColor)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        } else {
            context.fill(box, with: .color(Color(nsColor: .controlBackgroundColor)))
            context.stroke(box, with: .color(.secondary.opacity(0.35)), lineWidth: 1.5)
        }
    }
}

#Preview {
    HStack {
        CheckboxView(name: "Checkbox")
        CheckboxView(name: "Checkbox", checked: true, isSelected: true)
    }
    .frame(width: 120, height: 32)
    .padding()
}
