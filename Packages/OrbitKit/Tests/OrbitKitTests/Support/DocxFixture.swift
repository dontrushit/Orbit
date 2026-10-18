import Compression
import Foundation
import ImageIO
@testable import OrbitKit

/// Writes ZIP archives for tests: stored or deflated entries, like Office writes them.
struct ZipWriter {
    private var entries: [(name: String, data: Data, deflate: Bool)] = []

    mutating func add(_ name: String, _ data: Data, deflate: Bool = true) {
        entries.append((name, data, deflate))
    }

    mutating func add(_ name: String, _ text: String, deflate: Bool = true) {
        add(name, Data(text.utf8), deflate: deflate)
    }

    func data() -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let stored = entry.deflate ? Self.deflate(entry.data) : entry.data
            let name = Data(entry.name.utf8)
            let offset = UInt32(archive.count)
            let method: UInt16 = entry.deflate ? 8 : 0

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20) // version
            archive.append(le16: 0) // flags
            archive.append(le16: method)
            archive.append(le32: 0) // time, date
            archive.append(le32: 0) // CRC: the reader doesn't check it
            archive.append(le32: UInt32(stored.count))
            archive.append(le32: UInt32(entry.data.count))
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(stored)

            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 20)
            directory.append(le16: 20)
            directory.append(le16: 0)
            directory.append(le16: method)
            directory.append(le32: 0)
            directory.append(le32: 0)
            directory.append(le32: UInt32(stored.count))
            directory.append(le32: UInt32(entry.data.count))
            directory.append(le16: UInt16(name.count))
            directory.append(le16: 0) // extra
            directory.append(le16: 0) // comment
            directory.append(le16: 0) // disk
            directory.append(le16: 0) // internal attributes
            directory.append(le32: 0) // external attributes
            directory.append(le32: offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: directoryOffset)
        archive.append(le16: 0)
        return archive
    }

    private static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        var output = Data(count: data.count + 1024)
        let size = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(size)
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

/// A .docx built from WordprocessingML snippets.
struct DocxFixture {
    static let namespaces = """
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" \
        xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
        """

    /// Contents of `w:body`.
    var body: String
    /// Contents of `w:styles`.
    var styles: String?
    /// Contents of `w:numbering`.
    var numbering: String?
    /// Header parts by relationship ID ("rIdH1"), with the contents of `w:hdr`.
    var headers: [String: String] = [:]
    /// Media parts by relationship ID ("rIdImg1"), stored as word/media/<id>.png.
    var media: [String: Data] = [:]
    /// External hyperlinks by relationship ID.
    var links: [String: String] = [:]

    init(body: String, styles: String? = nil, numbering: String? = nil) {
        self.body = body
        self.styles = styles
        self.numbering = numbering
    }

    func data() -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", #"<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>"#)
        zip.add("_rels/.rels", Self.relationships([
            #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>"#,
        ]))

        var documentRelationships: [String] = []
        func relationship(_ id: String, _ type: String, _ target: String, external: Bool = false) {
            documentRelationships.append(
                #"<Relationship Id="\#(id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/\#(type)" Target="\#(target)"\#(external ? #" TargetMode="External""# : "")/>"#
            )
        }
        if let styles {
            zip.add("word/styles.xml", "<w:styles \(Self.namespaces)>\(styles)</w:styles>")
            relationship("rIdStyles", "styles", "styles.xml")
        }
        if let numbering {
            zip.add("word/numbering.xml", "<w:numbering \(Self.namespaces)>\(numbering)</w:numbering>")
            relationship("rIdNumbering", "numbering", "numbering.xml")
        }
        for (id, header) in headers {
            zip.add("word/\(id).xml", "<w:hdr \(Self.namespaces)>\(header)</w:hdr>")
            relationship(id, "header", "\(id).xml")
        }
        for (id, data) in media {
            zip.add("word/media/\(id).png", data, deflate: false)
            relationship(id, "image", "media/\(id).png")
        }
        for (id, url) in links {
            relationship(id, "hyperlink", url, external: true)
        }
        zip.add("word/_rels/document.xml.rels", Self.relationships(documentRelationships))
        zip.add("word/document.xml", "<w:document \(Self.namespaces)><w:body>\(body)</w:body></w:document>")
        return zip.data()
    }

    func write(to folder: URL, name: String = "Document.docx") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data().write(to: url)
        return url
    }

    func build() throws -> BuiltDocument {
        try DocumentBuilder(package: DocxPackage(data: data())).build()
    }

    private static func relationships(_ items: [String]) -> String {
        #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"# + items.joined() + "</Relationships>"
    }

    // MARK: Snippets

    static func paragraph(_ text: String, properties: String = "") -> String {
        #"<w:p><w:pPr>\#(properties)</w:pPr><w:r><w:t xml:space="preserve">\#(text)</w:t></w:r></w:p>"#
    }

    /// Page setup for a section: A4 with 1" margins unless given.
    static func section(width: Int = 11906, height: Int = 16838, margin: Int = 1440, extra: String = "") -> String {
        #"<w:sectPr>\#(extra)<w:pgSz w:w="\#(width)" w:h="\#(height)"/><w:pgMar w:top="\#(margin)" w:right="\#(margin)" w:bottom="\#(margin)" w:left="\#(margin)" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>"#
    }

    /// A 2×1 PNG.
    static let png: Data = {
        let bitmap = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()
}
