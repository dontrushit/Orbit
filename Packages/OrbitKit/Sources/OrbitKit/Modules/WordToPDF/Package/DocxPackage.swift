import Foundation

/// Why a file can't be converted.
public enum DocxError: Error, Equatable {
    /// Not a ZIP archive: an old binary .doc, a password-protected document, or not a Word file at all.
    case notADocx
    case unsupportedArchive(String)
    case missingPart(String)
    case malformedPart(String)
}

struct Relationship {
    let id: String
    /// The last component of the relationship type URI, such as "image" or "styles".
    let type: String
    /// A package path for internal targets, the URI as written for external ones.
    let target: String
    let isExternal: Bool
}

struct Relationships {
    static let empty = Relationships(list: [])

    private let list: [Relationship]
    private let byID: [String: Relationship]

    init(list: [Relationship]) {
        self.list = list
        byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(id: String) -> Relationship? { byID[id] }

    func first(ofType type: String) -> Relationship? {
        list.first { $0.type == type && !$0.isExternal }
    }
}

/// A .docx file: a ZIP archive of XML parts connected by relationships.
struct DocxPackage {
    private let archive: ZipArchive

    init(contentsOf url: URL) throws {
        archive = try Self.open { try ZipArchive(contentsOf: url) }
    }

    init(data: Data) throws {
        archive = try Self.open { try ZipArchive(data: data) }
    }

    private static func open(_ makeArchive: () throws -> ZipArchive) throws -> ZipArchive {
        do {
            return try makeArchive()
        } catch ZipArchive.Failure.notAnArchive {
            throw DocxError.notADocx
        } catch let failure as ZipArchive.Failure {
            throw DocxError.unsupportedArchive(String(describing: failure))
        }
    }

    func data(at path: String) throws -> Data? {
        do {
            return try archive.contents(of: path)
        } catch {
            throw DocxError.unsupportedArchive("\(path): \(error)")
        }
    }

    /// The parsed XML part, or `nil` if the package doesn't have it.
    func xml(at path: String) throws -> MarkupElement? {
        guard let data = try data(at: path) else { return nil }
        do {
            return try MarkupParser.parse(data)
        } catch {
            throw DocxError.malformedPart("\(path): \(error)")
        }
    }

    /// The main document part, found through the package relationships.
    func mainDocumentPath() throws -> String {
        let path = try relationships(of: "").first(ofType: "officeDocument")?.target ?? "word/document.xml"
        guard archive.contains(path) else { throw DocxError.notADocx }
        return path
    }

    /// Relationships of the part at `partPath`; pass "" for the package itself.
    func relationships(of partPath: String) throws -> Relationships {
        let directory = Self.directory(of: partPath)
        let fileName = partPath.split(separator: "/").last.map(String.init) ?? ""
        let relsPath = Self.join(directory, "_rels/\(fileName).rels")
        guard let root = try xml(at: relsPath) else { return .empty }

        let list = root.children("Relationship", in: .packageRelationships).compactMap { element -> Relationship? in
            guard let id = element.attribute("Id", in: .none),
                  let type = element.attribute("Type", in: .none),
                  let target = element.attribute("Target", in: .none)
            else { return nil }
            let isExternal = element.attribute("TargetMode", in: .none) == "External"
            return Relationship(
                id: id,
                type: type.split(separator: "/").last.map(String.init) ?? type,
                target: isExternal ? target : Self.resolve(target, from: directory),
                isExternal: isExternal
            )
        }
        return Relationships(list: list)
    }

    // MARK: Paths

    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func join(_ directory: String, _ path: String) -> String {
        directory.isEmpty ? path : "\(directory)/\(path)"
    }

    /// Resolves a relationship target, written relative to the source part's folder, to a package path.
    static func resolve(_ target: String, from directory: String) -> String {
        let decoded = target.removingPercentEncoding ?? target
        let combined = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : join(directory, decoded)
        var components: [Substring] = []
        for component in combined.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": _ = components.popLast()
            default: components.append(component)
            }
        }
        return components.joined(separator: "/")
    }
}
