//
//  AppAccentColor.swift
//  PatchWork
//
//  A custom accent color, independent of the system's - see AppAppearance
//  for the same idea applied to light/dark. There is no AccentColor set in
//  Assets.xcassets, so Color.accentColor already resolves to the system's
//  own accent color; "no override" here just means leaving accentColorHex
//  empty, which is what ContentView's Appearance menu and PatchWorkApp both
//  fall back to.
//
//  Color itself is not RawRepresentable, so @AppStorage needs a wire format -
//  hence the hex string round trip below, going through NSColor since this
//  is a macOS-only app.
//

import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let resolved = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

private struct AppAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    /// What every widget reads instead of Color.accentColor directly - the
    /// resolved accent, custom pick or system default alike. Fed from
    /// PatchWorkApp's own accentColorHex, the way .preferredColorScheme is
    /// fed from its appearance.
    var appAccentColor: Color {
        get { self[AppAccentColorKey.self] }
        set { self[AppAccentColorKey.self] = newValue }
    }
}
