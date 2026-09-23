//
//  ActionButtonView.swift
//  PatchWork
//
//  An action button. Shared by Random, Send All and Panic: visually
//  identical, so one view rather than three near-duplicates. What each one
//  *does* is ContentView's business; this view only reports the press.
//
//  "A plate with its own name on it, pressed to do something. No bottom
//  name strip, unlike every control: a button's caption is the button. Flat
//  and in the accent, so it reads as the one thing on a panel that acts
//  rather than holds a value." - draw_button's own docstring, reproduced
//  rather than paraphrased since it says exactly why this looks this way.
//
//  A press flashes a wash over the plate, the acknowledgement for something
//  with no value to show for itself - light enough the caption stays
//  readable, and as long as the input lamp's blink, since one duration for
//  "something just happened" is enough.
//
//  Chrome is CardChrome now, the same material fill and selection-aware
//  stroke every other widget wears - tried on Panic alone first, then kept
//  for all three once it read better than the flat accent plate this used
//  to draw unconditionally.
//

import SwiftUI

struct ActionButtonView: View {
    let name: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    /// True while the panel is live - when the button can be pressed.
    var active: Bool = false
    var onTrigger: () -> Void = {}

    /// How solid the wash over a pressed button is.
    private static let flashOpacity: Double = 0.35

    @State private var flashing = false
    @State private var flashTask: Task<Void, Never>?
    /// Whether this press is still being held. The gesture's own guard, kept
    /// apart from `flashing`: a drag reports many changes and a button has one
    /// effect per press, but the flash outlasts a quick press - so using it as
    /// the guard would swallow the second of two presses in a row.
    @State private var holding = false

    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardChrome(isSelected: isSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .fill(accentColor.opacity(flashing ? Self.flashOpacity : 0))
        )
        .contentShape(Rectangle())
        // On the press, not the release: a button should act when it is
        // pushed. Zero minimum distance so a plain click counts.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    press()
                }
                .onEnded { _ in holding = false },
            including: active ? .all : .subviews
        )
    }

    /// Acts, then flashes to say so.
    private func press() {
        onTrigger()
        flashing = true
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: MIDIActivity.flashDuration)
            flashing = false
        }
    }
}

#Preview {
    HStack {
        ActionButtonView(name: "Random", systemImage: "shuffle")
        ActionButtonView(name: "Panic", systemImage: "exclamationmark.octagon", isSelected: true)
        ActionButtonView(name: "Send All", systemImage: "paperplane", active: true)
    }
    .frame(height: 40)
    .padding()
}
