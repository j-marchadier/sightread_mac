import Foundation

public enum SongSource: String, Sendable, Codable {
    case builtin
    case imported
    case watched
}

/// A song of the library and what Pianissimac remembers about it.
public struct LibrarySong: Sendable, Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var composer: String?
    public var source: SongSource
    /// File name inside the built-in folder (built-in songs) or the library folder (imported songs).
    public var fileName: String
    public var duration: TimeInterval
    /// 1 (easiest) to 5 (hardest).
    public var difficulty: Int
    public var dateAdded: Date
    public var lastPlayed: Date?
    public var isFavorite: Bool
    /// Practice settings last used with this song.
    public var settings: PracticeSettings?
    /// SHA-256 of the file, to avoid importing the same file twice.
    public var contentHash: String?
    public var license: String?
    /// For songs found in the watched folder: where the original file is.
    public var sourcePath: String?

    public init(
        id: String, title: String, composer: String? = nil, source: SongSource, fileName: String,
        duration: TimeInterval, difficulty: Int, dateAdded: Date = Date(), lastPlayed: Date? = nil,
        isFavorite: Bool = false, settings: PracticeSettings? = nil, contentHash: String? = nil, license: String? = nil
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.source = source
        self.fileName = fileName
        self.duration = duration
        self.difficulty = difficulty
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.isFavorite = isFavorite
        self.settings = settings
        self.contentHash = contentHash
        self.license = license
    }
}

/// One finished practice session of a song.
public struct PracticeRecord: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID
    public var songID: String
    public var summary: SessionSummary

    public init(id: UUID = UUID(), songID: String, summary: SessionSummary) {
        self.id = id
        self.songID = songID
        self.summary = summary
    }
}

public struct SongProgress: Sendable, Equatable {
    public var sessions: Int
    public var practiceSeconds: TimeInterval
    public var bestAccuracy: Double?
    public var lastAccuracy: Double?
    public var bestScore: Int?
}

public enum LibraryCategory: Sendable, Hashable {
    case all
    case recent
    case favorites
    case imported
}

public enum LibrarySort: String, Sendable, CaseIterable, Codable {
    case title, composer, duration, difficulty, recent
}

/// Everything the library stores, saved as one JSON document.
public struct LibraryDatabase: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public var version = LibraryDatabase.currentVersion
    public private(set) var songs: [LibrarySong] = []
    public private(set) var records: [PracticeRecord] = []

    public init(songs: [LibrarySong] = [], records: [PracticeRecord] = []) {
        self.songs = songs
        self.records = records
    }

    public func song(_ id: String) -> LibrarySong? {
        songs.first { $0.id == id }
    }

    /// Adds a song, or updates the descriptive fields of an existing one (favourites, settings
    /// and history are kept).
    public mutating func upsert(_ song: LibrarySong) {
        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            var merged = song
            merged.isFavorite = songs[index].isFavorite
            merged.lastPlayed = songs[index].lastPlayed
            merged.settings = songs[index].settings ?? song.settings
            merged.dateAdded = songs[index].dateAdded
            songs[index] = merged
        } else {
            songs.append(song)
        }
    }

    public mutating func update(_ id: String, _ change: (inout LibrarySong) -> Void) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        change(&songs[index])
    }

    public mutating func remove(_ id: String) {
        songs.removeAll { $0.id == id }
        records.removeAll { $0.songID == id }
    }

    public mutating func record(_ summary: SessionSummary, for songID: String) {
        records.append(PracticeRecord(songID: songID, summary: summary))
        update(songID) { $0.lastPlayed = max($0.lastPlayed ?? .distantPast, summary.startedAt) }
    }

    public func records(for songID: String) -> [PracticeRecord] {
        records.filter { $0.songID == songID }.sorted { $0.summary.startedAt > $1.summary.startedAt }
    }

    public func progress(for songID: String) -> SongProgress {
        let judged = records(for: songID).filter { $0.summary.mode != .listen }
        return SongProgress(
            sessions: records(for: songID).count,
            practiceSeconds: records(for: songID).reduce(0) { $0 + $1.summary.practiceSeconds },
            bestAccuracy: judged.map(\.summary.stats.accuracy).max(),
            lastAccuracy: judged.first?.summary.stats.accuracy,
            bestScore: judged.map(\.summary.stats.score).max()
        )
    }

    /// Songs of a category matching a search (title or composer, ignoring case and accents), sorted.
    public func songs(in category: LibraryCategory, matching search: String = "", sortedBy sort: LibrarySort = .title, ascending: Bool = true) -> [LibrarySong] {
        var result: [LibrarySong]
        switch category {
        case .all: result = songs
        case .recent: result = songs.filter { $0.lastPlayed != nil }
        case .favorites: result = songs.filter(\.isFavorite)
        case .imported: result = songs.filter { $0.source != .builtin }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || ($0.composer?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
            }
        }
        func titleOrder(_ a: LibrarySong, _ b: LibrarySong) -> Bool {
            a.title.compare(b.title, options: [.caseInsensitive, .diacriticInsensitive, .numeric]) == .orderedAscending
        }
        if category == .recent && sort == .title {
            return result.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }
        result.sort { a, b in
            switch sort {
            case .title: return titleOrder(a, b)
            case .composer:
                let order = (a.composer ?? "").compare(b.composer ?? "", options: [.caseInsensitive, .diacriticInsensitive])
                return order == .orderedSame ? titleOrder(a, b) : order == .orderedAscending
            case .duration: return a.duration == b.duration ? titleOrder(a, b) : a.duration < b.duration
            case .difficulty: return a.difficulty == b.difficulty ? titleOrder(a, b) : a.difficulty < b.difficulty
            case .recent: return (a.lastPlayed ?? .distantPast) < (b.lastPlayed ?? .distantPast)
            }
        }
        return ascending ? result : result.reversed()
    }
}

/// Reads and writes the library document atomically.
public struct LibraryFileStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// An empty library when the file does not exist yet.
    public func load() throws -> LibraryDatabase {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryDatabase() }
        let decoder = JSONDecoder()
        return try decoder.decode(LibraryDatabase.self, from: Data(contentsOf: url))
    }

    public func save(_ database: LibraryDatabase) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(database).write(to: url, options: .atomic)
    }
}
