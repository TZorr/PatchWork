//
//  MultiField.swift
//  PatchWork
//
//  Editing several selected elements' shared fields at once - what
//  InspectorPanel shows instead of "N Elements Selected" once more than one
//  element is picked. A field a multi-selection disagrees on is "mixed",
//  the same word a native Inspector uses for it: a blank text field with a
//  grey "Multiple" placeholder, a dashed checkbox rather than on/off, no
//  highlighted picker item - never the value of whichever element happened
//  to be selected first, and never an asterisk.
//
//  Deliberately narrow: geometry and the lower Parameters/Values table stay
//  single-selection only (see InspectorPanel), so this only ever mediates
//  simple, fixed-shape fields - the ones every element carries as one
//  scalar rather than an array whose length varies by type.
//

import SwiftUI
import AppKit

/// A field's shared value across a multi-selection, or nil if the selected
/// elements disagree on it.
struct MultiField<T: Equatable> {
    let elements: Binding<[CanvasElement]>
    let indices: [Int]
    let keyPath: WritableKeyPath<CanvasElement, T>

    var value: T? {
        guard let first = indices.first else { return nil }
        let firstValue = elements.wrappedValue[first][keyPath: keyPath]
        return indices.dropFirst().allSatisfy { elements.wrappedValue[$0][keyPath: keyPath] == firstValue }
            ? firstValue : nil
    }

    /// Writes straight through to every selected element - what resolves a
    /// mixed field the moment it is touched, the same as typing over a
    /// native "Multiple Values" placeholder does.
    func set(_ newValue: T) {
        for index in indices { elements.wrappedValue[index][keyPath: keyPath] = newValue }
    }

    var binding: Binding<T?> {
        Binding(get: { value }, set: { if let newValue = $0 { set(newValue) } })
    }
}

/// A checkbox that can show AppKit's own third, "mixed" state - a dash
/// instead of on or off - for a Bool field a multi-selection disagrees on.
/// SwiftUI's own Toggle has no mixed state, so this wraps NSButton
/// directly, the same reason ComboBoxView's dropdown wraps NSMenu.
struct MixedToggle: NSViewRepresentable {
    let title: String
    var value: Bool?
    var onToggle: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToggle: onToggle) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.toggled(_:))
        )
        button.allowsMixedState = true
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onToggle = onToggle
        context.coordinator.currentValue = value
        button.title = title
        button.state = switch value {
        case .some(true): .on
        case .some(false): .off
        case .none: .mixed
        }
    }

    final class Coordinator: NSObject {
        var onToggle: (Bool) -> Void
        var currentValue: Bool?

        init(onToggle: @escaping (Bool) -> Void) {
            self.onToggle = onToggle
        }

        @objc func toggled(_ sender: NSButton) {
            // Not sender.state: AppKit's own mixed-state cycle would land
            // on .off first (Mixed -> Off -> On -> Mixed), unchecking
            // everything on the very click meant to resolve it. Resolving
            // a mixed field to *checked* on the first click, the way a
            // native Inspector does, only works by deciding from the value
            // this button had going in rather than the state AppKit just
            // cycled it to.
            let resolved = currentValue != true
            sender.state = resolved ? .on : .off
            onToggle(resolved)
        }
    }
}
