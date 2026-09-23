//
//  LabelView.swift
//  PatchWork
//
//  Plain text, aligned as asked - the alignment editable in Inspector.
//
//  No plate and no fill: a label that drew a box around itself would be a
//  heading. So, like HeaderView, there is no card background here at all -
//  the plainness is the whole point, not an oversight.
//
//  A fresh label is left-aligned.
//
//  It does get the same light border HeaderView has, though: it is the
//  fill that has to stay away, not the border, and every card already
//  draws this one at rest regardless of selection.
//

import SwiftUI

struct LabelView: View {
    let name: String
    var align: LabelAlignment = .left
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    /// There is no unrecognised alignment to fall back from: a file that
    /// says something else fails to decode as a LabelAlignment and never
    /// reaches this view.
    private var alignment: Alignment {
        switch align {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    /// The same answer again for the text's own layout, which matters once
    /// a name is long enough to wrap or be truncated: a right-aligned
    /// label should truncate on its left, not its right.
    private var textAlignment: TextAlignment {
        switch align {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var body: some View {
        Text(name)
            .font(.system(size: 10))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .multilineTextAlignment(textAlignment)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
    }
}

#Preview {
    VStack(spacing: 4) {
        LabelView(name: "Filter Cutoff")
        LabelView(name: "Filter Cutoff", align: .center)
        LabelView(name: "Filter Cutoff", align: .right, isSelected: true)
    }
    .frame(width: 120)
    .padding()
}
