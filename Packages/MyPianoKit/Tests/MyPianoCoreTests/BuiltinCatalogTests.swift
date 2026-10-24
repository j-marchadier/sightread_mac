import Foundation
import Testing
@testable import MyPianoCore

@Suite("Built-in catalog")
struct BuiltinCatalogTests {
    private func catalog() throws -> BuiltinCatalog {
        try BuiltinCatalog.load(from: Data(contentsOf: Fixtures.builtinSongs.appendingPathComponent("catalog.json")))
    }

    @Test func listsEveryShippedFileOnceWithUniqueIDs() throws {
        let catalog = try catalog()
        let files = try FileManager.default.contentsOfDirectory(atPath: Fixtures.builtinSongs.path).filter { $0.hasSuffix(".mid") }
        #expect(Set(catalog.songs.map(\.file)) == Set(files))
        #expect(Set(catalog.songs.map(\.id)).count == catalog.songs.count)
        #expect(!catalog.songs.contains { $0.file.contains("swan") })
    }

    @Test func everyEntryParsesAndHasLicenseAndTitles() throws {
        for entry in try catalog().songs {
            let song = try SongLoader.load(contentsOf: Fixtures.builtinSongs.appendingPathComponent(entry.file))
            #expect(!song.notes.isEmpty, "\(entry.file)")
            #expect(entry.title["fr"] != nil && entry.title["en"] != nil)
            #expect(!entry.license.isEmpty && entry.licenseURL.hasPrefix("https://"))
        }
    }

    @Test func picksTheTitleLanguage() throws {
        let ode = try #require(try catalog().songs.first { $0.id == "builtin.ode-to-joy" })
        #expect(ode.title(preferredLanguages: ["en-GB", "fr"]) == "Ode to Joy")
        #expect(ode.title(preferredLanguages: ["de"]) == "Ode à la joie")
        #expect(ode.composer == "Ludwig van Beethoven")
    }
}
