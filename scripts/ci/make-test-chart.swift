// Draws a synthetic test chart for the CI smoke test:
//   swift scripts/ci/make-test-chart.swift out.png
//
// Grey ramp, saturated and pastel patches, a hue sweep, and small bright
// lights on black (to exercise halation). 8-bit sRGB PNG.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1536
let height = 1024

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-test-chart.swift <out.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func fill(_ r: Double, _ g: Double, _ b: Double, _ rect: CGRect) {
    context.setFillColor(red: r, green: g, blue: b, alpha: 1)
    context.fill(rect)
}

// Mid-grey background.
fill(0.46, 0.46, 0.46, CGRect(x: 0, y: 0, width: width, height: height))

// Row 1 (top): 16-step grey ramp.
let margin = 48.0
let rowHeight = 176.0
let rampTop = Double(height) - margin - rowHeight
let stepWidth = (Double(width) - 2 * margin) / 16
for step in 0..<16 {
    let v = Double(step) / 15
    fill(v, v, v, CGRect(x: margin + Double(step) * stepWidth, y: rampTop, width: stepWidth, height: rowHeight))
}

// Rows 2 and 3: saturated primaries and secondaries, then natural tones.
let saturated: [(Double, Double, Double)] = [
    (0.85, 0.10, 0.10), (0.95, 0.55, 0.05), (0.95, 0.90, 0.10), (0.15, 0.65, 0.20),
    (0.10, 0.65, 0.75), (0.10, 0.25, 0.80), (0.50, 0.15, 0.75), (0.85, 0.15, 0.55),
]
let natural: [(Double, Double, Double)] = [
    (0.76, 0.57, 0.47), (0.45, 0.31, 0.24), (0.36, 0.48, 0.62), (0.33, 0.42, 0.25),
    (0.52, 0.50, 0.70), (0.38, 0.74, 0.67), (0.87, 0.80, 0.70), (0.20, 0.22, 0.26),
]
let patchWidth = (Double(width) - 2 * margin) / 8
for (index, color) in saturated.enumerated() {
    fill(color.0, color.1, color.2,
         CGRect(x: margin + Double(index) * patchWidth + 6, y: rampTop - rowHeight - 24,
                width: patchWidth - 12, height: rowHeight))
}
for (index, color) in natural.enumerated() {
    fill(color.0, color.1, color.2,
         CGRect(x: margin + Double(index) * patchWidth + 6, y: rampTop - 2 * rowHeight - 48,
                width: patchWidth - 12, height: rowHeight))
}

// Row 4 (bottom): hue sweep on the left, lights on black on the right.
let bottomHeight = rampTop - 2 * rowHeight - 72 - margin
let sweepWidth = (Double(width) - 2 * margin) * 0.6
for x in 0..<Int(sweepWidth) {
    let hue = Double(x) / sweepWidth * 6
    let c = 1.0
    let k = 1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)
    let rgb: (Double, Double, Double)
    switch Int(hue) {
    case 0: rgb = (c, k, 0)
    case 1: rgb = (k, c, 0)
    case 2: rgb = (0, c, k)
    case 3: rgb = (0, k, c)
    case 4: rgb = (k, 0, c)
    default: rgb = (c, 0, k)
    }
    fill(rgb.0, rgb.1, rgb.2, CGRect(x: margin + Double(x), y: margin, width: 1, height: bottomHeight))
}
let darkX = margin + sweepWidth + 24
let darkWidth = Double(width) - margin - darkX
fill(0.01, 0.01, 0.01, CGRect(x: darkX, y: margin, width: darkWidth, height: bottomHeight))
context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
for (index, radius) in [6.0, 12.0, 24.0].enumerated() {
    let cx = darkX + darkWidth * (Double(index) + 0.75) / 3.5
    let cy = margin + bottomHeight / 2
    context.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius))
}

guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("could not create the image\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
    exit(1)
}
