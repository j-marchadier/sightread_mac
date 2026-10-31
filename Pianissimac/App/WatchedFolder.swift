import CryptoKit
import Foundation
import PianissimacCore
import Observation

/// An optional folder whose MIDI and MusicXML files join the library by themselves.
/// Access survives restarts through a security-scoped bookmark; the folder is rescanned every few seconds.
@MainActor
@Observable
final class WatchedFolder {
    enum Status: Equatable {
        case off
        case watching
        /// The bookmark no longer opens the folder: it must be chosen again.
        case accessLost
    }

    private(set) var url: URL?
    private(set) var status: Status = .off

    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: CachedFile] = [:]
    @ObservationIgnored private var accessing: URL?

    private static let bookmarkKey = "library.watchedFolderBookmark"
    private static let scanInterval: Duration = .seconds(3)

    init(library: LibraryModel) {
        self.library = library
    }

    func start() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            status = .accessLost
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        begin(url)
    }

    /// Starts watching a folder the player chose.
    func choose(_ url: URL) {
        stop(forget: false)
        let scoped = url.startAccessingSecurityScopedResource()
        guard let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            status = .accessLost
            return
        }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        begin(url)
    }

    /// Stops watching. Songs already imported from the folder stay in the library.
    func stop(forget: Bool = true) {
        scanTask?.cancel()
        scanTask = nil
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        url = nil
        cache = [:]
        status = .off
        if forget {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            // The songs stay, as ordinary imported songs.
            library.detachWatchedSongs()
        }
    }

    private func begin(_ url: URL) {
        accessing = url
        self.url = url
        status = .watching
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: Self.scanInterval)
            }
        }
    }

    private func scan() async {
        guard let url else { return }
        let previous = cache
        let (found, cache) = await Task.detached(priority: .utility) { Self.files(in: url, cache: previous) }.value
        guard !Task.isCancelled, self.url == url else { return }
        guard let found else {
            status = .accessLost
            return
        }
        self.cache = cache
        library.sync(with: found)
    }

    // MARK: Scanning (off the main actor)

    struct CachedFile: Sendable {
        var size: Int
        var modified: Date
        var hash: String
    }

    /// Supported files in the folder and its subfolders, with their content hash (reused while
    /// size and date are unchanged). `nil` when the folder cannot be read.
    nonisolated private static func files(in folder: URL, cache: [String: CachedFile]) -> ([WatchedFolderSync.FoundFile]?, [String: CachedFile]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return (nil, cache)
        }
        var found: [WatchedFolderSync.FoundFile] = []
        var fresh: [String: CachedFile] = [:]
        for case let file as URL in enumerator {
            guard SongFileFormat.fileExtensions[file.pathExtension.lowercased()] != nil,
                  let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            let modified = values.contentModificationDate ?? .distantPast
            let path = file.path
            var entry = cache[path]
            if entry == nil || entry?.size != size || entry?.modified != modified {
                guard let data = try? Data(contentsOf: file) else { continue }
                entry = CachedFile(size: size, modified: modified, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
            if let entry {
                fresh[path] = entry
                found.append(.init(path: path, hash: entry.hash))
            }
        }
        return (found, fresh)
    }
}
