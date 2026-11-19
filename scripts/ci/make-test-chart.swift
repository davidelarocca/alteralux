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

struct RGB {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

func fill(_ color: RGB, _ rect: CGRect) {
    context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    context.fill(rect)
}

// Mid-grey background.
fill(RGB(0.46, 0.46, 0.46), CGRect(x: 0, y: 0, width: width, height: height))

// Row 1 (top): 16-step grey ramp.
let margin = 48.0
let rowHeight = 176.0
let rampTop = Double(height) - margin - rowHeight
let stepWidth = (Double(width) - 2 * margin) / 16
for step in 0..<16 {
    let level = Double(step) / 15
    fill(
        RGB(level, level, level),
        CGRect(x: margin + Double(step) * stepWidth, y: rampTop, width: stepWidth, height: rowHeight))
}

// Rows 2 and 3: saturated primaries and secondaries, then natural tones.
let saturated = [
    RGB(0.85, 0.10, 0.10), RGB(0.95, 0.55, 0.05), RGB(0.95, 0.90, 0.10), RGB(0.15, 0.65, 0.20),
    RGB(0.10, 0.65, 0.75), RGB(0.10, 0.25, 0.80), RGB(0.50, 0.15, 0.75), RGB(0.85, 0.15, 0.55),
]
let natural = [
    RGB(0.76, 0.57, 0.47), RGB(0.45, 0.31, 0.24), RGB(0.36, 0.48, 0.62), RGB(0.33, 0.42, 0.25),
    RGB(0.52, 0.50, 0.70), RGB(0.38, 0.74, 0.67), RGB(0.87, 0.80, 0.70), RGB(0.20, 0.22, 0.26),
]
let patchWidth = (Double(width) - 2 * margin) / 8
for (index, color) in saturated.enumerated() {
    fill(
        color,
        CGRect(
            x: margin + Double(index) * patchWidth + 6, y: rampTop - rowHeight - 24,
            width: patchWidth - 12, height: rowHeight))
}
for (index, color) in natural.enumerated() {
    fill(
        color,
        CGRect(
            x: margin + Double(index) * patchWidth + 6, y: rampTop - 2 * rowHeight - 48,
            width: patchWidth - 12, height: rowHeight))
}

// Row 4 (bottom): hue sweep on the left, lights on black on the right.
let bottomHeight = rampTop - 2 * rowHeight - 72 - margin
let sweepWidth = (Double(width) - 2 * margin) * 0.6
for column in 0..<Int(sweepWidth) {
    let hue = Double(column) / sweepWidth * 6
    let full = 1.0
    let ramp = 1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)
    let color: RGB
    switch Int(hue) {
    case 0: color = RGB(full, ramp, 0)
    case 1: color = RGB(ramp, full, 0)
    case 2: color = RGB(0, full, ramp)
    case 3: color = RGB(0, ramp, full)
    case 4: color = RGB(ramp, 0, full)
    default: color = RGB(full, 0, ramp)
    }
    fill(color, CGRect(x: margin + Double(column), y: margin, width: 1, height: bottomHeight))
}
let darkX = margin + sweepWidth + 24
let darkWidth = Double(width) - margin - darkX
fill(RGB(0.01, 0.01, 0.01), CGRect(x: darkX, y: margin, width: darkWidth, height: bottomHeight))
context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
for (index, radius) in [6.0, 12.0, 24.0].enumerated() {
    let centerX = darkX + darkWidth * (Double(index) + 0.75) / 3.5
    let centerY = margin + bottomHeight / 2
    context.fillEllipse(
        in: CGRect(x: centerX - radius, y: centerY - radius, width: 2 * radius, height: 2 * radius))
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
