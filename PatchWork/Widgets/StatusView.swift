//
//  StatusView.swift
//  PatchWork
//
//  The status table: the OUT/IN/CTRL port rows, then room for the last few
//  SENT lines whether or not anything has been sent, so the element does not
//  change height the moment it is first used. Role labels in the accent,
//  values in text color - or a dim placeholder tone for "None".
//
//  All three port rows are real. CTRL can name several at once - the
//  controllers are a set, not one choice - and they are joined into the one
//  row rather than given a row each, so the element keeps its shape whatever
//  is plugged in. A long list runs out under the row's own clip.
//
//  Built with plain SwiftUI Text rows rather than Canvas, unlike most other
//  per-type widgets - this one is fundamentally a small table, and SwiftUI's
//  own text layout is a better fit for that than hand-drawn GraphicsContext
//  text would be.
//
//  Card demo: a header bar and two grouped, tinted sub-surfaces (ports vs.
//  sent history) replace the single flat block, via the shared CardChrome
//  the other widgets don't use yet.
//

import SwiftUI

private struct StatusRow: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String?
}

struct StatusView: View {
    let name: String
    /// The connected ports, or nil for none. The OUT and IN rows.
    var outputName: String?
    var inputName: String?
    /// Every connected controller. Joined into the one CTRL row.
    var controllerNames: [String] = []
    /// The last thing sent, one line per message. An NRPN is four messages,
    /// so showing only the last would read "Data Entry (fine)" with no hint
    /// of what it was fine-tuning - hence several rows.
    var sentLines: [String] = []
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    private var portRows: [StatusRow] {
        [
            StatusRow(icon: "arrowshape.up", label: "OUT", value: outputName),
            StatusRow(icon: "arrowshape.down", label: "IN", value: inputName),
            StatusRow(icon: "pianokeys", label: "CTRL", value: controllerNames.isEmpty
                      ? nil : controllerNames.joined(separator: ", ")),
        ]
    }

    /// Exactly `sentLineLimit` slots, filled from the top, blank below - a
    /// fixed count keeps the table from reflowing as sends come and go.
    private var sentValues: [String?] {
        let sent = Array(sentLines.prefix(MIDIActivity.sentLineLimit))
        return (0..<MIDIActivity.sentLineLimit).map { index in
            index < sent.count ? sent[index] : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 8) {
                ports
                sent
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .cardChrome(isSelected: isSelected)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
    }

    private var ports: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(portRows) { row in
                HStack(spacing: 4) {
                    Image(systemName: row.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 11)
                    Text(row.label)
                        .foregroundStyle(accentColor)
                        .frame(width: 36, alignment: .leading)
                    Text(row.value ?? "None")
                        .lineLimit(1)
                        .foregroundStyle(row.value == nil ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 10))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
    }

    private var sent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.up")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("SENT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sentValues.enumerated()), id: \.offset) { _, value in
                if let value {
                    Text(value)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                } else {
                    Text("–")
                        .lineLimit(1)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
    }
}

#Preview("Light") {
    statusGrid
        .background(Color(nsColor: .textBackgroundColor))
}

#Preview("Dark") {
    statusGrid
        .background(Color(nsColor: .textBackgroundColor))
        .preferredColorScheme(.dark)
}

@ViewBuilder
private var statusGrid: some View {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            StatusView(name: "Status")
                .frame(width: 368, height: 152)
            StatusView(name: "Status", isSelected: true)
                .frame(width: 368, height: 152)
        }
        HStack(spacing: 16) {
            StatusView(
                name: "Status",
                outputName: "MiniFreak MIDI", inputName: "MiniFreak MIDI",
                controllerNames: ["Keystep", "Faderfox EC4"],
                sentLines: ["CH1 NRPN MSB 7", "CH1 NRPN LSB 104", "CH1 Data Entry 64"]
            )
            .frame(width: 368, height: 152)
            StatusView(
                name: "Status",
                outputName: "MiniFreak MIDI", inputName: "MiniFreak MIDI",
                controllerNames: ["Keystep", "Faderfox EC4"],
                sentLines: ["CH1 NRPN MSB 7", "CH1 NRPN LSB 104", "CH1 Data Entry 64"],
                isSelected: true
            )
            .frame(width: 368, height: 152)
        }
    }
    .padding()
}
