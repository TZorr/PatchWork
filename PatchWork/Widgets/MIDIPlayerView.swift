//
//  MIDIPlayerView.swift
//  PatchWork
//
//  What is looping to the output, or the invitation to drop a file on.
//
//  Reads the shared player directly, the same way LEDView reads the activity
//  lamp: the file and the play state are not this element's own - see
//  MIDIPlayer for why they are one noticeboard rather than one per element.
//  Two of these on a panel show the same thing, because there is one output.
//
//  Dropping is active mode only: dropping a file is *using* the panel, the
//  same as a click is, and nothing plays from the editor. The opposite of a
//  Library drop, which is
//  editor-only.
//
//  Card look: a header bar and the play state moved into its own tinted
//  surface, the same treatment Status and Monitor got.
//

import SwiftUI
import UniformTypeIdentifiers

struct MIDIPlayerView: View {
    let name: String
    var isSelected: Bool = false
    var active: Bool = false
    /// The shared player, read for what to show.
    var player: MIDIPlayer = MIDIStatus.idle.player
    /// A file was dropped on this element. Loading it is ContentView's
    /// business - this view only says which file.
    var onDrop: (URL) -> Void = { _ in }
    /// It was pressed: stop what is looping, or start the file still loaded.
    /// A press carries no file of its own.
    var onTrigger: () -> Void = {}

    /// Whether this press is still being held, so one press is one effect. A
    /// drag reports many changes and a button has one meaning per press.
    @State private var holding = false

    /// Whether a drag is currently over this element, so it can say that it
    /// will take the file rather than leaving the pointer to guess.
    @State private var targeted = false

    @Environment(\.appAccentColor) private var accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .padding(8)
        }
        .cardChrome(isSelected: isSelected || targeted)
        .contentShape(Rectangle())
        // On the press, like the action buttons: a transport should act when
        // it is pushed. No flash behind it, unlike those - this one has
        // something to show for itself, and the heading changing between
        // Playing and Stopped is the acknowledgement.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true
                    onTrigger()
                }
                .onEnded { _ in holding = false },
            including: active ? .all : .subviews
        )
        // Only in active mode, and only .mid: a file dropped on a panel being
        // built is not an instruction to anything.
        .dropDestination(for: URL.self) { urls, _ in
            guard active, let url = urls.first(where: isMIDIFile) else { return false }
            onDrop(url)
            return true
        } isTargeted: { over in
            targeted = active && over
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "music.note")
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

    @ViewBuilder
    private var content: some View {
        Group {
            if let file = player.name {
                VStack(spacing: 3) {
                    Text(player.playing ? "▶  Playing" : "■  Stopped")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(player.playing ? accentColor : .primary)
                    Text(file)
                        .font(.system(size: 9))
                        .foregroundStyle(player.playing ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("Drop a .mid file here")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.06)))
    }

    private func isMIDIFile(_ url: URL) -> Bool {
        ["mid", "midi"].contains(url.pathExtension.lowercased())
    }
}

#Preview {
    let loaded = MIDIPlayer()
    return HStack {
        MIDIPlayerView(name: "MIDI Player")
        MIDIPlayerView(name: "MIDI Player", isSelected: true, player: loaded)
    }
    .frame(width: 420, height: 96)
    .padding()
}
