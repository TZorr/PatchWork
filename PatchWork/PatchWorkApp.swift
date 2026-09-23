//
//  PatchWorkApp.swift
//  PatchWork
//

import SwiftUI
import AppKit

@main
struct PatchWorkApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    /// Independent of the system setting - see AppAccentColor. Empty means
    /// no override: follow the system accent color, same as always.
    @AppStorage("accentColorHex") private var accentColorHex: String = ""
    @Environment(\.openWindow) private var openWindow

    /// The one MIDI noticeboard, owned here rather than by an editor.
    ///
    /// The MIDI Monitor is a window of its own and can reach no ContentView's
    /// `@State`, so the board has to live above both. Only the board is
    /// shared - each editor window still has its own engine and its own port
    /// selection, exactly as before.
    @State private var activity = MIDIActivity()

    var body: some Scene {
        WindowGroup {
            ContentView(activity: activity)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.appAccentColor, Color(hex: accentColorHex) ?? .accentColor)
                .tint(Color(hex: accentColorHex))
        }
        .commands {
            // A singleton `Window` rather than another WindowGroup: help is
            // one reference to bring forward, not a document to open several
            // of. ⌘? matches the shortcut a stock Help menu's search field
            // would otherwise sit on.
            CommandGroup(replacing: .help) {
                Button("PatchWork Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            // Native macOS tabs already merge PatchWork's windows into one
            // bar - see View > Show All Tabs. What was missing is a way to
            // tell them apart: a window opens titled just "PatchWork", same
            // as every other one. ContentView retitles a window to its file
            // the moment one is opened or saved, but a fresh or unsaved
            // window still needs a name of its own, hence this.
            CommandGroup(after: .windowArrangement) {
                Button("Rename Tab…") {
                    renameKeyWindow()
                }
            }
            // Name, version and copyright already come from the bundle -
            // see MARKETING_VERSION and INFOPLIST_KEY_NSHumanReadableCopyright
            // in the project settings. Only the project link needs adding, as
            // a Credits link the standard panel has no other way to carry.
            CommandGroup(replacing: .appInfo) {
                Button("About PatchWork") {
                    showAboutPanel()
                }
            }
            // A menu of its own rather than another entry under Window: these
            // are tools that happen to be windows, not windows of the
            // document, and there will be more of them. CommandMenu places
            // itself before Window, which is where a Tools menu belongs.
            //
            // Shift too: plain Cmd+M is Minimize on macOS, and taking that
            // away is the kind of thing noticed only later, by someone
            // wondering why a window will not go down.
            CommandMenu("Tools") {
                Button("MIDI Monitor") {
                    openWindow(id: "midi-monitor")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Window("PatchWork Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        // Singleton, like Help: one log to bring forward, not a document to
        // open several of. Resizable, unlike Help - the first thing anyone
        // does with a log window is make it bigger.
        Window("MIDI Monitor", id: "midi-monitor") {
            MIDIMonitorView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.appAccentColor, Color(hex: accentColorHex) ?? .accentColor)
                .environment(\.midiActivity, activity)
                .tint(Color(hex: accentColorHex))
        }
        .defaultSize(width: 900, height: 520)
    }

    /// The repository rather than an address: it is where the source, the
    /// releases and somewhere to report a bug all are, and it is one thing to
    /// keep current instead of two.
    private static let projectURL = "https://github.com/TZorr/PatchWork"

    private func showAboutPanel() {
        let credits = NSMutableAttributedString(string: "github.com/TZorr/PatchWork")
        credits.addAttribute(
            .link,
            value: Self.projectURL,
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Applied straight to the window: a tab's label already *is*
    /// NSWindow.title, so there is no separate "tab name" to keep in sync
    /// with it.
    private func renameKeyWindow() {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: window.title)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                window.title = title
            }
        }
    }
}
