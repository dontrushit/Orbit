import Foundation
import PDFKit

/// Merges and splits PDF files with PDFKit. Synchronous: call it from a dispatch queue, like the other Finder actions.
public enum PDFTools {
    public enum Failure: Error {
        /// Merging needs at least two documents, splitting at least one.
        case tooFewDocuments
        case unreadable
        /// The document needs a password to open.
        case locked
        /// A one-page document has nothing to split.
        case singlePage
        /// Every page was left out.
        case noPages
        case unwritable
        /// The file is gone since it was inspected.
        case missing
        /// The file changed since it was inspected: the chosen pages may no longer be the same.
        case modified
    }

    /// Whether the file looks like a PDF. Doesn't touch the disk, so it's cheap enough for menus.
    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// A page of a PDF file on disk.
    public struct PageReference: Hashable, Sendable {
        public let document: URL
        /// Zero-based.
        public let index: Int

        public init(document: URL, index: Int) {
            self.document = document
            self.index = index
        }
    }

    /// Joins the documents in the order Finder sorts them by name ("2" before "10") and writes the result
    /// next to the first one as "Report (merged).pdf", "Report (merged) 2.pdf", … Nothing is written
    /// if any document can't be read.
    public static func merge(_ sources: [URL]) throws -> URL {
        let sorted = sortedByName(sources)
        guard sorted.count >= 2 else { throw Failure.tooFewDocuments }
        // Release the documents as soon as the result is written: they can be large.
        return try autoreleasepool {
            let documents = try openDocuments(sorted)
            let pages = sorted.flatMap { url in
                (0..<(documents[url]?.pageCount ?? 0)).map { PageReference(document: url, index: $0) }
            }
            return try write(merging: pages, from: documents)
        }
    }

    /// Joins the pages in the given order. The result is named after the document of the first page
    /// and saved next to it, like `merge(_:)` does.
    public static func merge(pages: [PageReference]) throws -> URL {
        guard !pages.isEmpty else { throw Failure.noPages }
        return try autoreleasepool {
            try write(merging: pages, from: openDocuments(pages.map(\.document)))
        }
    }

    private static func write(merging pages: [PageReference], from documents: [URL: PDFDocument]) throws -> URL {
        guard let first = pages.first?.document else { throw Failure.noPages }
        let name = first.deletingPathExtension().lastPathComponent
        return try write(pages, from: documents, baseName: String(localized: "\(name) (merged)"), in: first.deletingLastPathComponent())
    }

    /// Saves the chosen pages, in the document's order, as one file next to it: "Report (pages).pdf".
    /// - Parameter pages: Zero-based page indexes.
    public static func extract(pages: [Int], from source: URL) throws -> URL {
        let indexes = Array(Set(pages)).sorted()
        guard !indexes.isEmpty else { throw Failure.noPages }
        return try autoreleasepool {
            let references = indexes.map { PageReference(document: source, index: $0) }
            let name = source.deletingPathExtension().lastPathComponent
            return try write(references, from: [source: open(source)], baseName: String(localized: "\(name) (pages)"),
                             in: source.deletingLastPathComponent())
        }
    }

    private static func write(_ pages: [PageReference], from documents: [URL: PDFDocument], baseName: String, in folder: URL) throws -> URL {
        let result = PDFDocument()
        for reference in pages {
            // A page belongs to one document, so the result gets a copy.
            guard let page = try page(reference, in: documents).copy() as? PDFPage else { throw Failure.unreadable }
            result.insert(page, at: result.pageCount)
        }
        guard let data = result.dataRepresentation() else { throw Failure.unwritable }
        return try FileCreator.write(data, baseName: baseName, fileExtension: "pdf", in: folder)
    }

    /// Saves pages as "Report 1.pdf", "Report 2.pdf", … in a new folder "Report Pages" next to the document
    /// and returns the folder. Files are numbered as the pages are in the document. If a page fails,
    /// the folder is removed, so no partial result is left behind.
    /// - Parameter pages: Zero-based indexes of the pages to save; all of them if `nil`, which needs at least two.
    public static func split(_ source: URL, pages: [Int]? = nil) throws -> URL {
        try autoreleasepool {
            let document = try open(source)
            let indexes: [Int]
            if let pages {
                indexes = Array(Set(pages)).sorted()
                guard !indexes.isEmpty else { throw Failure.noPages }
                // Checked before the folder exists, so a changed document leaves nothing behind.
                guard indexes.allSatisfy({ (0..<document.pageCount).contains($0) }) else { throw Failure.modified }
            } else {
                guard document.pageCount > 1 else { throw Failure.singlePage }
                indexes = Array(0..<document.pageCount)
            }

            let name = source.deletingPathExtension().lastPathComponent
            let folder = try FileCreator.createFolder(baseName: String(localized: "\(name) Pages"), in: source.deletingLastPathComponent())
            do {
                for index in indexes {
                    try autoreleasepool {
                        guard let page = document.page(at: index)?.copy() as? PDFPage else { throw Failure.unreadable }
                        let single = PDFDocument()
                        single.insert(page, at: 0)
                        guard let data = single.dataRepresentation() else { throw Failure.unwritable }
                        try data.write(to: folder.appendingPathComponent("\(name) \(index + 1).pdf", isDirectory: false), options: .withoutOverwriting)
                    }
                }
            } catch {
                // The folder was created just now, so everything in it is ours.
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return folder
        }
    }

    /// In the order Finder sorts files by name: "2" before "10".
    public static func sortedByName(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Every distinct document opened once.
    private static func openDocuments(_ urls: [URL]) throws -> [URL: PDFDocument] {
        var documents: [URL: PDFDocument] = [:]
        for url in urls where documents[url] == nil {
            documents[url] = try open(url)
        }
        return documents
    }

    private static func page(_ reference: PageReference, in documents: [URL: PDFDocument]) throws -> PDFPage {
        // PDFKit raises an Objective-C exception for an index out of range, so check it first.
        guard let document = documents[reference.document], document.pageCount > reference.index, reference.index >= 0,
              let page = document.page(at: reference.index)
        else { throw Failure.modified }
        return page
    }

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        guard !document.isLocked else { throw Failure.locked }
        guard document.pageCount > 0 else { throw Failure.unreadable }
        return document
    }
}
