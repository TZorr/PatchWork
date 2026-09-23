//
//  MIDIMonitorView.swift
//  PatchWork
//
//  The MIDI Monitor: a window of its own, independent of any panel, that
//  shows everything on the ports and lets it be filtered and copied out.
//
//  Not a canvas widget, hence not in Widgets/ - the things in there are
//  elements someone places on a panel and saves to a .pwork file. This is a
//  tool, and it belongs to the app rather than to any layout.
//
//  It reads the shared MIDIActivity out of the environment; PatchWorkApp owns
//  it and hands the same one to the editor's engine. Which also means that
//  with several editor windows open, their traffic lands in one log - right
//  for a monitor, and the Device column is what tells them apart.
//
//  Recording only happens while a window is open (see beginCapture), so the
//  cost of this file when it is closed is nothing at all.
//

import AppKit
import SwiftUI

struct MIDIMonitorView: View {
    @Environment(\.midiActivity) private var activity
    @Environment(\.appAccentColor) private var accentColor

    /// Which readings to show. Both by default: the window exists to compare
    /// them, and hiding one by default would hide the reason it is here.
    @State private var forms: Set<MIDIEvent.Form> = Set(MIDIEvent.Form.allCases)
    @State private var directions: Set<MIDIEvent.Direction> = Set(MIDIEvent.Direction.allCases)
    /// Everything except Realtime. Clock arrives twenty-four times a beat and
    /// would be the whole log; someone who wants it can tick it back on.
    @State private var kinds: Set<MIDIEvent.Kind> = Set(
        MIDIEvent.Kind.allCases.filter { $0 != .realtime }
    )
    @State private var search = ""
    /// Freezes the *view*, not the recording - see `shown`.
    @State private var paused = false
    @State private var frozen: [MIDIEvent] = []

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            log
        }
        .frame(minWidth: 620, minHeight: 320)
        .background(Color(nsColor: .textBackgroundColor))
        // The record exists only while a window is watching it.
        .onAppear { activity.beginCapture() }
        .onDisappear { activity.endCapture() }
    }

    // ── What is shown ────────────────────────────────────────────────────

    /// The filtered log.
    ///
    /// While paused this returns a snapshot taken when Pause was pressed.
    /// Recording carries on underneath, so letting go resumes with nothing
    /// missing - which is the point of pausing a log rather than stopping it.
    private var shown: [MIDIEvent] {
        let source = paused ? frozen : activity.events
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return source.filter { event in
            guard forms.contains(event.form),
                  directions.contains(event.direction),
                  kinds.contains(event.kind) else { return false }
            guard !needle.isEmpty else { return true }
            return event.text.lowercased().contains(needle)
                || (event.device?.lowercased().contains(needle) ?? false)
        }
    }

    // ── Controls ─────────────────────────────────────────────────────────

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                picker("Show", MIDIEvent.Form.allCases, selected: $forms) { $0.title }
                Divider().frame(height: 16)
                picker("Direction", MIDIEvent.Direction.allCases,
                       selected: $directions) { $0.title }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(MIDIEvent.Kind.allCases, id: \.self) { kind in
                        Toggle(kind.title, isOn: binding(kind, in: $kinds))
                    }
                    Divider()
                    Button("All") { kinds = Set(MIDIEvent.Kind.allCases) }
                    Button("None") { kinds = [] }
                } label: {
                    Label(kindsLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Spacer(minLength: 0)

                Toggle(isOn: pauseBinding) {
                    Label(paused ? "Paused" : "Pause",
                          systemImage: paused ? "play.fill" : "pause.fill")
                }
                .toggleStyle(.button)
                .foregroundStyle(paused ? accentColor : .primary)

                Button {
                    copyLog()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(shown.isEmpty)
                .help("Copy every line the filters currently show")

                Button(role: .destructive) {
                    activity.clearEvents()
                    frozen.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(activity.events.isEmpty)
                .help("Empties this log. The Monitor elements on the panel keep theirs.")
            }
            .font(.callout)
        }
        .padding(10)
    }

    private var kindsLabel: String {
        if kinds.count == MIDIEvent.Kind.allCases.count { return "All types" }
        if kinds.isEmpty { return "No types" }
        return "\(kinds.count) types"
    }

    /// Pause takes the snapshot on the way in rather than the way out: what
    /// should be held still is what was on screen when the button was pressed.
    private var pauseBinding: Binding<Bool> {
        Binding(
            get: { paused },
            set: { wanted in
                if wanted { frozen = activity.events }
                paused = wanted
            }
        )
    }

    // ── The log ──────────────────────────────────────────────────────────

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(shown) { event in
                        row(event)
                            .id(event.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Selectable, so a line can be dragged over and copied with the
            // ordinary shortcut. Copy above is for the whole filtered log,
            // which is the thing nobody wants to select by hand.
            .textSelection(.enabled)
            .overlay { if shown.isEmpty { emptyState } }
            .onChange(of: shown.last?.id) { _, id in
                guard !paused, let id else { return }
                withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private func row(_ event: MIDIEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(event.timeText)
                .foregroundStyle(.tertiary)
            Text(event.direction.rawValue)
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(colour(event.direction))
            Text(event.form.rawValue)
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(event.form == .raw ? .tertiary : .secondary)
            Text(event.channel.map { "CH\($0)" } ?? "--")
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(.tertiary)
            Text(event.text)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let device = event.device {
                Text(device)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func colour(_ direction: MIDIEvent.Direction) -> Color {
        switch direction {
        case .rx: .green
        case .tx: accentColor
        case .ctrl: .orange
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(activity.events.isEmpty ? "Nothing yet." : "Nothing matches the filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // ── Copying ──────────────────────────────────────────────────────────

    /// The filtered log as text, tab-separated - see MIDIEvent.logLine.
    private func copyLog() {
        let text = shown.map(\.logLine).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // ── Small helpers ────────────────────────────────────────────────────

    /// A row of toggles over a set - the shape both Show and Direction take.
    private func picker<T: Hashable>(_ title: String, _ all: [T],
                                     selected: Binding<Set<T>>,
                                     label: @escaping (T) -> String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(all, id: \.self) { item in
                Toggle(label(item), isOn: binding(item, in: selected))
                    .toggleStyle(.button)
                    .font(.caption)
            }
        }
    }

    private func binding<T: Hashable>(_ item: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(item) },
            set: { on in
                if on { set.wrappedValue.insert(item) } else { set.wrappedValue.remove(item) }
            }
        )
    }
}

// ── Handing the board to a window that has no editor ─────────────────────

/// The one MIDIActivity, reachable from a scene that owns no engine.
///
/// An environment key rather than a parameter: `Window` scenes are built by
/// SwiftUI, not by us, so there is nowhere to pass one in.
private struct MIDIActivityKey: EnvironmentKey {
    static let defaultValue = MIDIActivity()
}

extension EnvironmentValues {
    var midiActivity: MIDIActivity {
        get { self[MIDIActivityKey.self] }
        set { self[MIDIActivityKey.self] = newValue }
    }
}
