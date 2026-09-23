//
//  CardChrome.swift
//  PatchWork
//
//  The card look a widget wraps itself in: material fill and a
//  selection-aware stroke. Factored out of StatusView so a later widget can
//  pick it up with one line, without every widget getting it today.
//

import SwiftUI

struct CardChrome: ViewModifier {
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
    }
}

extension View {
    func cardChrome(isSelected: Bool) -> some View {
        modifier(CardChrome(isSelected: isSelected))
    }
}
