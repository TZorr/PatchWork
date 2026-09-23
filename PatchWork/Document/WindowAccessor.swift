//
//  WindowAccessor.swift
//  PatchWork
//
//  Handing the NSWindow up to SwiftUI, because a window size is not something
//  SwiftUI itself will discuss: `.defaultSize` says how big to open and
//  nothing says how big to *become*, which is exactly what switching modes and
//  opening a layout have to do.
//
//  A zero-sized background view rather than reaching for NSApp.windows: this
//  application will grow a second window sooner or later - a settings sheet,
//  an about box - and "the first window" would then be a coin toss. This one
//  is the window this view is in, by construction.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Not in makeNSView's own call: the view has no window until it is
        // added to one, which happens after this returns.
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}

extension NSWindow {
    /// The size to store, and the exact inverse of `setContentSize`.
    ///
    /// Not `contentLayoutRect`, which leaves out the space under the title
    /// bar: storing that and restoring it through setContentSize would shave a
    /// little off the window on every round trip, and a window that shrinks
    /// each time it is saved and reopened is a slow, baffling bug.
    var savedContentSize: CGSize {
        contentRect(forFrameRect: frame).size
    }

    /// Resizes to `size` about the window's own top-left, which is where a
    /// title bar is: growing a window downward from the corner someone is
    /// looking at is far less startling than growing it around its middle.
    func setContentSize(_ size: CGSize, keepingTopLeft: Bool) {
        guard keepingTopLeft else {
            setContentSize(size)
            return
        }
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        setContentSize(size)
        setFrameTopLeftPoint(topLeft)
    }
}
