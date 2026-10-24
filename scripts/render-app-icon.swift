#!/usr/bin/env swift
// Renders the MyPiano app icon (Liquid Glass style) at every macOS size into the AppIcon asset catalog.
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

/// Fills `path` with a vertical gradient (top color first).
func fillVertical(_ path: CGPath, in context: CGContext, _ colors: [CGColor]) {
    let box = path.boundingBox
    context.saveGState()
    context.addPath(path)
    context.clip()
    linearGradient(colors, in: context, from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY))
    context.restoreGState()
}

/// Strokes the inside edge of `path` with a vertical gradient: the lit rim of a glass shape.
func rim(_ path: CGPath, width: CGFloat, in context: CGContext, top: CGColor, bottom: CGColor) {
    let box = path.boundingBox
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.addPath(path)
    context.setLineWidth(width * 2)
    context.replacePathWithStrokedPath()
    context.clip()
    linearGradient([top, bottom], in: context, from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY))
    context.restoreGState()
}

/// Draws the icon in a 1024-point coordinate space (origin bottom-left), in the Liquid Glass style:
/// a vivid tile with a lit rim, and keys made of frosted and smoked glass.
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

    // Indigo to violet background with a soft glow behind the keys.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    linearGradient([color(0x4F46E5), color(0x7C3AED), color(0xC026D3)], in: context,
                   from: CGPoint(x: tile.minX, y: tile.maxY), to: CGPoint(x: tile.maxX, y: tile.minY))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha: 0.28), color(0xFFFFFF, alpha: 0)] as CFArray, locations: nil)!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
    context.restoreGState()
    rim(tilePath, width: 5, in: context, top: color(0xFFFFFF, alpha: 0.55), bottom: color(0xFFFFFF, alpha: 0.12))

    // Three white keys and two black keys.
    let whiteWidth: CGFloat = 168
    let gap: CGFloat = 14
    let keysWidth = whiteWidth * 3 + gap * 2
    let top: CGFloat = 760
    let whiteHeight: CGFloat = 520
    let left = 512 - keysWidth / 2

    // Frosted glass white keys.
    for index in 0..<3 {
        let rect = CGRect(x: left + CGFloat(index) * (whiteWidth + gap), y: top - whiteHeight,
                          width: whiteWidth, height: whiteHeight)
        let path = keyPath(rect, radius: 36)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x1E1B4B, alpha: 0.40))
        context.addPath(path)
        context.setFillColor(color(0xFFFFFF, alpha: 0.55))
        context.fillPath()
        context.restoreGState()
        fillVertical(path, in: context, [color(0xFFFFFF, alpha: 0.42), color(0xF5F3FF, alpha: 0.25), color(0xEDE9FE, alpha: 0.38)])
        rim(path, width: 4, in: context, top: color(0xFFFFFF, alpha: 0.95), bottom: color(0xFFFFFF, alpha: 0.55))
    }

    // Smoked glass black keys with a specular streak.
    let blackWidth: CGFloat = 104
    let blackHeight: CGFloat = 318
    for index in 1...2 {
        let center = left + CGFloat(index) * (whiteWidth + gap) - gap / 2
        let rect = CGRect(x: center - blackWidth / 2, y: top - blackHeight, width: blackWidth, height: blackHeight)
        let path = keyPath(rect, radius: 26)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, alpha: 0.40))
        context.addPath(path)
        context.setFillColor(color(0x1C1A2E, alpha: 0.96))
        context.fillPath()
        context.restoreGState()
        fillVertical(path, in: context, [color(0x5B5680, alpha: 0.55), color(0x1C1A2E, alpha: 0)])
        let streak = CGPath(roundedRect: CGRect(x: rect.minX + 16, y: rect.minY + 40, width: 14, height: rect.height - 70),
                            cornerWidth: 7, cornerHeight: 7, transform: nil)
        fillVertical(streak, in: context, [color(0xFFFFFF, alpha: 0.38), color(0xFFFFFF, alpha: 0)])
        rim(path, width: 3, in: context, top: color(0xFFFFFF, alpha: 0.45), bottom: color(0xFFFFFF, alpha: 0.15))
    }

    // The key bed: a thin glass bar the keys hang from.
    let bed = CGPath(roundedRect: CGRect(x: left - 18, y: top, width: keysWidth + 36, height: 34),
                     cornerWidth: 17, cornerHeight: 17, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: color(0x1E1B4B, alpha: 0.35))
    context.addPath(bed)
    context.setFillColor(color(0x1E1B4B, alpha: 0.55))
    context.fillPath()
    context.restoreGState()
    rim(bed, width: 3, in: context, top: color(0xFFFFFF, alpha: 0.6), bottom: color(0xFFFFFF, alpha: 0.1))

    // Specular sheen across the top of the tile.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let sheen = CGPath(ellipseIn: CGRect(x: 40, y: 640, width: 944, height: 420), transform: nil)
    fillVertical(sheen, in: context, [color(0xFFFFFF, alpha: 0.20), color(0xFFFFFF, alpha: 0)])
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
