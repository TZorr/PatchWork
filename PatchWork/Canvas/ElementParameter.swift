//
//  ElementParameter.swift
//  PatchWork
//
//  One addressable part of an element - what the Inspector's lower table
//  edits one row of. An envelope's four stages are four parameters: each
//  has an address of its own, and on older gear each is a SysEx string of
//  its own.
//
//  What a parameter does NOT carry is the protocol, the channel or the
//  resolution: one envelope speaks one protocol on one channel, so those
//  stay on the element and are set in the form above the table.
//
//  Every element always has at least one entry in `parameters`, including
//  the single-parameter types that could just as well have kept their
//  address on the element itself. The table, the widgets and any future
//  sender then read one uniform array with no per-type branch.
//

import Foundation

struct ElementParameter: Identifiable, Codable {
    var id = UUID()
    /// The CC number, when the element's output is CC. A controller
    /// number, not the high half of anything - which is why NRPN's own
    /// pair is separate rather than this doubling as its MSB.
    var cc: Int = 0
    /// NRPN's parameter number, two 7-bit halves (CC 99 and CC 98). Both
    /// NRPN variants carry both - they differ in the order their data
    /// entry messages go out, not in which fields exist.
    var paramMSB: Int = 0
    var paramLSB: Int = 0
    /// The Bank Select that precedes a Program Change - CC 0 and CC 32.
    /// Named for what they do rather than sharing the NRPN pair's storage:
    /// a field whose meaning depends on a dropdown three rows up is a
    /// thing to look up rather than read.
    var bankMSB: Int = 0
    var bankLSB: Int = 0
    /// The SysEx message, typed the way a manual prints it.
    var sysex: String = ""
    /// What this parameter holds. The last column whatever the protocol:
    /// a stage is usually dragged on the canvas, and the table is the one
    /// place it can be typed.
    var value: Int = 0
    /// This axis sent backwards against where the point sits, so the field
    /// still reads and drags the ordinary way while the number leaving on
    /// it runs the other direction. Only the pads read it.
    ///
    /// It lives on the parameter rather than the element because an axis
    /// *is* a parameter. One flag per axis-parameter means the plain pad's
    /// two and the quad's four are the same mechanism rather than two, and
    /// the count comes out right on its own.
    var inverted: Bool = false
}

/// One entry of a control's value list - the pairs the lower table shows
/// instead of the parameters when Value List is on. A named struct rather
/// than a bare name/number pair: it reads better at the call sites and
/// costs nothing.
struct ValueEntry: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var number: Int = 0
}
