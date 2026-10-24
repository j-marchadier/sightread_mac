import AppKit
import CryptoKit
import Foundation
import Observation

/// Cover images chosen by the user, stored as square JPEGs in Application Support.
/// Songs without one show a generated cover (`GeneratedArtwork`).
@MainActor
@Observable
final class ArtworkStore {
    /// Bumped on every change so views showing a cover refresh.
    private(set) var revision = 0

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var cache: [String: NSImage] = [:]
    @ObservationIgnored private var missing: Set<String> = []

    /// Side of the stored images, in pixels.
    static let side = 800

    init(folder: URL) {
        self.folder = folder
    }

    func image(for id: String) -> NSImage? {
        _ = revision
        if let image = cache[id] { return image }
        if missing.contains(id) { return nil }
        guard let image = NSImage(contentsOf: fileURL(for: id)) else {
            missing.insert(id)
            return nil
        }
        cache[id] = image
        return image
    }

    /// Crops `image` to a centered square, scales it down and saves it as the song's cover.
    func setImage(_ image: NSImage, for id: String) throws {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let crop = min(source.width, source.height)
        let side = min(Self.side, crop)
        guard let square = source.cropping(to: CGRect(x: (source.width - crop) / 2, y: (source.height - crop) / 2,
                                                      width: crop, height: crop)),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileReadCorruptFile) }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: id), options: .atomic)
        cache[id] = NSImage(cgImage: scaled, size: NSSize(width: side, height: side))
        missing.remove(id)
        revision += 1
    }

    /// Goes back to the generated cover.
    func removeImage(for id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        cache[id] = nil
        missing.insert(id)
        revision += 1
    }

    /// Song ids may contain any character: the file is named after their hash.
    private func fileURL(for id: String) -> URL {
        let hash = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash).appendingPathExtension("jpg")
    }
}
