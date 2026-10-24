import Foundation

public enum InflateError: Error, Equatable, Sendable {
    case truncated
    case invalidBlockType
    case invalidStoredBlockLength
    case invalidCodeLengths
    case invalidSymbol
    case invalidDistance
    case outputTooLarge
}

/// Raw DEFLATE decompressor (RFC 1951), as used inside ZIP archives.
public enum Inflate {
    /// Decompresses `input`. `limit` guards against decompression bombs.
    public static func decompress(_ input: [UInt8], limit: Int = 256 * 1024 * 1024) throws(InflateError) -> [UInt8] {
        var bits = BitReader(input)
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 4)

        var isLastBlock = false
        while !isLastBlock {
            isLastBlock = try bits.read(1) == 1
            switch try bits.read(2) {
            case 0: try copyStoredBlock(&bits, into: &output)
            case 1: try inflateBlock(&bits, into: &output, literals: fixedTables.literals, distances: fixedTables.distances, limit: limit)
            case 2:
                let tables = try readDynamicTables(&bits)
                try inflateBlock(&bits, into: &output, literals: tables.literals, distances: tables.distances, limit: limit)
            default: throw .invalidBlockType
            }
            if output.count > limit { throw .outputTooLarge }
        }
        return output
    }

    private static func copyStoredBlock(_ bits: inout BitReader, into output: inout [UInt8]) throws(InflateError) {
        bits.alignToByte()
        let length = try bits.read(16)
        let complement = try bits.read(16)
        guard length == ~complement & 0xFFFF else { throw .invalidStoredBlockLength }
        output += try bits.readAlignedBytes(length)
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func inflateBlock(
        _ bits: inout BitReader, into output: inout [UInt8], literals: Huffman, distances: Huffman, limit: Int
    ) throws(InflateError) {
        while true {
            let symbol = try literals.decode(&bits)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < lengthBase.count else { throw .invalidSymbol }
                let length = lengthBase[lengthIndex] + (try bits.read(lengthExtra[lengthIndex]))
                let distanceSymbol = try distances.decode(&bits)
                guard distanceSymbol < distanceBase.count else { throw .invalidSymbol }
                let distance = distanceBase[distanceSymbol] + (try bits.read(distanceExtra[distanceSymbol]))
                guard distance <= output.count else { throw .invalidDistance }
                let start = output.count - distance
                for i in 0..<length {
                    output.append(output[start + i]) // may overlap the bytes being written
                }
                if output.count > limit { throw .outputTooLarge }
            }
        }
    }

    private static let fixedTables: (literals: Huffman, distances: Huffman) = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        // Fixed tables are valid by construction.
        let literals = try! Huffman(lengths: lengths)
        let distances = try! Huffman(lengths: [Int](repeating: 5, count: 30))
        return (literals, distances)
    }()

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static func readDynamicTables(_ bits: inout BitReader) throws(InflateError) -> (literals: Huffman, distances: Huffman) {
        let literalCount = try bits.read(5) + 257
        let distanceCount = try bits.read(5) + 1
        let codeLengthCount = try bits.read(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw .invalidCodeLengths }

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<codeLengthCount {
            codeLengthLengths[codeLengthOrder[i]] = try bits.read(3)
        }
        let codeLengthCode = try Huffman(lengths: codeLengthLengths)

        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            let symbol = try codeLengthCode.decode(&bits)
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else { throw .invalidCodeLengths }
                lengths += [Int](repeating: previous, count: 3 + (try bits.read(2)))
            case 17:
                lengths += [Int](repeating: 0, count: 3 + (try bits.read(3)))
            case 18:
                lengths += [Int](repeating: 0, count: 11 + (try bits.read(7)))
            default:
                throw .invalidCodeLengths
            }
        }
        guard lengths.count == literalCount + distanceCount, lengths[256] > 0 else { throw .invalidCodeLengths }
        return (
            try Huffman(lengths: Array(lengths[0..<literalCount])),
            try Huffman(lengths: Array(lengths[literalCount...]))
        )
    }
}

/// Canonical Huffman decoder built from code lengths.
private struct Huffman {
    private var counts = [Int](repeating: 0, count: 16)
    private var symbols: [Int] = []

    init(lengths: [Int]) throws(InflateError) {
        for length in lengths {
            guard (0...15).contains(length) else { throw .invalidCodeLengths }
            counts[length] += 1
        }
        counts[0] = 0
        // Reject over-subscribed codes (incomplete codes are allowed, as in zlib).
        var left = 1
        for length in 1...15 {
            left = left * 2 - counts[length]
            if left < 0 { throw .invalidCodeLengths }
        }
        var offsets = [Int](repeating: 0, count: 16)
        for length in 1..<15 {
            offsets[length + 1] = offsets[length] + counts[length]
        }
        symbols = [Int](repeating: 0, count: lengths.count)
        for (symbol, length) in lengths.enumerated() where length > 0 {
            symbols[offsets[length]] = symbol
            offsets[length] += 1
        }
    }

    func decode(_ bits: inout BitReader) throws(InflateError) -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...15 {
            code |= try bits.read(1)
            let count = counts[length]
            if code - first < count {
                return symbols[index + code - first]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw .invalidSymbol
    }
}

/// Reads bits least-significant first, as DEFLATE requires.
private struct BitReader {
    private let bytes: [UInt8]
    private var position = 0
    private var buffer = 0
    private var bufferCount = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func read(_ count: Int) throws(InflateError) -> Int {
        while bufferCount < count {
            guard position < bytes.count else { throw .truncated }
            buffer |= Int(bytes[position]) << bufferCount
            position += 1
            bufferCount += 8
        }
        let value = buffer & ((1 << count) - 1)
        buffer >>= count
        bufferCount -= count
        return value
    }

    mutating func alignToByte() {
        let drop = bufferCount % 8
        buffer >>= drop
        bufferCount -= drop
    }

    /// Reads whole bytes after ``alignToByte()``, starting with any bytes still buffered.
    mutating func readAlignedBytes(_ count: Int) throws(InflateError) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(count)
        while bufferCount >= 8 && result.count < count {
            result.append(UInt8(buffer & 0xFF))
            buffer >>= 8
            bufferCount -= 8
        }
        let remaining = count - result.count
        guard position + remaining <= bytes.count else { throw .truncated }
        result += bytes[position..<position + remaining]
        position += remaining
        return result
    }
}
