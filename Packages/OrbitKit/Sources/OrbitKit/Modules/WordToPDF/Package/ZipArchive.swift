import Compression
import Foundation

/// Read-only access to the entries of a ZIP archive, the container of .docx files.
///
/// Supports what Office and other editors write: stored and deflated entries, without encryption or ZIP64.
struct ZipArchive {
    enum Failure: Error, Equatable {
        case notAnArchive
        case unsupported(String)
        case corrupted(String)
    }

    /// Larger entries are refused instead of inflated, so a malicious archive can't exhaust memory.
    static let maxEntrySize = 512 * 1024 * 1024

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private enum Signature {
        static let localHeader: UInt32 = 0x0403_4B50
        static let centralDirectoryEntry: UInt32 = 0x0201_4B50
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    }

    private let reader: ByteReader
    /// Keyed by normalized path: part names in OOXML packages are case-insensitive.
    private let entries: [String: Entry]

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        reader = ByteReader(data: data)
        entries = try Self.readCentralDirectory(reader)
    }

    func contains(_ path: String) -> Bool {
        entries[Self.key(path)] != nil
    }

    /// Contents of the entry at `path`, or `nil` if the archive has no such entry.
    func contents(of path: String) throws -> Data? {
        guard let entry = entries[Self.key(path)] else { return nil }

        let header = entry.localHeaderOffset
        guard try reader.uint32(at: header) == Signature.localHeader else {
            throw Failure.corrupted("bad local header of \(path)")
        }
        // The local header repeats the name but may have a different extra field than the central directory.
        let start = header + 30 + Int(try reader.uint16(at: header + 26)) + Int(try reader.uint16(at: header + 28))
        let stored = try reader.bytes(at: start, count: entry.compressedSize)

        switch entry.method {
        case 0:
            guard stored.count == entry.uncompressedSize else { throw Failure.corrupted("size mismatch in \(path)") }
            return stored
        case 8:
            return try Self.inflate(stored, size: entry.uncompressedSize, path: path)
        default:
            throw Failure.unsupported("compression method \(entry.method)")
        }
    }

    // MARK: Reading

    static func key(_ path: String) -> String {
        (path.hasPrefix("/") ? String(path.dropFirst()) : path).lowercased()
    }

    private static func readCentralDirectory(_ reader: ByteReader) throws -> [String: Entry] {
        guard let end = findEndOfCentralDirectory(reader) else { throw Failure.notAnArchive }

        let count = try reader.uint16(at: end + 10)
        let offset = try reader.uint32(at: end + 16)
        guard count != 0xFFFF, offset != 0xFFFF_FFFF else { throw Failure.unsupported("ZIP64") }

        var entries: [String: Entry] = [:]
        var position = Int(offset)
        for _ in 0..<count {
            guard try reader.uint32(at: position) == Signature.centralDirectoryEntry else {
                throw Failure.corrupted("bad central directory")
            }
            guard try reader.uint16(at: position + 8) & 1 == 0 else { throw Failure.unsupported("encryption") }

            let compressedSize = try reader.uint32(at: position + 20)
            let uncompressedSize = try reader.uint32(at: position + 24)
            let localHeaderOffset = try reader.uint32(at: position + 42)
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF, localHeaderOffset != 0xFFFF_FFFF else {
                throw Failure.unsupported("ZIP64")
            }
            guard uncompressedSize <= maxEntrySize else { throw Failure.unsupported("entry larger than \(maxEntrySize) bytes") }

            let nameLength = Int(try reader.uint16(at: position + 28))
            let extraLength = Int(try reader.uint16(at: position + 30))
            let commentLength = Int(try reader.uint16(at: position + 32))
            let name = String(decoding: try reader.bytes(at: position + 46, count: nameLength), as: UTF8.self)

            entries[key(name)] = Entry(
                method: try reader.uint16(at: position + 10),
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localHeaderOffset)
            )
            position += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The record is at the very end, followed only by an optional comment of up to 64 KB.
    private static func findEndOfCentralDirectory(_ reader: ByteReader) -> Int? {
        let recordSize = 22
        guard reader.count >= recordSize else { return nil }
        let last = reader.count - recordSize
        for position in stride(from: last, through: max(0, last - 0xFFFF), by: -1)
        where (try? reader.uint32(at: position)) == Signature.endOfCentralDirectory {
            return position
        }
        return nil
    }

    private static func inflate(_ data: Data, size: Int, path: String) throws -> Data {
        guard size > 0 else { return Data() }
        guard !data.isEmpty else { throw Failure.corrupted("empty stream in \(path)") }

        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                // COMPRESSION_ZLIB is raw DEFLATE, exactly what ZIP stores.
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.corrupted("can't inflate \(path)") }
        return output
    }
}

/// Bounds-checked little-endian reads.
private struct ByteReader {
    let data: Data

    init(data: Data) {
        // Slices keep the indices of their parent; zero-based offsets are simpler and safer.
        self.data = data.startIndex == 0 ? data : Data(data)
    }

    var count: Int { data.count }

    func uint16(at offset: Int) throws -> UInt16 { try integer(at: offset) }
    func uint32(at offset: Int) throws -> UInt32 { try integer(at: offset) }

    func bytes(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count - count else {
            throw ZipArchive.Failure.corrupted("unexpected end of archive")
        }
        return data.subdata(in: offset..<offset + count)
    }

    private func integer<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset <= data.count - MemoryLayout<T>.size else {
            throw ZipArchive.Failure.corrupted("unexpected end of archive")
        }
        return data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
    }
}
