//
//  AppAppearance.swift
//  PatchWork
//
//  Light/Dark, held independently of the system setting. Backed by
//  @AppStorage rather than AppSettings: that struct's load/save pair is
//  for the answers only worth writing once, on the way out (ports, window
//  size) - this one should take effect the moment it is chosen, in every
//  window, which is what @AppStorage already does for free.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Codable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.fill"
        }
    }
}
