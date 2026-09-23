//
//  TransferMenu.swift
//  PatchWork
//
//  The toolbar's pace control: chunk size, the pause between units, and
//  whether to wait for the device to answer. What the numbers mean is
//  SysExTransfer's business; this is where they are set.
//
//  **In the toolbar rather than in the Inspector**, which is the one thing
//  about this that is not obvious. Every other setting that belongs to the
//  layout is edited in the Inspector, and these are not - because these are
//  the settings nobody knows the right value of. They are found by trying:
//  send, watch the device drop half a dump, slow down, send again. Sending
//  only happens in active mode, and in active mode the Inspector is not on
//  screen (see ContentView) - so an Inspector home would put a mode switch in
//  the middle of every turn of that loop. The toolbar is in both modes.
//
//  A popover rather than a Menu, for a reason the accent colour picker
//  already ran into: a SwiftUI Menu becomes a real NSMenu, which hosts simple
//  rows and nothing else. A text field in one arrives disabled.
//

import SwiftUI

struct TransferMenu: View {
    @Binding var transfer: SysExTransfer
    /// Whether an Input port is chosen. Handshake is unreachable without one
    /// - the reply arrives there - so it says so rather than failing later.
    let hasInput: Bool

    @State private var showingSettings = false
    /// Collapsed by default: Timeout and Retries only mean anything once a
    /// handshake is asked for, and even then their defaults are usually right.
    @State private var showingAdvanced = false

    var body: some View {
        Button {
            showingSettings.toggle()
        } label: {
            Label("Transfer", systemImage: "timer")
        }
        .help("SysEx pace: \(transfer.summary)")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            form
                .padding(16)
                .frame(width: 300)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SysEx Transfer")
                .font(.headline)

            field("Strategy") {
                Picker("Strategy", selection: $transfer.strategy) {
                    ForEach(SysExTransfer.Strategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .labelsHidden()
            }

            field("Chunk") {
                Picker("Chunk", selection: $transfer.chunkBytes) {
                    ForEach(SysExTransfer.chunkChoices, id: \.self) { size in
                        Text("\(size) bytes").tag(size)
                    }
                    // A hand-edited file may hold a size that is not on the
                    // menu. Shown rather than silently snapped to a
                    // neighbour, which would look like the app ignoring the
                    // file.
                    if !SysExTransfer.chunkChoices.contains(transfer.chunkBytes) {
                        Text("\(transfer.chunkBytes) bytes").tag(transfer.chunkBytes)
                    }
                }
                .labelsHidden()
            }

            field(transfer.strategy == .handshake ? "Break after reply" : "Break") {
                numberField($transfer.breakMS, unit: "ms")
            }

            if transfer.strategy == .handshake, !hasInput {
                Label(
                    "Handshake needs a MIDI Input - that is where the reply arrives.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            DisclosureGroup("Advanced", isExpanded: $showingAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    field("Timeout") {
                        numberField($transfer.timeoutMS, unit: "ms")
                    }
                    field("Retries") {
                        numberField($transfer.retries, unit: "")
                    }
                }
                .padding(.top, 8)
                // Both only ever apply to a handshake: Fixed Delay is not
                // listening for anything, so it has nothing to wait for and
                // nothing to try again.
                .disabled(transfer.strategy != .handshake)
            }
            .font(.caption)

            Divider()

            Text("Saved with the layout.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// A label and its control, on one line, with the labels lining up -
    /// the Inspector's own arrangement, at the width a popover has.
    private func field<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            content()
        }
    }

    private func numberField(_ value: Binding<Int>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
