//
//  MonitorView.swift
//  PatchWork
//
//  Monitor - the last few messages, newest at the bottom the way a log
//  reads. How many rows: the element's own Lines property, capped by
//  however many actually fit its height, which is what draw_monitor does.
//
//  The lines are handed in rather than fetched: see PlacedElementView. With
//  no history at all it keeps showing one dim marker per row rather than a
//  single centred "No messages yet." - that fallback hides the row
//  count entirely, and resizing the element or changing Lines should
//  stay visible before any MIDI has arrived. They are not fake message
//  content, only "a line could go here".
//
//  Card look: a header bar (as StatusView got first) and the log lines
//  moved into their own tinted surface, via the shared CardChrome.
//

import SwiftUI

struct MonitorView: View {
    let name: String
    /// How many lines the element asks for. What it shows is this or
    /// however many fit, whichever is fewer.
    var lines: Int = 6
    /// The messages to show, oldest first. Fewer than `lines` is normal -
    /// early on there simply are not that many.
    var history: [String] = []
    var isSelected: Bool = false

    @Environment(\.appAccentColor) private var accentColor

    // Menlo 9pt's approximate line height.
    private let lineHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            logArea
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .cardChrome(isSelected: isSelected)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
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

    private var logArea: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.secondary.opacity(0.06))
            .overlay(
                GeometryReader { proxy in
                    // However many the element asks for, or however many fit -
                    // whichever is fewer: a monitor set to 12 lines in a
                    // two-line box shows two, rather than painting ten of
                    // them over its own border.
                    let fits = max(1, Int(proxy.size.height / lineHeight))
                    let shown = min(max(1, lines), fits)

                    // The newest `shown` lines, and a dim marker for each row
                    // there is no message for - so the rows stay put as
                    // messages arrive rather than the block growing upward.
                    let visible = Array(history.suffix(shown))
                    let blanks = shown - visible.count

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<blanks, id: \.self) { _ in
                            Text("–")
                                .foregroundStyle(.secondary.opacity(0.5))
                                .frame(height: lineHeight, alignment: .leading)
                        }
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                                .frame(height: lineHeight, alignment: .leading)
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
    }
}

#Preview("Light") {
    monitorGrid
        .background(Color(nsColor: .textBackgroundColor))
}

#Preview("Dark") {
    monitorGrid
        .background(Color(nsColor: .textBackgroundColor))
        .preferredColorScheme(.dark)
}

@ViewBuilder
private var monitorGrid: some View {
    HStack(spacing: 16) {
        // Same height, different Lines - and the tall one asking for
        // more than fits, so it shows what fits instead.
        MonitorView(name: "Monitor", lines: 3)
            .frame(width: 320, height: 104)
        MonitorView(
            name: "Monitor", lines: 24,
            history: ["RX  CH1 CC 74 = 64", "RX  CH1 NRPN 1000 = 8192", "TX  CH1 CC 70 = 0"],
            isSelected: true
        )
        .frame(width: 320, height: 104)
    }
    .padding()
}
