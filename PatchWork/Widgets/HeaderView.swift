//
//  HeaderView.swift
//  PatchWork
//
//  Section heading, filled or bare, editable in Inspector.
//
//  Filled means a lightly tinted accent plate that starts a section; bare
//  means a
//  hairline along the bottom that separates within one, without claiming
//  to start anything.
//
//  The name is the heading text itself, centred - not a caption
//  underneath, unlike every other per-type widget. No card background
//  either: a heading has no generic plate look of its own to layer a
//  second one under, and doubling up the box would just look cluttered.
//
//  A fresh header is filled.
//
//  A light border now runs around it always, the same secondary-opacity
//  one every card uses at rest - filled or bare still picks the fill
//  underneath it, untouched.
//

import SwiftUI

struct HeaderView: View {
    let name: String
    var filled: Bool = true
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        ZStack {
            if filled {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accentColor.opacity(0.15))
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(height: 1)
                }
            }

            // Centered, and only here: a heading spans its section and
            // sits over the middle of it, where a label (a caption beside
            // something) takes whatever alignment its own property asks
            // for instead.
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
}

#Preview {
    VStack {
        HeaderView(name: "Oscillators")
        HeaderView(name: "Oscillators", filled: false, isSelected: true)
    }
    .frame(width: 200, height: 28)
    .padding()
}
