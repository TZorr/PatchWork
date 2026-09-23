//
//  ElementLearn.swift
//  PatchWork
//
//  Learn: point a control at whatever just arrived, so filling in a CC number
//  does not need the device's manual. Turn the knob, and the element is that
//  parameter.
//
//  The inverse of `matches`, beside it for the same reason as the planner: the
//  three are one statement about how something is addressed, written once.
//  After learning, `matches` is true for the same message.
//
//  **Learn listens to the Input, and only the Input.** The Input is the
//  device this editor is being built for, the reference the whole panel is
//  measured against, and its addresses are the ones a panel for it needs. A
//  Controller's CC numbers say nothing about the target - learning CC 12 off
//  a Microkorg while building a Nord Lead panel writes an address for the
//  wrong instrument. A device chosen as both is admitted, because it *is*
//  the Input.
//
//  This reverses an earlier rule that took the Controller as the source
//  (what a hand touches) and the Input as a report to distrust. That is a
//  fair description of a performance rig, but the wrong question for a
//  device editor, where the hand is as likely to be on the instrument's own
//  front panel. It also removed a dependency on invisible state: a version
//  in between took the Input only while no Controller was selected, and
//  controller choices persist across launches (AppSettings), so an earlier
//  session's choice silently refused every Input message with nothing on
//  screen to say so. The rule now reads off the message alone - see
//  `Learn.accepts`.
//
//  It has nothing to do with the wire: Learn reads a message and writes into
//  the layout, sending nothing, while the Controller's thru to the Output
//  runs raw whether Learn is armed or not.
//
//  The other half of the same gesture is ElementValueLearn.swift: moving a
//  control to collect the *values* it takes rather than the address it sits
//  at. That one reads the value; this one deliberately does not.
//

import Foundation

/// One address Learn has already used in this run - a *kind*, a channel and a
/// number, with no value in it.
///
/// The value is what changes while a knob turns and is the one thing Learn
/// never writes, so it is not part of what makes an address distinct either.
nonisolated struct LearnAddress: Hashable {
    let kind: IncomingMessage.Kind
    let channel: Int
    let number: Int

    init(_ incoming: IncomingMessage) {
        kind = incoming.kind
        channel = incoming.channel
        number = incoming.number
    }
}

nonisolated enum Learn {
    /// Whether a message arriving in these roles may address an element, or
    /// have its value collected - the one rule both halves of Learn share.
    ///
    /// The Input, and nothing else. See this file's header for why the target
    /// device is the only one whose addresses mean anything here, and why this
    /// takes no second argument: a rule that also consulted what was selected
    /// elsewhere is exactly the one that failed.
    ///
    /// A device chosen as both Input and Controller arrives carrying both
    /// roles and is admitted - it is the Input, wearing a second hat.
    static func accepts(_ roles: MIDIRoles) -> Bool {
        roles.contains(.input)
    }

    /// Which output a message of this kind would be learned as, or nil for one
    /// that cannot be learned at all. What lets a run refuse a second protocol
    /// without repeating the table below.
    static func output(for kind: IncomingMessage.Kind) -> OutputProtocol? {
        switch kind {
        case .controlChange: .cc
        case .nrpn: .nrpnMSBLSB
        case .programChange: .program
        case .systemExclusive: nil
        // A note is played, not addressed: it carries no parameter for a
        // control to be pointed at, and learning from one would assign
        // whichever key was pressed.
        case .noteOn, .noteOff: nil
        }
    }
}

extension CanvasElement {
    /// Points parameter `index` at what just arrived, and says whether it
    /// could.
    ///
    /// Split the way the settings are: the **address** is the parameter's own
    /// and goes into its row, while the protocol, the channel and the
    /// resolution are shared by every parameter of the element. Learning the
    /// Decay stage therefore points that stage somewhere new without moving
    /// the other three.
    ///
    /// What is written is the address, **never the value**. Learn answers
    /// "which parameter is this control", and the value that happened to be on
    /// the knob when it was turned is no part of that.
    ///
    /// The resolution moves with the protocol: an NRPN is a 14-bit parameter
    /// and a plain CC a 7-bit one, and leaving a learned NRPN in a 7-bit
    /// domain would send it back out through half its range.
    ///
    /// SysEx is not learnable and is left alone - there is nothing to compare
    /// an arriving payload against until templates exist (see `matches`).
    mutating func learn(_ incoming: IncomingMessage, at index: Int) -> Bool {
        guard parameters.indices.contains(index) else { return false }

        switch incoming.kind {
        case .controlChange:
            output = .cc
            resolution = .sevenBit
            parameters[index].cc = clamp7(incoming.number)

        case .nrpn:
            // MSB/LSB rather than LSB/MSB: the two differ only in the order
            // the address pair goes out, both address the same parameter, and
            // one of them has to be picked. This is the common spelling.
            output = .nrpnMSBLSB
            resolution = .fourteenBit
            // Split, not clamped: an NRPN address is 14 bits and its two
            // halves are the high and low seven of it. Clamping to 7 bits
            // would flatten 1234 to 127 and learn the wrong parameter.
            parameters[index].paramMSB = (incoming.number >> 7) & 0x7F
            parameters[index].paramLSB = incoming.number & 0x7F

        case .programChange:
            // A Program Change has no address beyond its channel, so there is
            // nothing to write into the row - the protocol and channel below
            // are the whole answer.
            output = .program

        case .systemExclusive:
            return false

        case .noteOn, .noteOff:
            // A note is played, not addressed: it carries no parameter for a
            // control to be pointed at, and learning from one would assign
            // whichever key happened to be pressed.
            return false
        }

        channel = clampChannel(incoming.channel)
        return true
    }
}
