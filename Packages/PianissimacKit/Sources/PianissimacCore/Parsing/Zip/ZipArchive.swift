import Foundation

public enum ZipError: Error, Equatable, Sendable {
    case notAZipArchive
    case truncated
    case unsupportedCompression(method: Int)
    case encryptedEntry
    case checksumMismatch(entry: String)
    case entryNotFound(String)
    case corrupted(InflateError)
}

/// Read-only access to the entries of a ZIP archive (stored and deflated entries, no ZIP64).
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Equatable {
        public let path: String
        let method: Int
        let flags: Int
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    public let entries: [Entry]

    public init(data: Data) throws(ZipError) {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    public func entry(_ path: String) -> Entry? {
        entries.first { $0.path == path }
    }

    public func contents(of path: String) throws(ZipError) -> Data {
        guard let entry = entry(path) else { throw .entryNotFound(path) }
        return try contents(of: entry)
    }

    public func contents(of entry: Entry) throws(ZipError) -> Data {
        guard entry.flags & 1 == 0 else { throw .encryptedEntry }
        let header = entry.localHeaderOffset
        guard le32(bytes, header) == 0x0403_4B50 else { throw .truncated }
        let start = header + 30 + Int(le16(bytes, header + 26)) + Int(le16(bytes, header + 28))
        guard start + entry.compressedSize <= bytes.count else { throw .truncated }
        let compressed = Array(bytes[start..<start + entry.compressedSize])

        let output: [UInt8]
        switch entry.method {
        case 0:
            output = compressed
        case 8:
            do {
                output = try Inflate.decompress(compressed, limit: max(entry.uncompressedSize, 1) * 2 + 1024)
            } catch {
                throw .corrupted(error)
            }
        default:
            throw .unsupportedCompression(method: entry.method)
        }
        guard CRC32.checksum(output) == entry.crc32 else { throw .checksumMismatch(entry: entry.path) }
        return Data(output)
    }

    private static func readCentralDirectory(_ bytes: [UInt8]) throws(ZipError) -> [Entry] {
        guard bytes.count >= 22 else { throw .notAZipArchive }
        // The end-of-central-directory record sits in the last 22 + 65535 bytes (comment included).
        let searchStart = max(0, bytes.count - 22 - 0xFFFF)
        guard let end = stride(from: bytes.count - 22, through: searchStart, by: -1).first(where: { le32(bytes, $0) == 0x0605_4B50 }) else {
            throw .notAZipArchive
        }
        let count = Int(le16(bytes, end + 10))
        var offset = Int(le32(bytes, end + 16))

        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, le32(bytes, offset) == 0x0201_4B50 else { throw .truncated }
            let nameLength = Int(le16(bytes, offset + 28))
            let extraLength = Int(le16(bytes, offset + 30))
            let commentLength = Int(le16(bytes, offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { throw .truncated }
            let name = String(decoding: bytes[offset + 46..<offset + 46 + nameLength], as: UTF8.self)
            entries.append(Entry(
                path: name,
                method: Int(le16(bytes, offset + 10)),
                flags: Int(le16(bytes, offset + 8)),
                crc32: le32(bytes, offset + 16),
                compressedSize: Int(le32(bytes, offset + 20)),
                uncompressedSize: Int(le32(bytes, offset + 24)),
                localHeaderOffset: Int(le32(bytes, offset + 42))
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}

private func le16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    guard offset + 2 <= bytes.count else { return 0 }
    return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
}

private func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
    return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
