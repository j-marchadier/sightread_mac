#if canImport(CoreText) && canImport(SwiftUI)
import CoreText
import SwiftUI

/// Code points of the SMuFL glyphs Pianissimac draws (Standard Music Font Layout).
enum SMuFL: UInt16 {
    case brace = 0xE000
    case gClef = 0xE050
    case fClef = 0xE062
    case timeSig0 = 0xE080
    case noteheadWhole = 0xE0A2
    case noteheadHalf = 0xE0A3
    case noteheadBlack = 0xE0A4
    case augmentationDot = 0xE1E7
    case flag8thUp = 0xE240
    case flag8thDown = 0xE241
    case flag16thUp = 0xE242
    case flag16thDown = 0xE243
    case flag32ndUp = 0xE244
    case flag32ndDown = 0xE245
    case accidentalFlat = 0xE260
    case accidentalNatural = 0xE261
    case accidentalSharp = 0xE262
    case accidentalDoubleSharp = 0xE263
    case accidentalDoubleFlat = 0xE264
    case restWhole = 0xE4E3
    case restHalf = 0xE4E4
    case restQuarter = 0xE4E5
    case rest8th = 0xE4E6
    case rest16th = 0xE4E7
    case rest32nd = 0xE4E8
    case tuplet3 = 0xE883

    static func timeSignatureDigit(_ digit: Int) -> UInt16 { timeSig0.rawValue + UInt16(max(0, min(9, digit))) }
}

/// SMuFL glyph outlines from the bundled Leland font, as SwiftUI paths in staff-space units
/// scaled to the requested staff space. Baseline at y = 0, y growing downward.
@MainActor
final class GlyphCache {
    static let shared = GlyphCache()

    struct Glyph {
        let path: Path
        let bounds: CGRect
    }

    private var fonts: [CGFloat: CTFont] = [:]
    private var glyphs: [GlyphKey: Glyph] = [:]

    private struct GlyphKey: Hashable {
        let code: UInt16
        let staffSpace: CGFloat
    }

    /// Whether the music font is available (it is registered from the app bundle).
    var isFontAvailable: Bool {
        glyph(SMuFL.noteheadBlack.rawValue, staffSpace: 10) != nil
    }

    func glyph(_ symbol: SMuFL, staffSpace: CGFloat) -> Glyph? {
        glyph(symbol.rawValue, staffSpace: staffSpace)
    }

    func glyph(_ code: UInt16, staffSpace: CGFloat) -> Glyph? {
        let key = GlyphKey(code: code, staffSpace: (staffSpace * 4).rounded() / 4)
        if let cached = glyphs[key] { return cached }
        // SMuFL fonts are designed so that one em equals the height of a five-line staff.
        let size = key.staffSpace * 4
        let font = fonts[size] ?? CTFontCreateWithName("Leland" as CFString, size, nil)
        fonts[size] = font
        var character = code
        var glyphID: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyphID, 1), glyphID != 0,
              let outline = CTFontCreatePathForGlyph(font, glyphID, nil) else { return nil }
        let path = Path(outline).applying(CGAffineTransform(scaleX: 1, y: -1))
        let glyph = Glyph(path: path, bounds: path.boundingRect)
        glyphs[key] = glyph
        return glyph
    }
}

extension GraphicsContext {
    /// Fills a glyph with its origin (left of the advance, on the baseline) at `origin`.
    func fill(_ glyph: GlyphCache.Glyph, at origin: CGPoint, with shading: GraphicsContext.Shading) {
        fill(glyph.path.applying(CGAffineTransform(translationX: origin.x, y: origin.y)), with: shading)
    }

    /// Fills a glyph horizontally centred on `x`, on the baseline `y`.
    func fill(_ glyph: GlyphCache.Glyph, centeredAt x: CGFloat, baseline y: CGFloat, with shading: GraphicsContext.Shading) {
        fill(glyph, at: CGPoint(x: x - glyph.bounds.midX, y: y), with: shading)
    }
}
#endif
