import Foundation

/// Converts Word documents (.docx) to PDF locally, with system frameworks only.
///
/// Conversion is synchronous and blocks on CoreText. Call it from a dispatch queue, not from Swift concurrency
/// tasks: once every thread of the cooperative pool waits in CoreText at the same time, they deadlock.
public enum WordToPDFConverter {
    public static let sourceExtensions: Set<String> = ["docx", "docm", "dotx", "dotm"]

    /// Whether the file looks like a Word document. Doesn't touch the disk, so it's cheap enough for menus.
    public static func canConvert(_ url: URL) -> Bool {
        // Word keeps a hidden "~$Report.docx" lock file next to an open document; it isn't a document.
        sourceExtensions.contains(url.pathExtension.lowercased()) && !url.lastPathComponent.hasPrefix("~$")
    }

    /// Converts every document and returns the PDFs that were written. Documents that fail are logged
    /// and skipped, so one broken file doesn't cost the others; if none succeeds, the first error is thrown.
    public static func convert(_ sources: [URL]) throws -> [URL] {
        var results: [URL] = []
        var firstError: (any Error)?
        for source in sources {
            do {
                results.append(try convert(source))
            } catch {
                Log.logger("WordToPDF").error("Can't convert \(source.lastPathComponent, privacy: .private): \(String(describing: error), privacy: .public)")
                firstError = firstError ?? error
            }
        }
        if results.isEmpty, let firstError {
            throw firstError
        }
        return results
    }

    /// Writes the PDF next to the document under the first free name, "Report.pdf", "Report 2.pdf", …
    /// and returns its URL.
    public static func convert(_ source: URL) throws -> URL {
        let data = try pdfData(for: source)
        let baseName = source.deletingPathExtension().lastPathComponent
        return try FileCreator.write(data, baseName: baseName, fileExtension: "pdf", in: source.deletingLastPathComponent())
    }

    public static func pdfData(for source: URL) throws -> Data {
        // Layout creates many short-lived objects; release them as soon as the document is done.
        try autoreleasepool {
            let document = try DocumentBuilder(package: DocxPackage(contentsOf: source)).build()
            return try PDFRenderer(document: document).render(title: source.deletingPathExtension().lastPathComponent)
        }
    }
}
