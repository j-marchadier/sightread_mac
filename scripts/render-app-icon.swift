#!/usr/bin/env swift
// Renders the MyPiano app icon at every macOS size into the AppIcon asset catalog.
// The icon is drawn as vectors at each size, so small sizes stay crisp.
//
// Usage: swift scripts/render-app-icon.swift [output .appiconset directory]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "MyPiano/Resources/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ colors: [CGColor], in context: CGContext, from start: CGPoint, to end: CGPoint) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

/// A rectangle whose bottom corners only are rounded (piano keys hang from the top).
func keyPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
    path.closeSubpath()
    return path
}

/// Draws the icon in a 1024-point coordinate space (origin bottom-left).
func drawIcon(in context: CGContext) {
    // macOS icon grid: an 824-point rounded square centered in the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0x4338CA))
    context.fillPath()
    context.restoreGState()

    // Indigo to violet background.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    linearGradient([color(0x4F46E5), color(0x7C3AED), color(0xA855F7)], in: context,
                   from: CGPoint(x: tile.minX, y: tile.maxY), to: CGPoint(x: tile.maxX, y: tile.minY))
    // Soft light from the top.
    linearGradient([color(0xFFFFFF, alpha: 0.18), color(0xFFFFFF, alpha: 0)], in: context,
                   from: CGPoint(x: 512, y: tile.maxY), to: CGPoint(x: 512, y: 560))
    context.restoreGState()

    // Three white keys and two black keys.
    let whiteWidth: CGFloat = 168
    let gap: CGFloat = 14
    let keysWidth = whiteWidth * 3 + gap * 2
    let top: CGFloat = 760
    let whiteHeight: CGFloat = 520
    let left = 512 - keysWidth / 2

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: color(0x1E1B4B, alpha: 0.45))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    for index in 0..<3 {
        let rect = CGRect(x: left + CGFloat(index) * (whiteWidth + gap), y: top - whiteHeight,
                          width: whiteWidth, height: whiteHeight)
        context.saveGState()
        context.addPath(keyPath(rect, radius: 34))
        context.clip()
        linearGradient([color(0xFFFFFF), color(0xF1F0FA), color(0xDCD8EE)], in: context,
                       from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY))
        context.restoreGState()
    }
    context.endTransparencyLayer()
    context.restoreGState()

    let blackWidth: CGFloat = 104
    let blackHeight: CGFloat = 318
    for index in 1...2 {
        let center = left + CGFloat(index) * (whiteWidth + gap) - gap / 2
        let rect = CGRect(x: center - blackWidth / 2, y: top - blackHeight, width: blackWidth, height: blackHeight)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x000000, alpha: 0.35))
        context.addPath(keyPath(rect, radius: 22))
        context.setFillColor(color(0x1C1A2E))
        context.fillPath()
        context.restoreGState()

        // Bevel highlight on the key face.
        context.saveGState()
        context.addPath(keyPath(rect.insetBy(dx: 12, dy: 0).offsetBy(dx: 0, dy: 22), radius: 16))
        context.clip()
        linearGradient([color(0x4A4566), color(0x26233A)], in: context,
                       from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY + 22))
        context.restoreGState()
    }

    // The key bed: a thin dark band the keys hang from.
    let bed = CGRect(x: left - 18, y: top, width: keysWidth + 36, height: 34)
    context.saveGState()
    context.addPath(CGPath(roundedRect: bed, cornerWidth: 14, cornerHeight: 14, transform: nil))
    context.setFillColor(color(0x1E1B4B, alpha: 0.85))
    context.fillPath()
    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)
    return context.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(path)") }
}

var entries: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        write(render(pixels: size * scale), to: "\(output)/\(name)")
        entries.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(size)x\#(size)" }"#)
    }
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! contents.write(toFile: "\(output)/Contents.json", atomically: true, encoding: .utf8)
print("Rendered \(entries.count) icons into \(output)")
