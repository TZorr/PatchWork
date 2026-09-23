//
//  PatchWorkDocument.swift
//  PatchWork
//
//  The save/load format for a canvas: its placed elements, and whether the
//  arrangement is locked. JSON in a file of its own type - `.pwork`, declared
//  in the Info.plist at the repository root. Used to drive Save's file panel
//  via .fileExporter; Open reads the same shape directly (see ContentView),
//  no FileDocument round-trip needed there.
//
//  This used to be a bare JSON array of elements, and became an object when
//  the lock arrived: a lock belongs to the layout rather than to any element
//  in it, so there was nowhere in an array to put it. Files written before
//  that do not open - no version field, no migration path, in keeping with
//  this project's own instructions. The shape changes when it needs to.
//
//  No version field even now, for the same reason: nothing has asked for one,
//  and adding compatibility machinery on the chance it might be wanted is the
//  thing those instructions rule out.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The layout file's own type, declared in Info.plist at the repository
    /// root and conforming to public.json - a .pwork *is* JSON, it just says
    /// which application it belongs to.
    ///
    /// `exportedAs` rather than a filename-extension lookup on purpose: it
    /// reads the declaration out of the bundle and traps if it is not there,
    /// so a missing or misspelt Info.plist fails loudly at launch instead of
    /// producing a dynamic type that silently matches nothing.
    static let patchWorkLayout = UTType(exportedAs: "TZorr.PatchWork.layout")
}

struct PatchWorkDocument: FileDocument, Codable {
    static var readableContentTypes: [UTType] { [.patchWorkLayout] }

    var elements: [CanvasElement]
    /// Whether the arrangement is nailed down. Saved with the layout, so a
    /// panel that was finished stays finished.
    var locked: Bool
    /// Which mode it was last saved in, so a finished panel opens ready to
    /// play rather than ready to be rearranged.
    var mode: LayoutMode?
    /// How big the window should be **in each mode**, keyed by mode name.
    ///
    /// One size per mode because a panel in use is usually not the size it
    /// was built at: arranging wants room, playing wants the panel.
    ///
    /// Optional, and the two above with it - a file with no window size is
    /// not a file with a problem, it is one that has not been given a size
    /// yet. That tolerance is not a compatibility shim: it is what these
    /// fields *mean* when absent.
    var windows: [String: [Double]]?
    /// Light/Dark, and the accent it was built to be seen in - a panel is a
    /// designed thing, and the two are part of how it looks, the same way its
    /// mode and size are part of how it opens.
    ///
    /// Optional for the reason `mode` and `windows` are: absent means the file
    /// says nothing about it, so whatever the app is already set to stands.
    /// `accentColorHex` is separately meaningful when *empty* - that is the
    /// "Use System Accent Color" answer, an explicit choice rather than no
    /// answer at all.
    var appearance: AppAppearance?
    var accentColorHex: String?
    /// How fast this panel's device can be spoken to - chunk size, the pause
    /// between units, whether to wait for a reply. See SysExTransfer.
    ///
    /// In the file for the same reason the appearance is: a panel is built
    /// for one instrument, and how slowly that instrument has to be fed is a
    /// fact about it rather than about the application. Optional in the same
    /// way too - absent means the file has never been asked, and the defaults
    /// stand.
    var transfer: SysExTransfer?

    enum LayoutMode: String, Codable {
        case editor, active
    }

    init(elements: [CanvasElement] = [], locked: Bool = false,
         mode: LayoutMode? = nil, windows: [String: [Double]]? = nil,
         appearance: AppAppearance? = nil, accentColorHex: String? = nil,
         transfer: SysExTransfer? = nil) {
        self.elements = elements
        self.locked = locked
        self.mode = mode
        self.windows = windows
        self.appearance = appearance
        self.accentColorHex = accentColorHex
        self.transfer = transfer
    }

    /// The saved size for one mode, or nil. Half a size is not a size.
    func windowSize(for mode: LayoutMode) -> CGSize? {
        guard let pair = windows?[mode.rawValue], pair.count == 2,
              pair[0] > 0, pair[1] > 0 else { return nil }
        return CGSize(width: pair[0], height: pair[1])
    }

    /// Whether it was saved in active mode. Nil reads as the editor, which is
    /// what a file that has never said anything about it means.
    var opensActive: Bool { mode == .active }

    static func windowsDictionary(_ sizes: [LayoutMode: CGSize]) -> [String: [Double]]? {
        let pairs = sizes.map { ($0.key.rawValue, [Double($0.value.width), Double($0.value.height)]) }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self = try JSONDecoder().decode(PatchWorkDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(self)
        return FileWrapper(regularFileWithContents: data)
    }
}
