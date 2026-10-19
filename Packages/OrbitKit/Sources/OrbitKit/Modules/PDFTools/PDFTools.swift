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
        case unwritable
    }

    /// Whether the file looks like a PDF. Doesn't touch the disk, so it's cheap enough for menus.
    public static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// Joins the documents in the order Finder sorts them by name ("2" before "10") and writes the result
    /// next to the first one as "Report (merged).pdf", "Report (merged) 2.pdf", … Nothing is written
    /// if any document can't be read.
    public static func merge(_ sources: [URL]) throws -> URL {
        let sorted = sources.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard sorted.count >= 2, let first = sorted.first else { throw Failure.tooFewDocuments }

        // Release the documents as soon as the result is written: they can be large.
        return try autoreleasepool {
            let merged = PDFDocument()
            for source in sorted {
                let document = try open(source)
                for index in 0..<document.pageCount {
                    // A page belongs to one document, so the merged one gets a copy.
                    guard let page = document.page(at: index)?.copy() as? PDFPage else { throw Failure.unreadable }
                    merged.insert(page, at: merged.pageCount)
                }
            }
            guard let data = merged.dataRepresentation() else { throw Failure.unwritable }
            let name = first.deletingPathExtension().lastPathComponent
            return try FileCreator.write(data, baseName: String(localized: "\(name) (merged)"), fileExtension: "pdf",
                                         in: first.deletingLastPathComponent())
        }
    }

    /// Saves every page as "Report 1.pdf", "Report 2.pdf", … in a new folder "Report Pages" next to the document
    /// and returns the folder. If a page fails, the folder is removed, so no partial result is left behind.
    public static func split(_ source: URL) throws -> URL {
        try autoreleasepool {
            let document = try open(source)
            guard document.pageCount > 1 else { throw Failure.singlePage }

            let name = source.deletingPathExtension().lastPathComponent
            let folder = try FileCreator.createFolder(baseName: String(localized: "\(name) Pages"), in: source.deletingLastPathComponent())
            do {
                for index in 0..<document.pageCount {
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

    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        guard !document.isLocked else { throw Failure.locked }
        guard document.pageCount > 0 else { throw Failure.unreadable }
        return document
    }
}
