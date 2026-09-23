//
//  MIDIThru.swift
//  PatchWork
//
//  The routing rule, in one place because it is a rule and not a detail.
//
//      Controller → Out.    Input → nothing.
//
//  Two listening roles, not symmetrical.
//
//  An **Input** is the device being edited. What arrives on it is that
//  device reporting its own parameters back, so it is shown, and in active
//  mode moves the control that addresses it (IncomingControl) - but it is
//  **never** forwarded to the Output. Sending a device its own report back
//  would achieve nothing at best, and at worst echo: it reports, we send it
//  back, it reports again.
//
//  A **Controller** is a keyboard or fader box. Reaching the Output is its
//  entire reason to exist, so what arrives is forwarded there untouched, in
//  **either mode** - playing and operating the gear is part of building a
//  panel for it.
//
//  Forwarding an Input's *notes* would cover the one-device case, where a
//  synth set to Local Off makes no sound until its own keyboard comes back
//  through the app. **Deliberately not done**: no In → Out path at all. With
//  a separate master keyboard on the Controller, playing belongs there.
//

import Foundation

enum MIDIThru {
    /// Whether a Controller forwards this to the Output.
    ///
    /// Notes and Control Change, both of them, in both modes. A note is
    /// playing and a CC is operating,
    /// and neither waits for the panel to go live: a Controller was chosen in
    /// order to reach the Output, and the editor is where the gear is being
    /// listened to most. Nothing here reads the mode, so there is no mode for
    /// a later edit to get the wrong way round.
    /// **Control Change is what carries NRPN too** - real gear sends an NRPN
    /// as three or four ordinary Control Changes (CC 99, CC 98, CC 6, CC 38),
    /// so forwarding raw CCs passes the whole sequence through in order.
    /// There is no NRPN type to list here and nothing to reassemble.
    ///
    /// Deliberately not everything that arrives:
    ///
    /// - **Clock and timecode** would flood the port. They never even reach
    ///   here - MIDIStreamParser drops System Real Time as it reads.
    /// - **SysEx** is none of this app's business. A control surface
    ///   announcing itself does send one, and relaying that to a synth is
    ///   not something to do by accident.
    /// - **Pitch bend, aftertouch and program change** are left out for now,
    ///   each being one more word in the list.
    ///   Pitch bend and aftertouch are the two most likely to be wanted next;
    ///   they are one line each, right here.
    static func forwards(_ message: RawMIDIMessage) -> Bool {
        switch message.status & 0xF0 {
        case 0x80, 0x90, 0xB0: return true
        default: return false
        }
    }
}
