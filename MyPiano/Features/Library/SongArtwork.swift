import MyPianoCore
import SwiftUI

/// A song's cover: the image chosen by the user, or one generated from its title and composer.
/// The store is passed in rather than read from the environment: table cells are hosted on their own
/// and do not inherit the app's environment objects.
struct SongArtwork: View {
    let song: LibrarySong
    let store: ArtworkStore
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = store.image(for: song.id) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    GeneratedArtwork(title: song.title, composer: song.composer)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

/// The colours of a generated cover. Songs by the same composer share a palette.
struct ArtworkPalette {
    let start: Color
    let end: Color

    /// Sixteen gradients with well spread hues, so neighbouring covers rarely look alike.
    private static let all: [ArtworkPalette] = [
        ArtworkPalette(0xFF5E62, 0xC2185B), ArtworkPalette(0xFF9966, 0xE53935), ArtworkPalette(0xFFD54F, 0xF57C00),
        ArtworkPalette(0xD4E157, 0x2E7D32), ArtworkPalette(0x66BB6A, 0x00796B), ArtworkPalette(0x26C6DA, 0x1565C0),
        ArtworkPalette(0x64B5F6, 0x283593), ArtworkPalette(0x5C6BC0, 0x6A1B9A), ArtworkPalette(0xAB47BC, 0xEC407A),
        ArtworkPalette(0xF06292, 0xFF8A65), ArtworkPalette(0xFF80AB, 0x7B1FA2), ArtworkPalette(0x26A69A, 0x1A237E),
        ArtworkPalette(0xFFB300, 0xBF360C), ArtworkPalette(0xB39DDB, 0x3949AB), ArtworkPalette(0xFF7043, 0xFFCA28),
        ArtworkPalette(0x455A64, 0x7E57C2),
    ]

    private init(_ start: UInt32, _ end: UInt32) {
        func color(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        self.start = color(start)
        self.end = color(end)
    }

    static func palette(title: String, composer: String?) -> ArtworkPalette {
        all[Int(seed(composer ?? title) % UInt64(all.count))]
    }

    /// FNV-1a then a final mix (its low bits alone are poorly spread). Unlike `hashValue`, the same on every launch.
    static func seed(_ text: String) -> UInt64 {
        var hash = text.lowercased().utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        hash ^= hash >> 33
        hash &*= 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        hash &*= 0xc4ce_b9fe_1a85_ec53
        hash ^= hash >> 33
        return hash
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// An album-style cover drawn from the title and composer: a gradient, a musical motif and the title.
struct GeneratedArtwork: View {
    let title: String
    let composer: String?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let seed = ArtworkPalette.seed(title)
            ZStack(alignment: .bottomLeading) {
                ArtworkPalette.palette(title: title, composer: composer).gradient
                Canvas { context, size in
                    Self.drawMotif(Int(seed % 4), seed: seed >> 2, side: min(size.width, size.height), in: &context)
                }
                RadialGradient(colors: [.white.opacity(0.3), .clear], center: .topLeading, startRadius: 0, endRadius: side * 0.9)
                if side >= 72 {
                    VStack(alignment: .leading, spacing: side * 0.015) {
                        if let composer {
                            Text(composer.uppercased())
                                .font(.system(size: side * 0.055, weight: .semibold))
                                .tracking(side * 0.004)
                                .opacity(0.85)
                        }
                        Text(title)
                            .font(.system(size: side * 0.105, weight: .bold))
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: side * 0.02)
                    .padding(side * 0.08)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static func drawMotif(_ motif: Int, seed: UInt64, side s: CGFloat, in context: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(.white.opacity(0.22))
        switch motif {
        case 0:
            // A large treble clef from the Leland font.
            context.draw(Text("\u{E050}").font(.custom("Leland", size: s * 0.7)).foregroundStyle(.white.opacity(0.24)),
                         at: CGPoint(x: s * 0.7, y: s * 0.38), anchor: .center)
        case 1:
            // A staff with a few notes, their heights taken from the title.
            let spacing = s * 0.055
            let top = s * 0.16
            var lines = Path()
            for line in 0..<5 { lines.addRect(CGRect(x: 0, y: top + CGFloat(line) * spacing, width: s, height: s * 0.006)) }
            context.fill(lines, with: ink)
            for index in 0..<5 {
                let step = CGFloat((seed >> (UInt64(index) * 3)) % 7)
                let center = CGPoint(x: s * (0.14 + CGFloat(index) * 0.18), y: top + step * spacing / 2 + spacing * 0.5)
                var head = context
                head.translateBy(x: center.x, y: center.y)
                head.rotate(by: .degrees(-20))
                head.fill(Path(ellipseIn: CGRect(x: -s * 0.042, y: -s * 0.03, width: s * 0.084, height: s * 0.06)), with: ink)
                context.fill(Path(CGRect(x: center.x + s * 0.034, y: center.y - s * 0.15, width: s * 0.009, height: s * 0.15)), with: ink)
            }
        case 2:
            // Concentric rings, like a record.
            let center = CGPoint(x: s * 0.85, y: s * 0.15)
            for ring in 1...10 {
                let radius = s * 0.09 * CGFloat(ring)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(.white.opacity(0.18)), lineWidth: s * 0.008)
            }
        default:
            // An octave of piano keys across the top.
            let width = s / 7
            let height = s * 0.5
            for key in 0..<7 {
                context.stroke(Path(roundedRect: CGRect(x: CGFloat(key) * width, y: -s * 0.05, width: width, height: height),
                                    cornerRadius: s * 0.02), with: .color(.white.opacity(0.24)), lineWidth: s * 0.008)
            }
            for key in [0, 1, 3, 4, 5] {
                let rect = CGRect(x: CGFloat(key + 1) * width - width * 0.3, y: -s * 0.05, width: width * 0.6, height: height * 0.62)
                context.fill(Path(roundedRect: rect, cornerRadius: s * 0.015), with: .color(.white.opacity(0.2)))
            }
        }
    }
}
