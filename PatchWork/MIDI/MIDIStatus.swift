//
//  MIDIStatus.swift
//  PatchWork
//
//  What the display elements need to know, gathered into one value so it
//  can be handed down the canvas in one piece.
//
//  Previously the canvas threaded a single `outputName: String?` through to
//  the Status element. Three elements now read the MIDI side - LED wants
//  the lamp, Monitor wants the history, Status wants both port names and
//  the last few sent lines - and threading four parameters through two
//  intermediate views would mean touching all of them again the next time
//  one of these elements learns to show something new.
//
//  The activity object is passed as itself rather than copied out: it is
//  @Observable, and SwiftUI tracks whichever properties a body actually
//  reads. So a Monitor redraws when a message arrives while a Knob on the
//  same canvas does not, even though both were handed the same value.
//

import Foundation

struct MIDIStatus {
    /// The connected output and input port names, or nil for none. Nil is
    /// an ordinary state: a fresh layout has nothing chosen.
    let outputName: String?
    let inputName: String?
    /// Every connected controller's name. Several is normal, and none is a
    /// list rather than a nil so the CTRL row has one shape to render.
    let controllerNames: [String]
    /// The live noticeboard - lamp, counts and message history.
    let activity: MIDIActivity
    /// The one file player, for the MIDI Player elements to show. One for the
    /// panel rather than one per element, for the same reason as the
    /// noticeboard: there is one output, and one thing going out of it.
    let player: MIDIPlayer

    /// Nothing connected and nothing heard. For previews and for a canvas
    /// rendered without an engine behind it.
    static let idle = MIDIStatus(
        outputName: nil, inputName: nil, controllerNames: [],
        activity: MIDIActivity(), player: MIDIPlayer()
    )
}
