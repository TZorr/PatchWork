//
//  AppSettings.swift
//  PatchWork
//
//  What the application remembers between sessions.
//
//  Not the layout - that is a file the user names and saves. This is the small
//  set of answers nobody wants to give twice a day: which ports were in use,
//  and how big the window was. Kept in UserDefaults rather than a JSON file
//  of its own: it is already the platform's config store, sandboxed into
//  this app's own container and written without anyone having to pick a path.
//
//  **Ports are remembered by name, not by CoreMIDI's unique id.** A name is
//  what the user chose in the menu and what they would recognise in a settings
//  file; a unique id is an implementation detail that a reinstalled driver can
//  change. The cost is that two identical devices cannot be told apart, which
//  is the trade the original makes too.
//
//  Every read is defensive. Settings are a convenience, and a missing or
//  half-written one must cost nothing more than the convenience - never the
//  session. UserDefaults gives that for free: an absent key is the default.
//

import Foundation

nonisolated struct AppSettings: Equatable {
    /// The port names last in use. Nil or empty means none was chosen - a
    /// real answer, not a missing one.
    var outputName: String?
    var inputName: String?
    /// A list, because the Controller role takes as many devices as are
    /// plugged in.
    var controllerNames: [String] = []
    /// How big the window was, for a session that opens without a layout.
    /// A layout of its own carries a size per mode - see PatchWorkDocument.
    var windowSize: CGSize?

    private enum Key {
        static let output = "midi.output"
        static let input = "midi.input"
        static let controllers = "midi.controllers"
        static let windowWidth = "window.width"
        static let windowHeight = "window.height"
    }

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        var settings = AppSettings()
        settings.outputName = defaults.string(forKey: Key.output)
        settings.inputName = defaults.string(forKey: Key.input)
        settings.controllerNames = defaults.stringArray(forKey: Key.controllers) ?? []
        let width = defaults.double(forKey: Key.windowWidth)
        let height = defaults.double(forKey: Key.windowHeight)
        // Both, or neither: half a size is not a size, and zero is what an
        // absent key reads as.
        if width > 0, height > 0 {
            settings.windowSize = CGSize(width: width, height: height)
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(outputName, forKey: Key.output)
        defaults.set(inputName, forKey: Key.input)
        defaults.set(controllerNames, forKey: Key.controllers)
        defaults.set(windowSize?.width ?? 0, forKey: Key.windowWidth)
        defaults.set(windowSize?.height ?? 0, forKey: Key.windowHeight)
    }
}
