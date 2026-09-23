//
//  CanvasUndo.swift
//  PatchWork
//
//  One Undo step per completed layout edit - move, resize, add, delete,
//  duplicate, paste - registered by the call site that just made the
//  change, snapshotting canvasElements *before* it. Undo and redo are the
//  same operation run in either direction, so one function does both:
//  undoing swaps the current array back to the snapshot and, in the same
//  breath, registers the array it just replaced as the next redo.
//
//  Scoped to the layout array alone, not to every field an Inspector row
//  can edit: those commit on every keystroke, and one Undo step per
//  keystroke is not what Undo means to someone typing a name.
//
//  Active-mode control operation (turning a live knob) never calls this -
//  see EditorCanvasView's onOperate - because that is not an edit to undo,
//  it is what the panel is for. It already has its own way back: leaving
//  active mode restores `restingElements`, the layout as it was when the
//  panel went live.
//
//  Registered against the UndoManager itself rather than a dedicated anchor
//  object - ContentView and EditorCanvasView are structs and cannot be a
//  registerUndo target, and the manager is as good an anchor as any, since
//  it is guaranteed to outlive the closure that needs it.
//

import SwiftUI

enum CanvasUndo {
    static func register(
        _ undoManager: UndoManager?,
        binding: Binding<[CanvasElement]>,
        previous: [CanvasElement],
        actionName: String
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoManager) { manager in
            let current = binding.wrappedValue
            binding.wrappedValue = previous
            register(manager, binding: binding, previous: current, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
