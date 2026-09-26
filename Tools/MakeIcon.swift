//
//  MakeIcon.swift
//  PatchWork — Tools
//
//  Draws the asset catalogue's ten PNGs, plus `icon.png` at the project root
//  as a 1024 preview.
//
//  The earlier icon was a render with the transparency checkerboard baked in,
//  which showed as a grey frame round the plate in the Dock. This one is
//  drawn from scratch, so everything outside the plate is truly transparent.
//
//  The look follows Audio Converter's icon: the same top-lit dark squircle and
//  faint bevel, with an orange neon trace. Here the trace is an ADSR envelope —
//  a short lead-in, a straight attack, exponential decay to the sustain level,
//  the sustain plateau, an exponential release, and a short tail.
//
//  Re-run with `./Tools/make_icon.sh`.
//

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// ---------------------------------------------------------- the envelope

/// The trace in plate units: x and y in 0…1, y up.
func envelopePoints() -> [CGPoint] {
    let base: CGFloat = 0.34, peak: CGFloat = 0.68, sustain: CGFloat = 0.50
    let x0: CGFloat = 0.11      // lead-in starts
    let xA: CGFloat = 0.20      // attack starts
    let xP: CGFloat = 0.33      // peak
    let xD: CGFloat = 0.50      // decay has settled
    let xS: CGFloat = 0.66      // release starts
    let xR: CGFloat = 0.83      // release has settled
    let x1: CGFloat = 0.89      // tail ends

    var pts: [CGPoint] = [CGPoint(x: x0, y: base), CGPoint(x: xA, y: base)]

    // Attack: nearly straight, a touch of RC-charge bow so it reads as analog.
    let steps = 60
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let bow = (1 - exp(-2.2 * t)) / (1 - exp(-2.2))
        pts.append(CGPoint(x: xA + (xP - xA) * t, y: base + (peak - base) * (0.35 * bow + 0.65 * t)))
    }
    // Decay and release: exponential, normalised to land exactly on target.
    func exponential(from x: CGFloat, to xEnd: CGFloat, from y: CGFloat, to yEnd: CGFloat) {
        let k: CGFloat = 4.5
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let e = (exp(-k * t) - exp(-k)) / (1 - exp(-k))
            pts.append(CGPoint(x: x + (xEnd - x) * t, y: yEnd + (y - yEnd) * e))
        }
    }
    exponential(from: xP, to: xD, from: peak, to: sustain)
    pts.append(CGPoint(x: xS, y: sustain))
    exponential(from: xS, to: xR, from: sustain, to: base)
    pts.append(CGPoint(x: x1, y: base))
    return pts
}

// ---------------------------------------------------------- drawing

func squirclePath(rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let rx = rect.width / 2, ry = rect.height / 2
    let samples = 1440
    for i in 0...samples {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
        let ct = cos(t), st = sin(t)
        let x = cx + copysign(pow(abs(ct), 2 / exponent), ct) * rx
        let y = cy + copysign(pow(abs(st), 2 / exponent), st) * ry
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.012
    let plate = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let shape = squirclePath(rect: plate)

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Top-lit near-black, as Audio Converter.
    let g = CGGradient(colorsSpace: space,
                       colors: [CGColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1),
                                CGColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // The trace, built in plate coordinates.
    let trace = CGMutablePath()
    for (i, p) in envelopePoints().enumerated() {
        let q = CGPoint(x: plate.minX + p.x * plate.width, y: plate.minY + p.y * plate.height)
        if i == 0 { trace.move(to: q) } else { trace.addLine(to: q) }
    }
    // Small sizes get a relatively heavier line, or it vanishes in the menu bar.
    let weight: CGFloat = size <= 32 ? 1.6 : (size <= 64 ? 1.25 : 1)
    let tube = s * 0.032 * weight

    func stroke(width: CGFloat, color: CGColor, glow: CGFloat = 0, glowColor: CGColor? = nil) {
        ctx.saveGState()
        if glow > 0, let glowColor { ctx.setShadow(offset: .zero, blur: glow, color: glowColor) }
        ctx.addPath(trace)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color)
        ctx.strokePath()
        ctx.restoreGState()
    }

    let orange = CGColor(srgbRed: 1.00, green: 0.42, blue: 0.12, alpha: 1)
    // The tube, twice: once casting a wide soft halo, once a tighter one.
    // Glow comes only from the blur, so it fades out without banding.
    stroke(width: tube, color: orange,
           glow: s * 0.07, glowColor: CGColor(srgbRed: 1, green: 0.30, blue: 0.04, alpha: 0.85))
    stroke(width: tube, color: orange,
           glow: s * 0.022, glowColor: CGColor(srgbRed: 1, green: 0.40, blue: 0.10, alpha: 0.9))
    // Then its hot core.
    stroke(width: tube * 0.42, color: CGColor(srgbRed: 1.00, green: 0.72, blue: 0.45, alpha: 0.95),
           glow: tube * 0.35, glowColor: CGColor(srgbRed: 1, green: 0.65, blue: 0.35, alpha: 1))

    // A faint inner top edge, like Audio Converter's bevel.
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

// ------------------------------------------------------------------ output

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("cannot write \(url.path)\n".utf8)); exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("failed to encode \(url.path)\n".utf8)); exit(1)
    }
}

let variants: [(name: String, size: Int)] = [
    ("icon_16x16@1x", 16), ("icon_16x16@2x", 32),
    ("icon_32x32@1x", 32), ("icon_32x32@2x", 64),
    ("icon_128x128@1x", 128), ("icon_128x128@2x", 256),
    ("icon_256x256@1x", 256), ("icon_256x256@2x", 512),
    ("icon_512x512@1x", 512), ("icon_512x512@2x", 1024),
]

let iconSet = root.appendingPathComponent("PatchWork/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var rendered: [Int: CGImage] = [:]
for variant in variants {
    let image = rendered[variant.size] ?? render(size: variant.size)
    rendered[variant.size] = image
    write(image, to: iconSet.appendingPathComponent("\(variant.name).png"))
    print("  \(variant.name).png  \(variant.size)×\(variant.size)")
}

write(rendered[1024]!, to: root.appendingPathComponent("icon.png"))
print("  icon.png  1024×1024")
