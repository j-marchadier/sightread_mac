import Foundation

/// Locates test data in the repository from this source file's path.
enum Fixtures {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // MyPianoCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MyPianoKit

    static let repositoryRoot = packageRoot
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    /// MIDI files shipped as the built-in library.
    static let builtinSongs = repositoryRoot.appendingPathComponent("MyPiano/Resources/BuiltinSongs")

    static let directory = packageRoot.appendingPathComponent("Tests/MyPianoCoreTests/Fixtures")

    static func builtinSong(_ name: String) throws -> Data {
        try Data(contentsOf: builtinSongs.appendingPathComponent(name))
    }

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(relativePath))
    }

    static func string(_ relativePath: String) throws -> String {
        try String(decoding: data(relativePath), as: UTF8.self)
    }
}
