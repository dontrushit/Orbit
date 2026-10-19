import CoreGraphics
import Foundation

/// What a page window needs to know about a PDF file before showing its pages.
public struct PDFDocumentInfo: Equatable, Sendable {
    public let url: URL
    public let pageCount: Int
    let stamp: FileStamp

    /// Reads the page count and fails with a `PDFTools.Failure` the user can act on: missing, locked or unreadable.
    public init(contentsOf url: URL) throws {
        stamp = try FileStamp(url)
        guard let document = CGPDFDocument(url as CFURL) else { throw PDFTools.Failure.unreadable }
        // Documents with only an owner password open with an empty one, as in Preview.
        if !document.isUnlocked, !document.unlockWithPassword("") {
            throw PDFTools.Failure.locked
        }
        guard document.numberOfPages > 0 else { throw PDFTools.Failure.unreadable }
        self.url = url
        pageCount = document.numberOfPages
    }

    /// Throws `.missing` or `.modified` if the file is no longer the one that was inspected:
    /// pages chosen in the window might not match its contents.
    public func verifyUnchanged() throws {
        guard try FileStamp(url) == stamp else { throw PDFTools.Failure.modified }
    }
}

/// Cheap evidence that a file hasn't changed: its modification date and size.
struct FileStamp: Equatable, Sendable {
    let modificationDate: Date?
    let size: Int?

    // Not `URL.resourceValues`: a URL caches them, so a second look at the same URL wouldn't see changes.
    init(_ url: URL) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            modificationDate = attributes[.modificationDate] as? Date
            size = (attributes[.size] as? NSNumber)?.intValue
        } catch CocoaError.fileReadNoSuchFile {
            throw PDFTools.Failure.missing
        }
    }
}
