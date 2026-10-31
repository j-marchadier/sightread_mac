import Foundation

/// Songs shipped with the app, described by `BuiltinSongs/catalog.json`.
public struct BuiltinCatalog: Sendable, Decodable, Equatable {
    public struct Entry: Sendable, Decodable, Equatable, Identifiable {
        /// Stable identifier, never reused, so settings and progress survive app updates.
        public let id: String
        public let file: String
        /// Titles by language code ("fr", "en").
        public let title: [String: String]
        public let composer: String?
        public let license: String
        public let licenseURL: String
        public let sourceURL: String

        /// Title in the preferred language, falling back to French then any title.
        public func title(preferredLanguages: [String]) -> String {
            for language in preferredLanguages {
                let code = String(language.prefix(2))
                if let value = title[code] { return value }
            }
            return title["fr"] ?? title.values.first ?? file
        }

        /// The library entry of an already installed song, updated for this catalog: the title follows the
        /// language unless the user renamed the song, and the licence follows the catalog. Everything else
        /// the user changed or built up (title, composer, difficulty, favourite, settings, history dates)
        /// is kept. `nil` when nothing changes.
        public func refreshing(_ existing: LibrarySong, preferredLanguages: [String]) -> LibrarySong? {
            var song = existing
            let localized = title(preferredLanguages: preferredLanguages)
            if Set(title.values).contains(existing.title) { song.title = localized }
            song.license = license
            return song == existing ? nil : song
        }
    }

    public let version: Int
    public let songs: [Entry]

    public static func load(from data: Data) throws -> BuiltinCatalog {
        try JSONDecoder().decode(BuiltinCatalog.self, from: data)
    }
}
