#!/usr/bin/env swift
// Generates Resources/AppIcon.icns. Run: ./scripts/make-icon.sh
//
// The mark is a squircle split on the diagonal: a Korean glyph on the dark half, a Latin one
// on the light half. At 16 points the glyphs stop being legible but the two-tone diagonal
// still reads as "two of something", which is the point.
import AppKit
import CoreGraphics

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)

    // macOS icons leave transparent padding around the shape.
    let inset = size * 0.085
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = box.width * 0.2237                       // the standard squircle approximation
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Dark half.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [CGColor(red: 0.22, green: 0.20, blue: 0.62, alpha: 1),
                  CGColor(red: 0.42, green: 0.24, blue: 0.78, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: box.minX, y: box.maxY),
                               end: CGPoint(x: box.maxX, y: box.minY), options: [])

    // Light half, cut on the diagonal.
    let diagonal = CGMutablePath()
    diagonal.move(to: CGPoint(x: box.minX, y: box.minY))
    diagonal.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
    diagonal.addLine(to: CGPoint(x: box.maxX, y: box.minY))
    diagonal.closeSubpath()
    context.addPath(diagonal)
    context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.99, alpha: 1))
    context.fillPath()
    context.restoreGState()

    func drawGlyph(_ text: String, center: CGPoint, pointSize: CGFloat, color: NSColor) {
        let font = NSFont.systemFont(ofSize: pointSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    let glyphSize = box.width * 0.40
    drawGlyph("가", center: CGPoint(x: box.minX + box.width * 0.33, y: box.minY + box.height * 0.66),
              pointSize: glyphSize, color: .white)
    drawGlyph("A", center: CGPoint(x: box.minX + box.width * 0.68, y: box.minY + box.height * 0.33),
              pointSize: glyphSize, color: NSColor(red: 0.22, green: 0.20, blue: 0.62, alpha: 1))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for entry in sizes {
    let rep = draw(size: entry.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(entry.name).png"))
}
print("wrote \(iconset.path)")
