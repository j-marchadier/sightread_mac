import Foundation

/// Decides how the library follows the watched folder: files to add, songs whose file moved or
/// was renamed (recognised by content), and songs whose file is gone.
public enum WatchedFolderSync {
    public struct FoundFile: Sendable, Equatable {
        public var path: String
        public var hash: String

        public init(path: String, hash: String) {
            self.path = path
            self.hash = hash
        }
    }

    public enum Action: Sendable, Equatable {
        case add(path: String)
        case move(id: String, to: String)
        case remove(id: String)
    }

    /// - Parameter ignored: contents the player removed from the library on purpose.
    public static func plan(found: [FoundFile], library: [LibrarySong], ignoring ignored: Set<String> = []) -> [Action] {
        var actions: [Action] = []
        let byPath = Dictionary(found.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let watched = library.filter { $0.source == .watched }
        var claimed = Set(watched.compactMap { song in
            song.sourcePath.flatMap { byPath[$0]?.hash == song.contentHash ? $0 : nil }
        })
        for song in watched {
            if let path = song.sourcePath, claimed.contains(path), byPath[path]?.hash == song.contentHash { continue }
            if let moved = found.first(where: { $0.hash == song.contentHash && !claimed.contains($0.path) }) {
                claimed.insert(moved.path)
                actions.append(.move(id: song.id, to: moved.path))
            } else {
                actions.append(.remove(id: song.id))
            }
        }
        let removed = Set(actions.compactMap { if case let .remove(id) = $0 { id } else { nil } })
        let knownHashes = Set(library.filter { !removed.contains($0.id) }.compactMap(\.contentHash))
        var added = Set<String>()
        for file in found.sorted(by: { $0.path < $1.path }) where !claimed.contains(file.path) {
            guard !ignored.contains(file.hash), !knownHashes.contains(file.hash), added.insert(file.hash).inserted else { continue }
            actions.append(.add(path: file.path))
        }
        return actions
    }
}
