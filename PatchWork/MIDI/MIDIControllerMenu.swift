//
//  MIDIControllerMenu.swift
//  PatchWork
//
//  The Controller picker. Its own view rather than a mode of MIDIPortMenu,
//  because the selection model is genuinely different: the Output and the
//  Input are one choice each, and the controllers are a set. A keyboard and
//  a fader box are an ordinary pair, and neither is more the controller.
//
//  So: a Toggle per source, not a Picker. Unticking one is how it is
//  disconnected - a dropdown would need a "None" entry to mean "release
//  this port", and a set of toggles already has one.
//  "Disconnect All" is there for the case where
//  several are on and the point is to silence them.
//

import SwiftUI

struct MIDIControllerMenu: View {
    let sources: [MIDIEndpointInfo]
    let selectedIDs: Set<Int32>
    let onSet: (Int32, Bool) -> Void
    let onDisconnectAll: () -> Void
    let onRescan: () -> Void

    var body: some View {
        Menu {
            Section("Controller") {
                ForEach(sources) { source in
                    Toggle(source.name, isOn: Binding(
                        get: { selectedIDs.contains(source.id) },
                        set: { onSet(source.id, $0) }
                    ))
                }
            }

            Divider()

            Button("Disconnect All", action: onDisconnectAll)
                .disabled(selectedIDs.isEmpty)
            Button("Rescan Ports", action: onRescan)

            if sources.isEmpty {
                Text("No MIDI inputs found")
            }
        } label: {
            Label(label, systemImage: "pianokeys")
        }
    }

    /// One name reads better than "1 Controller"; past that the count is what
    /// fits and what is actually useful.
    private var label: String {
        switch selectedIDs.count {
        case 0: "No Controller"
        case 1: sources.first { selectedIDs.contains($0.id) }?.name ?? "1 Controller"
        default: "\(selectedIDs.count) Controllers"
        }
    }
}
