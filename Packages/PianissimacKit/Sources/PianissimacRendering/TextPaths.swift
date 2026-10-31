#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import CoreText
import SwiftUI

/// Short labels (fingers, note names, measure numbers) as cached vector paths.
///
/// Drawing a `Text` in a `Canvas` lays it out with CoreText on every frame; a score shows hundreds of
/// fingers, which made text layout most of the drawing time. Here each label is laid out once.
@MainActor
final class TextPaths {
    static let shared = TextPaths()

    struct Label {
        let path: Path
        /// The line box around the text, baseline at y = 0, y growing downward.
        let box: CGRect
    }

    private struct Key: Hashable {
        let text: String
        let size: CGFloat
        let weight: CGFloat
        let italic: Bool
        let rounded: Bool
        let monospacedDigits: Bool
    }

    private var labels: [Key: Label] = [:]

    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false,
               rounded: Bool = false, monospacedDigits: Bool = false) -> Label {
        let key = Key(text: text, size: (size * 4).rounded() / 4, weight: weight.rawValue, italic: italic,
                      rounded: rounded, monospacedDigits: monospacedDigits)
        if let label = labels[key] { return label }
        let label = Self.layout(key)
        labels[key] = label
        return label
    }

    private static func layout(_ key: Key) -> Label {
        var font = key.monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: key.size, weight: NSFont.Weight(key.weight))
            : NSFont.systemFont(ofSize: key.size, weight: NSFont.Weight(key.weight))
        if key.italic {
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: key.size) ?? font
        }
        if key.rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: key.size) ?? font
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: key.text, attributes: [.font: font]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        // Glyph outlines are y-up; flip them so the baseline is at y = 0 with y growing downward.
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName as String] else { continue }
            let ctFont = runFont as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let outline = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[index].x, ty: -positions[index].y)
                path.addPath(outline, transform: transform)
            }
        }
        return Label(path: Path(path), box: CGRect(x: 0, y: -ascent, width: width, height: ascent + descent))
    }
}

extension GraphicsContext {
    /// Fills a cached label so that `anchor` of its line box lies at `point`, like `draw(_:at:anchor:)` for text.
    mutating func fill(_ label: TextPaths.Label, at point: CGPoint, anchor: UnitPoint = .center, with color: Color) {
        let origin = CGPoint(x: point.x - label.box.minX - anchor.x * label.box.width,
                             y: point.y - label.box.minY - anchor.y * label.box.height)
        fill(label.path.offsetBy(dx: origin.x, dy: origin.y), with: .color(color))
    }
}
#endif
