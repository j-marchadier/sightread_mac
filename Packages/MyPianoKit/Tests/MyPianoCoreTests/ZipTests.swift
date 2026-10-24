import Foundation
import Testing
@testable import MyPianoCore

@Suite("ZIP and DEFLATE")
struct ZipTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        let archive = try ZipArchive(data: Fixtures.data("Zip/mixed.zip"))
        let expected = try Fixtures.data("Zip/expected.txt")
        #expect(archive.entries.map(\.path).sorted() == ["deflate-1.txt", "deflate-9.txt", "empty.txt", "stored.txt"])
        #expect(try archive.contents(of: "stored.txt") == Data("stored entry\n".utf8))
        #expect(try archive.contents(of: "deflate-1.txt") == expected) // dynamic Huffman blocks
        #expect(try archive.contents(of: "deflate-9.txt") == expected)
        #expect(try archive.contents(of: "empty.txt").isEmpty)
        #expect(throws: ZipError.entryNotFound("missing")) { try archive.contents(of: "missing") }
    }

    @Test func inflatesFixedHuffmanAndStoredBlocks() throws {
        let fixed = try Inflate.decompress([UInt8](Fixtures.data("Zip/fixed.deflate")))
        #expect(String(decoding: fixed, as: UTF8.self) == "abcabcabcabc hello hello hello")
        let stored = try Inflate.decompress([UInt8](Fixtures.data("Zip/stored.deflate")))
        #expect(Data(stored) == (try Fixtures.data("Zip/stored-expected.bin")))
    }

    @Test func rejectsCorruptedData() throws {
        #expect(throws: ZipError.notAZipArchive) { try ZipArchive(data: Data("not a zip".utf8)) }
        #expect(throws: InflateError.invalidBlockType) { try Inflate.decompress([0b0000_0111]) }
        #expect(throws: InflateError.truncated) { try Inflate.decompress([]) }

        var zip = [UInt8](try Fixtures.data("Zip/mixed.zip"))
        let archive = try ZipArchive(data: Data(zip))
        // Flip a byte inside the stored entry's data: the checksum must catch it.
        let marker = Array("stored entry".utf8)
        let index = (0...(zip.count - marker.count)).first { Array(zip[$0..<$0 + marker.count]) == marker }!
        zip[index] ^= 0xFF
        let damaged = try ZipArchive(data: Data(zip))
        #expect(throws: ZipError.checksumMismatch(entry: "stored.txt")) { try damaged.contents(of: "stored.txt") }
        _ = archive
    }

    @Test func checksum() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
    }
}
