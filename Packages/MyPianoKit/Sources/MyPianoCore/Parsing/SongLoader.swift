import Foundation

/// File formats MyPiano can import.
public enum SongFileFormat: String, Sendable, CaseIterable {
    case midi
    case musicXML
    case compressedMusicXML

    public static let fileExtensions: [String: SongFileFormat] = [
        "mid": .midi, "midi": .midi, "smf": .midi,
        "musicxml": .musicXML, "xml": .musicXML,
        "mxl": .compressedMusicXML,
    ]

    /// Detects the format from the content first, then from the extension.
    public static func detect(data: Data, fileExtension: String?) -> SongFileFormat? {
        if data.starts(with: Array("MThd".utf8)) { return .midi }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .compressedMusicXML }
        let head = String(decoding: data.prefix(512), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("<") || head.hasPrefix("\u{FEFF}<") { return .musicXML }
        return fileExtension.flatMap { fileExtensions[$0.lowercased()] }
    }
}

public enum SongLoadingError: Error, Equatable, Sendable {
    case unsupportedFormat
    case midi(MIDIFileError)
    case musicXML(MusicXMLError)
}

public enum SongLoader {
    public static func load(data: Data, fileExtension: String? = nil) throws(SongLoadingError) -> Song {
        switch SongFileFormat.detect(data: data, fileExtension: fileExtension) {
        case .midi:
            do { return try MIDISongBuilder.song(from: data) } catch { throw .midi(error) }
        case .musicXML, .compressedMusicXML:
            do { return try MusicXMLImporter.song(from: data) } catch { throw .musicXML(error) }
        case nil:
            throw .unsupportedFormat
        }
    }

    public static func load(contentsOf url: URL) throws -> Song {
        try load(data: Data(contentsOf: url), fileExtension: url.pathExtension)
    }
}
