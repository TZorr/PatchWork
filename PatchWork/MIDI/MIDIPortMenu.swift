//
//  MIDIPortMenu.swift
//  PatchWork
//
//  The toolbar's port picker. One view used twice - once for the output,
//  once for the input - because the two menus differ only in their label
//  and their list. Ports are picked here rather than on the canvas: which
//  device the application is talking to is about the application, not about
//  the layout being designed.
//
//  Extracted from ContentView's toolbar rather than written inline, for two
//  reasons. The second menu would have been a copy of the first, and the
//  toolbar had already grown past what the type-checker would solve in
//  reasonable time - a single expression containing two Pickers with
//  ForEach bodies over optional tags is exactly the shape that defeats it.
//

import SwiftUI

struct MIDIPortMenu: View {
    /// "Output" or "Input" - the Picker's label and the wording of the
    /// empty-list note.
    let role: String
    let systemImage: String
    let endpoints: [MIDIEndpointInfo]
    let selectedID: Int32?
    /// Nil means "None": disconnecting is a real choice, not the absence of
    /// one, so it is an entry in the list rather than a separate button.
    let onSelect: (MIDIEndpointInfo?) -> Void
    let onRescan: () -> Void

    private var selection: Binding<Int32?> {
        Binding(
            get: { selectedID },
            set: { id in onSelect(endpoints.first { $0.id == id }) }
        )
    }

    var body: some View {
        Menu {
            Picker(role, selection: selection) {
                Text("None").tag(Int32?.none)
                ForEach(endpoints) { endpoint in
                    Text(endpoint.name).tag(Int32?.some(endpoint.id))
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Rescan Ports", action: onRescan)

            if endpoints.isEmpty {
                // Said plainly, because an empty menu looks like a broken
                // app rather than an empty system. Nothing here can conjure
                // a port that does not exist.
                Text("No MIDI \(role.lowercased())s found")
            }
        } label: {
            Label(label, systemImage: systemImage)
        }
    }

    private var label: String {
        endpoints.first { $0.id == selectedID }?.name ?? "No \(role)"
    }
}
