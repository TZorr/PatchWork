//
//  ContentView.swift
//  PatchWork
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var canvasElements: [CanvasElement] = []
    /// Everything selected. Dragging a group, deleting one and duplicating one
    /// are what it is for - each of them something a single element cannot be.
    @State private var selection: Set<CanvasElement.ID> = []
    /// Copied elements, kept as plain values.
    ///
    /// `CanvasElement` is a value type, so holding them *is* holding a copy -
    /// no encode/decode round trip needed to detach them from the canvas.
    /// Paste still mints fresh ids (see `duplicated`), or a pasted element
    /// would be the same element twice.
    @State private var clipboard: [CanvasElement] = []
    /// The last copied Value List, kept apart from `clipboard`: copying a
    /// value list and copying an element are different gestures with
    /// different targets (many widgets vs. exactly the one copied from).
    @State private var valueListClipboard: [ValueEntry]?
    @FocusState private var windowFocused: Bool

    /// The shared noticeboard, from PatchWorkApp. Handed straight to the
    /// engine below - the MIDI Monitor is a window of its own and watches the
    /// same one, which is why it cannot be made here.
    let activity: MIDIActivity

    /// The engine itself is still this window's own: one editor, one set of
    /// ports. Only the board it writes to is shared.
    @State private var midi: MIDIEngine

    init(activity: MIDIActivity = MIDIActivity()) {
        self.activity = activity
        _midi = State(initialValue: MIDIEngine(activity: activity))
    }

    /// Whether the layout is being used rather than arranged. See
    /// `setActive(_:)`.
    @State private var active = false
    /// Whether the arrangement is nailed down.
    ///
    /// Separate from `active`, and a different kind of thing: active mode says
    /// the panel is in use, while a lock says the *arranging* is finished. It
    /// is against the accidental drag, not against deliberate editing - a
    /// locked element is still selected, still inspected and still edited by
    /// its number fields. Saved with the layout, so a panel that was finished
    /// stays finished.
    @State private var locked = false
    /// Every element as it was when the layout went live.
    ///
    /// Operating a control - or a message arriving in active mode - writes
    /// into the very properties the editor edits, so this is what tells the
    /// configured default from the value someone has since dialled in, and
    /// what puts the layout back the way it was designed on the way out.
    @State private var restingElements: [CanvasElement]?

    /// The two side panels' widths, dragged by the dividers between them.
    ///
    /// Held here rather than inside each panel because a divider sits
    /// *between* two views and belongs to neither. Ranges are generous on the
    /// Inspector: its lower table has four columns once the output is SysEx
    /// (Parameter / Template / Parsed / Value), and 300 points is not enough
    /// to read a template in.
    @State private var libraryWidth: CGFloat = 200
    @State private var inspectorWidth: CGFloat = 300

    /// The Learn run in progress, if any. See `toggleLearn`.
    @State private var learnRun: LearnRun?
    /// The element collecting arriving values into its Value List, if any.
    ///
    /// An id and no more, where address-Learn needs a whole `LearnRun`: that
    /// one walks an element's parameters in order and has to remember where it
    /// has got to, while this one fills a single list and is finished only when
    /// someone says so. Armed from the Inspector's own checkbox rather than the
    /// toolbar, since it belongs to a list only one kind of element has - see
    /// `captureValues(from:)` and ElementValueLearn.swift.
    @State private var valueLearnID: CanvasElement.ID?

    /// The window this view is in, for reading and setting its size. See
    /// WindowAccessor.
    @State private var window: NSWindow?
    /// How big the window should be in each mode, carried by the layout.
    ///
    /// A panel in use is usually not the size it was built at - arranging
    /// wants room, playing wants the panel - so the size is remembered per
    /// mode and applied on the way across.
    @State private var windowSizes: [PatchWorkDocument.LayoutMode: CGSize] = [:]

    /// Which element Learn is waiting on, and where in its parameters it has
    /// got to.
    ///
    /// One element at a time: this writes into the design, and "which element"
    /// has to have exactly one answer. A run walks the element's parameters in
    /// order, because four stages of an envelope are four knobs on the device
    /// and stopping after the first would mean arming it four times.
    private struct LearnRun {
        let elementID: CanvasElement.ID
        var index: Int
        let first: Int
        let last: Int
        /// The addresses this run has already assigned. What moves the run on
        /// is a *different address*, not another message - see `learn(from:)`.
        var seen: Set<LearnAddress> = []
    }

    @State private var showingSaveDialog = false
    @State private var showingOpenDialog = false
    /// The file this layout came from, and the one Save writes back over.
    /// Nil until there is one - a layout that has never been saved has
    /// nowhere to save over, which is what sends Save to the panel instead.
    @State private var documentURL: URL?
    @State private var fileError: String?
    @State private var showingAccentPicker = false

    /// Independent of the system setting - see AppAppearance.
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    /// Independent of the system setting - see AppAccentColor. Empty means
    /// no override: follow the system accent color.
    @AppStorage("accentColorHex") private var accentColorHex: String = ""
    /// Fed from PatchWorkApp's own accentColorHex - see AppAccentColor.
    @Environment(\.appAccentColor) private var accentColor
    /// The window's own, supplied by AppKit - see CanvasUndo.
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 0) {
            // The Library and the Inspector are hidden in active mode rather
            // than disabled: they *are* the editor, and a live panel should
            // be the panel and nothing else. Everything about the
            // application itself stays in the toolbar, in both modes.
            if !active {
                LibraryPanel(onSelectType: placeElement, width: libraryWidth,
                             enabled: !locked)
                PanelDivider(width: $libraryWidth, range: 140...400, edge: .leading)
            }

            EditorCanvasView(
                elements: $canvasElements,
                selection: $selection,
                status: midi.status,
                active: active,
                locked: locked,
                armedElementID: learnRun?.elementID ?? valueLearnID,
                onOperated: operated,
                onTriggered: triggered,
                onDropFile: loadMIDIFile,
                onDeleted: elementsDeleted
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !active {
                // Trailing edge: dragging left widens the Inspector, so the
                // translation counts the other way round.
                PanelDivider(width: $inspectorWidth, range: 260...900, edge: .trailing)
                InspectorPanel(
                    elements: $canvasElements,
                    selection: selection,
                    valueLearnID: $valueLearnID,
                    hasInput: hasInput,
                    width: inspectorWidth
                )
            }
        }
        .background(WindowAccessor { window = $0 })
        .focusable()
        .focusEffectDisabled()
        .focused($windowFocused)
        .onAppear {
            windowFocused = true
            restoreSettings()
            // Assigned here rather than at construction: the closure writes
            // through @State, which only has storage to write to once the
            // view is on screen.
            midi.onDecoded = { messages, roles in incoming(messages, roles: roles) }
            // A handshake transfer fails long after the send that started it
            // returned, so it cannot report through a return value - see
            // MIDIEngine.onTransferFailed.
            midi.onTransferFailed = { fileError = $0 }
        }
        // Written on the way out rather than on every change: which ports are
        // in use is not worth a disk write per menu click, and quitting is
        // the one moment it is certainly worth having.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification)) { _ in
            saveSettings()
            // Quitting mid-file used to leave up to MIDIPlayer.lookahead of
            // scheduled packets with the driver and any sounding note held:
            // the engine's deinit disposes the ports, which is not the same as
            // telling the device to stop.
            midi.stopPlayback()
        }
        // And the same for a window closing on its own, which is a quit as far
        // as this panel's playback is concerned.
        .onDisappear {
            midi.stopPlayback()
        }
        // Every editor shortcut is inert while the panel is live - there is
        // no selection to delete, cycle or clear.
        // The other half of toggleLearn's exclusion: arming from the
        // Inspector stands the toolbar's run down, the same way arming from
        // the toolbar stands this one down.
        .onChange(of: valueLearnID) { _, id in
            if id != nil { learnRun = nil }
        }
        // An armed element that is no longer selected has no checkbox on
        // screen to switch off, and would go on collecting out of sight.
        .onChange(of: selection) { _, _ in
            valueLearnID = nil
        }
        // The Input going away leaves both arms waiting on a port that no
        // longer exists - the same standing-down every other way out does.
        .onChange(of: midi.selectedSourceID) { _, id in
            if id == nil {
                learnRun = nil
                valueLearnID = nil
            }
        }
        .onKeyPress(.delete) { deleteSelectedElement() }
        .onKeyPress(.deleteForward) { deleteSelectedElement() }
        .onKeyPress(.escape) { clearSelection() }
        .onKeyPress(.tab, phases: .down) { press in
            cycleSelection(forward: !press.modifiers.contains(.shift))
        }
        .toolbar {
            // First in the toolbar because it changes what everything after
            // it means. Grouped with Learn, Lock, Send All and Panic:
            // together they are the panel's own states and the commands that
            // act on it, apart from the document and MIDI-port concerns
            // around them.
            ToolbarItemGroup {
                Button {
                    setActive(!active)
                } label: {
                    Label(
                        active ? "Active Mode" : "Editor Mode",
                        systemImage: active ? "play.circle.fill" : "pencil.circle"
                    )
                }
                .keyboardShortcut("r", modifiers: .command)
                .foregroundStyle(active ? accentColor : .primary)

                // Learn is a *state*, so the button shows it: what it is
                // waiting for, and that pressing it again stands down.
                Button(action: toggleLearn) {
                    Label(learnLabel, systemImage: learnRun == nil
                          ? "dot.radiowaves.left.and.right" : "record.circle.fill")
                }
                .keyboardShortcut("k", modifiers: .command)
                .foregroundStyle(learnRun == nil ? .primary : accentColor)
                .disabled(active || (learnRun == nil && !(canLearn && hasInput)))
                .help(learnHelp)

                // A lock reads as the smaller relative of a mode: nothing
                // moves in either.
                Button {
                    locked.toggle()
                    // A lock is not an offer to resize, so nothing should look
                    // like one - and the handles only ever show on a lone
                    // selection anyway.
                } label: {
                    Label(locked ? "Locked" : "Unlocked",
                          systemImage: locked ? "lock.fill" : "lock.open")
                }
                .keyboardShortcut("l", modifiers: .command)
                .foregroundStyle(locked ? accentColor : .primary)
                // Editor-only by nature: nothing moves in active mode anyway.
                .disabled(active)

                Button {
                    send(canvasElements.midiMessages, what: "Send All")
                } label: {
                    Label("Send All", systemImage: "paperplane.circle")
                }
                .disabled(midi.selectedDestinationID == nil || canvasElements.isEmpty)

                Button(action: panic) {
                    Label("Panic", systemImage: "exclamationmark.octagon")
                }
                .disabled(midi.selectedDestinationID == nil)
            }

            // Select All / Copy / Paste in one menu, each carrying its own
            // shortcut so Cmd+A/C/V work whether the menu is open or not.
            //
            // Used to also hold Align and Pack commands, for a canvas with
            // no grid. This one snaps to 8 points, which is what those were
            // for: two elements dragged to roughly the same row land on
            // exactly the same one. Packing was worse than redundant - it
            // butts elements together with no gap, ignoring the grid.
            //
            // A toolbar menu rather than the system Edit menu: that would
            // mean reaching this view's state from the App's `commands`
            // block, which wants the state pulled into an observable model
            // of its own - worth doing, not worth smuggling into this
            // change.
            ToolbarItem {
                Menu {
                    Button("Select All", action: selectAll)
                        .keyboardShortcut("a", modifiers: .command)
                    Button("Copy", action: copySelection)
                        .keyboardShortcut("c", modifiers: .command)
                        .disabled(selection.isEmpty)
                    Button("Copy Value List", action: copyValueList)
                        .disabled(!canCopyValueList)
                    Button("Paste", action: paste)
                        .keyboardShortcut("v", modifiers: .command)
                        .disabled(clipboard.isEmpty || locked)
                    Button("Paste Value List", action: pasteValueList)
                        .disabled(!canPasteValueList)
                } label: {
                    Label(selectionLabel, systemImage: "square.on.square.dashed")
                }
                .disabled(active)
            }

            ToolbarItem {
                Button {
                    showingOpenDialog = true
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            // Both in one group so the toolbar's builder still counts them as
            // a single item - see the MIDI ports' own group for why that
            // matters. Save over the file, Save As… to choose a new one, the
            // two shortcuts macOS puts them on everywhere else.
            ToolbarItemGroup {
                Button(action: saveDocument) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help(documentURL.map { "Save over \($0.lastPathComponent)" }
                      ?? "Choose where to save this layout")

                Button {
                    showingSaveDialog = true
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // MIDI lives in the toolbar rather than on the canvas: which
            // port the application is connected to is about the
            // application, not about the layout being designed. The Random
            // and Send All *elements* are a separate thing - those are
            // placed on a panel and pressed while operating it.
            // The three ports in one group: they are one subject, and the
            // toolbar's builder only takes ten items besides.
            ToolbarItemGroup {
                MIDIPortMenu(
                    role: "Output",
                    systemImage: "arrowshape.up",
                    endpoints: midi.destinations,
                    selectedID: midi.selectedDestinationID,
                    onSelect: { midi.select($0) },
                    onRescan: { midi.refreshEndpoints() }
                )

                MIDIPortMenu(
                    role: "Input",
                    systemImage: "arrowshape.down",
                    endpoints: midi.sources,
                    selectedID: midi.selectedSourceID,
                    onSelect: { midi.selectSource($0) },
                    onRescan: { midi.refreshEndpoints() }
                )

                // Separate from the Input, because the two are routed
                // differently and that is the point of having both: a
                // Controller reaches the Output, an Input never does. See
                // MIDIThru.
                MIDIControllerMenu(
                    sources: midi.sources,
                    selectedIDs: midi.selectedControllerIDs,
                    onSet: { id, connected in midi.setController(id, connected: connected) },
                    onDisconnectAll: { midi.disconnectAllControllers() },
                    onRescan: { midi.refreshEndpoints() }
                )

                // Beside the ports rather than with the panel's own commands:
                // this is the same subject they are - how the application
                // talks to the device on the other end of the cable. Unlike
                // them it travels with the layout, which is what the popover's
                // last line says. See TransferMenu.
                TransferMenu(
                    transfer: Binding(get: { midi.transfer }, set: { midi.transfer = $0 }),
                    hasInput: midi.selectedSourceID != nil
                )
            }

            ToolbarItem {
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Divider()
                    // A Button rather than a ColorPicker directly in the menu:
                    // Menu becomes a real NSMenu, which can only host simple
                    // rows - a ColorPicker embedded in one shows up disabled
                    // rather than working. This opens the native color panel
                    // in a popover instead, off the same toolbar item.
                    Button("Custom Accent Color…") { showingAccentPicker = true }
                    if !accentColorHex.isEmpty {
                        Button("Use System Accent Color") { accentColorHex = "" }
                    }
                } label: {
                    Label("Appearance", systemImage: appearance.systemImage)
                }
                .popover(isPresented: $showingAccentPicker) {
                    // Empty accentColorHex means no custom pick yet, so the
                    // picker opens on today's resolved accent rather than
                    // some arbitrary default.
                    ColorPicker(
                        "Custom Accent Color",
                        selection: Binding(
                            get: { Color(hex: accentColorHex) ?? accentColor },
                            set: { accentColorHex = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    .padding()
                }
            }
        }
        // What makes a Finder double-click (or "Open With") on a .pwork file
        // actually load it: the WindowGroup gets the URL from AppKit and
        // hands it straight to the same path the Open… dialog uses, so the
        // saved mode (see PatchWorkDocument.opensActive) takes over from
        // there.
        .onOpenURL { url in
            // On a cold launch this fires before WindowAccessor's own async
            // capture of `window` has run, so applyWindowSize and
            // retitleWindow would silently see nil. One more run-loop turn
            // is enough to land after it.
            DispatchQueue.main.async {
                loadDocument(from: url)
                retitleWindow(for: url)
            }
        }
        .fileExporter(
            isPresented: $showingSaveDialog,
            document: savedDocument,
            contentType: .patchWorkLayout,
            defaultFilename: "Patch"
        ) { result in
            switch result {
            case .success(let url):
                // Where Save writes from now on: having just said where this
                // layout lives, saving it again should not ask twice.
                documentURL = url
                retitleWindow(for: url)
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showingOpenDialog,
            allowedContentTypes: [.patchWorkLayout]
        ) { result in
            switch result {
            case .success(let url):
                loadDocument(from: url)
                retitleWindow(for: url)
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
        .alert("PatchWork", isPresented: Binding(
            get: { fileError != nil },
            set: { if !$0 { fileError = nil } }
        )) {
            Button("OK") { fileError = nil }
        } message: {
            Text(fileError ?? "")
        }
    }

    /// The menu's own label doubles as the selection count. It is the only
    /// place that says how many are selected, and Copy acts on all of them, so
    /// the number should be readable without counting highlighted rectangles.
    private var selectionLabel: String {
        switch selection.count {
        case 0: "Edit"
        case 1: "1 Selected"
        default: "\(selection.count) Selected"
        }
    }

    // ── What is remembered ───────────────────────────────────────────────

    /// The layout as it should go to disk, with what it knows about itself.
    private var savedDocument: PatchWorkDocument {
        var sizes = windowSizes
        // The mode being saved from is the one whose size is on screen right
        // now; the other one's is whatever it was left at.
        if let live = window?.savedContentSize {
            sizes[currentMode] = live
        }
        return PatchWorkDocument(
            elements: savedElements,
            locked: locked,
            mode: currentMode,
            windows: PatchWorkDocument.windowsDictionary(sizes),
            appearance: appearance,
            accentColorHex: accentColorHex,
            transfer: midi.transfer
        )
    }

    private var currentMode: PatchWorkDocument.LayoutMode { active ? .active : .editor }

    /// The ports last in use, and the window size for a session that opens
    /// without a layout.
    private func restoreSettings() {
        let settings = AppSettings.load()
        midi.restorePorts(
            output: settings.outputName,
            input: settings.inputName,
            controllers: settings.controllerNames
        )
        if let size = settings.windowSize {
            window?.setContentSize(size, keepingTopLeft: true)
        }
    }

    private func saveSettings() {
        let ports = midi.portSettings
        var settings = AppSettings()
        settings.outputName = ports.output
        settings.inputName = ports.input
        settings.controllerNames = ports.controllers
        settings.windowSize = window?.savedContentSize
        settings.save()
    }

    /// Puts the window at the size this mode was left at, if it has one.
    private func applyWindowSize(for mode: PatchWorkDocument.LayoutMode) {
        guard let wanted = windowSizes[mode], let window else { return }
        window.setContentSize(wanted, keepingTopLeft: true)
    }

    /// What Save writes: the layout as designed, not as currently dialled in.
    ///
    /// In active mode the elements hold whatever has since been moved, and
    /// saving that would silently promote a performance into the design.
    /// Leaving active mode before writing would reach the same end; the
    /// resting snapshot is already at hand, so a save need not throw the
    /// user out of a live panel to be correct.
    private var savedElements: [CanvasElement] { restingElements ?? canvasElements }

    /// Switches between arranging the layout and using it.
    ///
    /// The values are snapshotted on the way in and put back on the way out.
    /// That is not housekeeping: from here on, an arriving message writes
    /// into the same `parameters[…].value` the Inspector edits, so without
    /// the snapshot a knob the hardware moved would quietly have become the
    /// layout's configured default.
    private func setActive(_ wanted: Bool) {
        guard wanted != active else { return }
        // Note what the mode being left is at, before the window moves.
        if let live = window?.savedContentSize {
            windowSizes[currentMode] = live
        }
        // Learn is an editor action, and an armed element in a live panel would
        // be waiting for something that can no longer be written.
        learnRun = nil
        // And the same for collecting values, which writes into the design
        // rather than into the performance.
        valueLearnID = nil
        if wanted {
            restingElements = canvasElements
            // Nothing is selected in a live panel, and the Inspector that
            // would show it is about to be out of sight anyway.
            selection.removeAll()
        } else if let resting = restingElements {
            canvasElements = resting
            restingElements = nil
        }
        active = wanted
        applyWindowSize(for: currentMode)
        // Nothing keeps playing once the panel is being edited again - the
        // same rule every other element follows, arriving from the other
        // direction here since a loop is not something a mouse release ends.
        if !wanted {
            midi.stopPlayback()
        }
        // Nothing here about routing: a Controller reaches the Output in
        // either mode, so the mode is not something the engine is told. See
        // MIDIThru.
    }

    /// One control was just operated → the wire.
    ///
    /// The active-mode check is here and not only in the gesture that cannot
    /// fire in the editor anyway: this is the path that puts bytes on the
    /// wire, so this is where the rule has to be *true* rather than merely
    /// unreachable.
    ///
    /// Failures are not raised as a dialog: a knob dragged across its range
    /// would stack up a hundred of them. The engine logs and keeps its
    /// `lastError`.
    /// Unpaced, and that is the point of the flag: a knob dragged across its
    /// range calls this sixty times a second, and putting the layout's break
    /// between each of those would build a backlog that went on arriving after
    /// the hand had stopped moving. A long SysEx still has its own chunks
    /// spaced - see MIDIEngine.send(_:paced:).
    private func operated(_ element: CanvasElement) {
        guard active else { return }
        midi.send(element.midiMessages, paced: false)
    }

    // ── Learn ────────────────────────────────────────────────────────────

    /// Arms Learn on the selected element, or cancels a run in progress.
    ///
    /// The point of it is that filling in a CC number should not need the
    /// device's manual: turn the knob and the element is that parameter. So it
    /// takes the first message that decodes and moves on - no confirmation
    /// step, because turning a knob is already the answer.
    ///
    /// Armed again while waiting, it stands down. An armed element with no way
    /// out but sending it something would be a trap when you armed the wrong
    /// one.
    private func toggleLearn() {
        if learnRun != nil {
            learnRun = nil
            return
        }
        // hasInput asked here and not only on the button that is already
        // greyed out: this is the method that arms, so this is where the rule
        // has to be true rather than merely unreachable - the same stance
        // `operated` takes about sending.
        guard hasInput else { return }
        guard !active, selection.count == 1, let id = selection.first,
              let index = canvasElements.firstIndex(where: { $0.id == id }),
              canvasElements[index].traits.contains(.sends) else { return }
        // One arm at a time. Both wait on the same wire, and `incoming` can
        // only hand a message to one of them - two lit at once would mean the
        // other was quietly doing nothing.
        valueLearnID = nil
        let count = canvasElements[index].parameters.count
        learnRun = LearnRun(elementID: id, index: 0, first: 0, last: count - 1)
    }

    /// Writes an arriving address onto the armed parameter, then moves to
    /// the next one or stands down.
    ///
    /// **From the Controller**, and from the Input only when no Controller
    /// is chosen (`Learn.accepts`). The Controller is what a hand touches;
    /// an Input alongside one is a device reporting itself back, and
    /// learning from a report would capture whatever the synth last echoed.
    /// With no Controller in the rig there is no report to mistake.
    ///
    /// What moves the run on is a **different address**, not another
    /// message: turning one knob sends a stream of them, one address dozens
    /// of values, and taking each as the next answer would put that one
    /// address on every remaining stage. An address the run has already
    /// assigned is the knob still moving, and is ignored - so every stage of
    /// a run gets a distinct parameter: A on CC 80, D on 81, S on 82, R on
    /// 83, one knob each.
    private func learn(from messages: [IncomingMessage]) {
        for message in messages {
            guard var run = learnRun else { return }
            guard let index = canvasElements.firstIndex(where: { $0.id == run.elementID }) else {
                // The element is gone. Standing down rather than returning:
                // a run left armed against nothing would keep the button lit
                // and swallow every message that followed.
                learnRun = nil
                return
            }

            let address = LearnAddress(message)
            if run.seen.contains(address) { continue }
            // One run, one protocol. The output belongs to the whole element,
            // so a second kind arriving mid-run would re-point the stages
            // already learned - four addresses that suddenly mean nothing.
            guard let wanted = Learn.output(for: message.kind) else { continue }
            if !run.seen.isEmpty, wanted != canvasElements[index].output { continue }
            // Nothing written - a Program Change onto a stage that needs an
            // address, say - so Learn keeps waiting rather than ending on a
            // message it could not use.
            guard canvasElements[index].learn(message, at: run.index) else { continue }

            run.seen.insert(address)
            if run.index >= run.last {
                learnRun = nil
            } else {
                run.index += 1
                learnRun = run
            }
        }
    }

    // ── Learn Values ─────────────────────────────────────────────────────

    /// Files arriving values into the armed element's Value List.
    ///
    /// The counterpart to `learn(from:)`, and the inverse of its dedup rule:
    /// there, a repeated address is the same knob still turning and is
    /// ignored, so that four stages get four parameters. Here a repeated
    /// *value* is skipped for the opposite reason - a list is a set of
    /// distinct numbers, and a knob sweeping back over 64 should not file it
    /// twice. Which value each message contributes, and every rule about
    /// whether it contributes at all, is in `captureValue`.
    ///
    /// Nothing is registered with Undo. A knob turned across its travel calls
    /// this sixty times a second, and one Undo step per entry is not what Undo
    /// means to someone collecting a list - see CanvasUndo. Clearing the list
    /// *is* undoable, and puts back whatever this collected.
    private func captureValues(from messages: [IncomingMessage]) {
        guard let id = valueLearnID,
              let index = canvasElements.firstIndex(where: { $0.id == id }),
              canvasElements[index].canLearnValues else {
            // The element is gone, or its Value List has been switched off.
            // Standing down rather than returning: an arm against nothing
            // would keep the checkbox lit and swallow every message after it.
            valueLearnID = nil
            return
        }
        // Worked out on a copy and written back only if something landed,
        // for the reason spelled out in `incoming`: the layout is `@State`
        // with no equality check, so *any* mutating call on it copies the
        // array and repaints every element. While this is armed every
        // message the device sends arrives here, addressed to this element
        // or not - an LFO streaming down another CC would otherwise redraw
        // the panel sixty times a second to collect nothing.
        var element = canvasElements[index]
        var collected = false
        for message in messages {
            if element.captureValue(message) { collected = true }
        }
        if collected {
            canvasElements[index] = element
        }
        // Full. Standing down says so, where a checkbox that stayed lit while
        // nothing more arrived would look like a wiring fault.
        if element.values.count >= ElementOptions.valueLearnMaxEntries {
            valueLearnID = nil
        }
    }

    /// Whether Learn can be armed: exactly one element, and one that addresses
    /// something. A Header has nothing to learn.
    private var canLearn: Bool {
        guard selection.count == 1, let id = selection.first,
              let element = canvasElements.first(where: { $0.id == id }) else { return false }
        return element.traits.contains(.sends)
    }

    /// Whether there is anything to learn *from*.
    ///
    /// Learn reads the Input and only the Input (see `Learn.accepts`), so with
    /// no Input chosen there is no device in the conversation at all. Armed
    /// there, it would wait on a port nothing arrives at - and waiting with no
    /// symptom is the failure this whole feature keeps producing, so it is
    /// said on the control instead.
    private var hasInput: Bool { midi.selectedSourceID != nil }

    /// What the Learn button's tooltip says, including why it is greyed out.
    ///
    /// Three answers rather than two, because there are two different things
    /// that can be missing and telling someone the wrong one is worse than
    /// telling them nothing.
    private var learnHelp: String {
        if learnRun != nil { return "Turn a knob on the device to address this element" }
        if !canLearn { return "Select one element that sends" }
        if !hasInput { return "Choose a MIDI Input first - Learn listens to that device" }
        return "Turn a knob on the device at the Input to address this element"
    }

    /// What the Learn button says. There is no status bar to put it in, and an
    /// armed element can only show *that* it is waiting - only words can say
    /// what for.
    private var learnLabel: String {
        guard let run = learnRun,
              let element = canvasElements.first(where: { $0.id == run.elementID })
        else { return "Learn" }
        let names = ParameterSchema.parameterNames(
            for: element.type, parameterCount: element.parameters.count
        )
        let name = names.indices.contains(run.index) ? names[run.index] : ""
        // The counter only during a real run: "1/1" on a single-parameter
        // control would be counting nothing.
        let counter = run.last > run.first
            ? "  (\(run.index - run.first + 1)/\(run.last - run.first + 1))" : ""
        return "Learn → \(name)\(counter)"
    }

    /// An action button on the panel was pressed - four different effects
    /// behind the one press.
    ///
    /// Only in active mode, for the same reason nothing else sends from the
    /// editor: rolling or pushing values while a panel is being built would
    /// overwrite the very numbers being typed. The gesture cannot fire there
    /// anyway; this is the method that acts, so this is where the rule has to
    /// be true rather than merely unreachable.
    private func triggered(_ element: CanvasElement) {
        guard active else { return }
        switch element.type {
        case .random:
            // Each rolled element goes out the same way a gesture on it would,
            // which keeps the protocol rules in the one place that has them.
            // Only what actually moved: a roll that landed on the value it
            // already held has nothing to say.
            for rolled in canvasElements.randomiseMarked() {
                midi.send(rolled.midiMessages)
            }
        case .sendAll:
            send(canvasElements.midiMessages, what: "Send All")
        case .panic:
            panic()
        case .midiPlayer:
            // A press carries no file of its own, only whichever one is
            // still loaded.
            // The output is resolved here, once, and the run keeps it: see
            // MIDIEngine.playbackSink. Nil is nothing chosen to send to, and
            // the player says so rather than starting.
            midi.player.toggle(
                send: midi.playbackSink(),
                silence: { midi.silencePlayback() },
                onError: { midi.noteFailure($0); fileError = $0 }
            )
        default:
            // Nothing else is a button - see ElementTraits.button, which is
            // what gates the gesture that calls this.
            break
        }
    }

    /// Elements were deleted from the canvas's own context menu.
    ///
    /// A Learn run points at an element by id, so deleting that element has to
    /// end the run - otherwise the toolbar button stays armed, waiting for a
    /// message it could no longer write anywhere. The Delete *key* clears it
    /// already (see deleteSelectedElement); this is the same rule for the other
    /// way in.
    private func elementsDeleted(_ ids: Set<CanvasElement.ID>) {
        if let run = learnRun, ids.contains(run.elementID) {
            learnRun = nil
        }
        if let id = valueLearnID, ids.contains(id) {
            valueLearnID = nil
        }
    }

    /// A .mid file was dropped on a MIDI Player, and starts looping.
    ///
    /// It is read and parsed here and now - before anything is playing, so a
    /// file that cannot be read says so instead of failing halfway through.
    /// Dropping is using the panel, so it only happens in active mode; the
    /// element enforces that too, and this is the method that acts.
    private func loadMIDIFile(_ url: URL) {
        guard active else { return }
        // Whatever was looping is stopped *and silenced* before the new file
        // replaces it. `load` stops by itself, but only that: dropping a
        // second file on a playing element used to leave the first one's notes
        // held, because nothing had told the wire.
        midi.stopPlayback()
        do {
            try midi.player.load(url)
        } catch {
            fileError = error.localizedDescription
            return
        }
        guard let send = midi.playbackSink() else {
            fileError = "No MIDI output is selected."
            return
        }
        midi.player.play(
            send: send,
            silence: { midi.silencePlayback() },
            onError: { midi.noteFailure($0); fileError = $0 }
        )
    }

    /// Messages that just arrived, in one batch, and which role they came in.
    ///
    /// **Both roles move the controls they address**, so the panel follows
    /// whichever is playing - the Input because the device being edited
    /// reported a change, a Controller because a hand moved something. Only
    /// in active mode: in the editor that would write into the design,
    /// changing a configured default because a device happened to be
    /// plugged in. The lamp, counts and Monitor are not gated - they write
    /// nothing into the layout, and knowing the cable works matters most
    /// while a panel is still being built.
    ///
    /// **Learn comes first, ahead of the mode gate**: an editor action, so
    /// it must work in the mode where an arriving message otherwise moves
    /// nothing, and it takes precedence over moving, or one knob turn would
    /// both assign the address and shift the control. From the Input only -
    /// see `Learn.accepts`. Both halves of Learn ask it, so the two cannot
    /// drift apart.
    ///
    /// A message in the wrong role falls through rather than being
    /// swallowed, ending at the mode gate below - where a message that
    /// moves nothing belongs anyway.
    private func incoming(_ messages: [IncomingMessage], roles: MIDIRoles) {
        if Learn.accepts(roles) {
            if learnRun != nil {
                learn(from: messages)
                return
            }
            if valueLearnID != nil {
                captureValues(from: messages)
                return
            }
        }
        guard active else { return }
        // Asked before it is written, and that is the whole point. The layout
        // is `@State`, whose setter has no equality check and no `_modify`, so
        // *any* mutating call on it copies the array and repaints every element
        // on the canvas - even for a message addressed to nothing here. A
        // controller streaming a CC this panel does not use was redrawing the
        // whole panel for it; so was every echo of a value already set.
        guard canvasElements.wouldChange(for: messages) else { return }
        canvasElements.apply(messages)
    }

    /// Everything off, now.
    ///
    /// Unpaced, and ahead of whatever is queued: a Panic that waited its turn
    /// behind a bulk transfer would not be a Panic. `cancelTransfer` drops a
    /// handshake in progress and clears the queue the next paced send would
    /// otherwise line up behind - see MIDIEngine.
    private func panic() {
        midi.cancelTransfer()
        send(MIDIPlanner.panic(), what: "Panic", paced: false)
    }

    /// Sends, and surfaces a failure rather than letting it pass
    /// silently - a MIDI send that quietly does nothing is the hardest
    /// kind of problem to notice.
    private func send(_ messages: [MIDIMessage], what: String, paced: Bool = true) {
        guard !messages.isEmpty else {
            fileError = "\(what): nothing to send. Only controls with an output configured send anything."
            return
        }
        if !midi.send(messages, paced: paced) {
            fileError = midi.lastError ?? "\(what) failed."
        }
    }

    /// Gives a window a name of its own the moment it stops being just
    /// another blank one - what tells its tab apart in the tab bar. A
    /// later manual rename (see PatchWorkApp) overrides this until the
    /// next open or save names it again.
    private func retitleWindow(for url: URL) {
        window?.title = url.deletingPathExtension().lastPathComponent
    }

    /// Opened files are security-scoped: this app IS sandboxed (see the
    /// ENABLE_APP_SANDBOX build setting), so the bracket is required, not
    /// a precaution.
    private func loadDocument(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(PatchWorkDocument.self, from: data)
            canvasElements = document.elements
            locked = document.locked
            selection.removeAll()
            // Set here rather than at each call site so both ways in - the
            // Open… panel and a Finder double-click - leave Save pointing at
            // the file that was actually read, and only when it read.
            documentURL = url
            // Only what the file actually answers: a preset that says nothing
            // about its look leaves the app set the way the user left it.
            if let saved = document.appearance { appearance = saved }
            if let saved = document.accentColorHex { accentColorHex = saved }
            // The pace goes back to the defaults when the file says nothing,
            // rather than keeping the last panel's: this one is about the
            // device on the other end, and a layout built for a modern synth
            // should not inherit the crawl a vintage one needed.
            midi.transfer = document.transfer ?? SysExTransfer()
            // The resting snapshot belongs to the layout being replaced, and
            // nothing here has asked for it back. Dropped *before* the mode
            // is set, because setActive reads it both ways: its guard returns
            // early when this document opens in the mode the window is
            // already in, which would leave the previous layout's elements
            // standing as what Save writes - and its leaving-active branch
            // would put those same elements back over the ones just read.
            restingElements = nil
            // The mode first, then the sizes, then the window. In that
            // order on purpose: switching modes notes the size of the mode it
            // is leaving, and doing it after would write the old window's
            // size over the one just read from the file.
            setActive(document.opensActive)
            // setActive only snapshots on a real transition, so a layout that
            // opens active into a window already in active mode gets none.
            // Idempotent when the transition did happen - it took this same
            // snapshot a moment ago.
            if active { restingElements = canvasElements }
            windowSizes = [:]
            for mode in [PatchWorkDocument.LayoutMode.editor, .active] {
                windowSizes[mode] = document.windowSize(for: mode)
            }
            applyWindowSize(for: currentMode)
        } catch {
            fileError = error.localizedDescription
        }
    }

    /// Writes back over the file this layout came from - what Cmd+S should do
    /// once there is somewhere to write. Without one it opens the panel
    /// instead, so the first Save on a fresh layout still asks where, and
    /// every one after that stops asking.
    private func saveDocument() {
        guard let url = documentURL else {
            showingSaveDialog = true
            return
        }
        // Bracketed for the same reason loadDocument is - the sandbox grants
        // access to a panel's URL only inside it.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            // Not .atomic: that writes a new file and renames it over this
            // one, which drops the sandbox grant that came with the URL and
            // makes the *second* save fail. Writing in place keeps the file
            // - and the permission to it - the one that was opened.
            try JSONEncoder().encode(savedDocument).write(to: url)
        } catch {
            fileError = error.localizedDescription
        }
    }

    /// Places a new element of `type` straight onto the canvas - no arm-
    /// then-click-canvas step. Successive placements cascade diagonally
    /// (wrapping after 8 steps) so they don't all land in an unreachable
    /// exact stack; `canvasElements.count` doubles as a cheap, stateless
    /// cascade index since nothing here needs it to be gap-free.
    private func placeElement(ofType type: ElementType) {
        // Nothing is placed on a locked page - that is what "the arrangement
        // is settled" has to mean.
        guard !locked else { return }
        let step: CGFloat = 24
        let cascade = CGFloat(canvasElements.count % 8) * step
        let size = CanvasLayout.defaultSize(for: type)
        let origin = CGPoint(
            x: CanvasLayout.snapped(CanvasLayout.size.width / 2 - size.width / 2 + cascade),
            y: CanvasLayout.snapped(CanvasLayout.size.height / 2 - size.height / 2 + cascade)
        )
        let rect = CGRect(origin: origin, size: size)
        let placed = CanvasElement(type: type, rect: rect)
        let previous = canvasElements
        canvasElements.append(placed)
        selection = [placed.id]
        CanvasUndo.register(undoManager, binding: $canvasElements, previous: previous, actionName: "Add \(type)")
    }

    // ── Selection commands ───────────────────────────────────────────────

    /// Every element on the page.
    ///
    /// Editor only: in active mode there is no selection to have. Selecting is
    /// not moving, so nothing about it is dangerous.
    private func selectAll() {
        guard !active else { return }
        selection = Set(canvasElements.map(\.id))
    }

    private func copySelection() {
        let chosen = canvasElements.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        clipboard = chosen
    }

    /// Pastes the clipboard, offset by one grid step, and selects what
    /// arrived - so the obvious next move (drag it, align it) acts on the copy
    /// rather than on what it was copied from.
    ///
    /// Repeated pastes land on top of each other, because each is offset from
    /// the *copied* position rather than from the last paste. A cascade would
    /// be a different feature.
    private func paste() {
        guard !active, !locked, !clipboard.isEmpty else { return }
        let pasted = clipboard.map { $0.duplicated(offset: CanvasLayout.grid) }
        let previous = canvasElements
        canvasElements.append(contentsOf: pasted)
        selection = Set(pasted.map(\.id))
        CanvasUndo.register(undoManager, binding: $canvasElements, previous: previous, actionName: "Paste")
    }

    /// Copies the selected element's Value List on its own, so it can be
    /// applied to other widgets without dragging the whole element along.
    private func copyValueList() {
        guard selection.count == 1, let id = selection.first,
              let element = canvasElements.first(where: { $0.id == id }),
              element.traits.contains(.valueList), element.useValues else { return }
        valueListClipboard = element.values
    }

    /// Whether copying the current selection's Value List is possible right
    /// now - exactly one element selected, of a type that carries a Value
    /// List, with the switch already on. Mirrors `canLearn`'s shape.
    private var canCopyValueList: Bool {
        guard selection.count == 1, let id = selection.first,
              let element = canvasElements.first(where: { $0.id == id }) else { return false }
        return element.traits.contains(.valueList) && element.useValues
    }

    /// Applies the copied Value List to every selected element that can
    /// carry one, turning its switch on. Elements in the selection that
    /// cannot (an XY Pad, say) are left untouched rather than blocking the
    /// whole paste - a mixed selection is common once Value Lists apply to
    /// several widget types.
    private func pasteValueList() {
        guard !active, !locked, let clip = valueListClipboard, !clip.isEmpty else { return }
        let previous = canvasElements
        var changed = false
        for index in canvasElements.indices
        where selection.contains(canvasElements[index].id)
            && canvasElements[index].traits.contains(.valueList) {
            canvasElements[index].useValues = true
            // Fresh ids per target, same reasoning as duplicated(): shared
            // row identities across elements would be a trap for whatever
            // reads them next.
            canvasElements[index].values = clip.map { entry in
                var fresh = entry
                fresh.id = UUID()
                return fresh
            }
            changed = true
        }
        guard changed else { return }
        CanvasUndo.register(undoManager, binding: $canvasElements, previous: previous, actionName: "Paste Value List")
    }

    private var canPasteValueList: Bool {
        guard let clip = valueListClipboard, !clip.isEmpty else { return false }
        return canvasElements.contains {
            selection.contains($0.id) && $0.traits.contains(.valueList)
        }
    }

    private func deleteSelectedElement() -> KeyPress.Result {
        guard !locked, !selection.isEmpty else { return .ignored }
        let previous = canvasElements
        let removedCount = selection.count
        canvasElements.removeAll { selection.contains($0.id) }
        selection.removeAll()
        // A run pointed at an element that no longer exists would wait for
        // ever, and `learn(from:)` would silently find nothing to write to.
        learnRun = nil
        valueLearnID = nil
        CanvasUndo.register(undoManager, binding: $canvasElements, previous: previous,
                             actionName: removedCount > 1 ? "Delete Elements" : "Delete Element")
        return .handled
    }

    private func clearSelection() -> KeyPress.Result {
        guard !selection.isEmpty else { return .ignored }
        selection.removeAll()
        return .handled
    }

    /// Tab/Shift-Tab cycles through placed elements in `canvasElements`
    /// order (their z-order, i.e. placement order) rather than spatial
    /// position - simplest well-defined order, and matches what "next"
    /// means once elements can overlap.
    ///
    /// Ignored whenever a text field is being edited - an Inspector field,
    /// the Value List not least - so native next-field navigation reaches
    /// it instead of the canvas selection jumping. Checked against the
    /// window's actual first responder rather than `windowFocused`: that
    /// FocusState lives on the canvas's own container and did not reliably
    /// clear when focus moved to a field elsewhere in the Inspector. An
    /// editing text field's first responder is its field editor, an
    /// NSTextView, not the NSTextField itself.
    private func cycleSelection(forward: Bool) -> KeyPress.Result {
        guard !(window?.firstResponder is NSTextView) else { return .ignored }
        guard !canvasElements.isEmpty else { return .ignored }
        // Tab always lands on exactly one element: it is a way of walking the
        // page, and a walk that grew the selection as it went would have no
        // way back.
        if selection.count == 1, let currentID = selection.first,
           let currentIndex = canvasElements.firstIndex(where: { $0.id == currentID }) {
            let step = forward ? 1 : -1
            let nextIndex = (currentIndex + step + canvasElements.count) % canvasElements.count
            selection = [canvasElements[nextIndex].id]
        } else if let landing = forward ? canvasElements.first?.id : canvasElements.last?.id {
            selection = [landing]
        }
        return .handled
    }
}

#Preview {
    ContentView()
}
