//
//  ValueReadout.swift
//  PatchWork
//
//  The number a control shows in the middle of itself, and where its
//  value sits in its own travel. Shared by the knob and the fader the same
//  way PadDrawing/EnvelopeDrawing are shared by their families.
//
//  Everything here takes the element's own ceiling rather than assuming
//  127: resolution is per element, so a 14-bit fader's numbers run to
//  16383 while the 7-bit knob beside it still stops at 127.
//

import Foundation
import CoreGraphics
import SwiftUI

/// The raw value a bipolar readout calls zero.
///
/// Rounded up rather than down: with an even count of raw values (0..127 is
/// 128 of them) there is no single middle, and MIDI's own convention breaks
/// that
/// tie upward - CC 64 reads as "0" on a pan control, not CC 63. At 14 bits
/// the same formula lands on 8192.
func centerValue(_ range: ClosedRange<Int>) -> Int {
    (range.lowerBound + range.upperBound + 1) / 2
}

/// A value clamped into its element's own domain.
///
/// Which matters most right after a resolution changes: narrowing to 7-bit
/// leaves any stored 14-bit numbers where they are, so everything that
/// *reads* one clamps, and a stale 9000 shows as 127 rather than as
/// nonsense.
///
/// `floor` defaults to 0 for every caller but Knob/Slider, which pass
/// their element's own custom lower bound (CanvasElement.valueRange) when
/// it narrows the travel below 0.
func clampedValue(_ value: Int, floor: Int = 0, ceiling: Int) -> Int {
    min(max(value, floor), ceiling)
}

/// Where a value sits in its travel, 0...1. An out-of-range value
/// collapses to an end rather than running off the control, and a
/// nonsensical ceiling collapses to 0 rather than dividing by nothing -
/// both straight from _fraction.
func valueFraction(_ value: Int, floor: Int = 0, ceiling: Int) -> CGFloat {
    guard ceiling > floor else { return 0 }
    return max(0, min(1, CGFloat(value - floor) / CGFloat(ceiling - floor)))
}

/// `text` resolved at the largest size that fits `maxWidth`.
///
/// Shrinking beats clipping: a value with its last digit cut off reads as
/// a different value, where smaller type only reads as smaller type. The
/// floor is where it stops - past that it would be unreadable anyway, and
/// the clip takes over.
func fittedText(
    _ string: String,
    in context: GraphicsContext,
    maxWidth: CGFloat,
    color: Color = .primary,
    largest: CGFloat = 11,
    smallest: CGFloat = 7
) -> GraphicsContext.ResolvedText {
    let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    var resolved = context.resolve(styled(string, size: largest, color: color))
    var size = largest
    while size > smallest, resolved.measure(in: unbounded).width > maxWidth {
        size -= 1
        resolved = context.resolve(styled(string, size: size, color: color))
    }
    return resolved
}

/// Monospaced digits throughout: these readouts are numbers that change,
/// and proportional digits make them jitter sideways as they do.
private func styled(_ string: String, size: CGFloat, color: Color) -> Text {
    Text(string)
        .font(.system(size: size).monospacedDigit())
        .foregroundStyle(color)
}

/// A control's own reading. Always the raw value; bipolar only shifts it
/// to read against the middle of the travel, signed - "+12" against "-12"
/// being the entire point of the mode.
func valueReadout(_ value: Int, bipolar: Bool, floor: Int = 0, ceiling: Int = 127) -> String {
    let raw = clampedValue(value, floor: floor, ceiling: ceiling)
    guard bipolar else { return "\(raw)" }
    let offset = raw - centerValue(floor...ceiling)
    return offset < 0 ? "\(offset)" : "+\(offset)"
}
