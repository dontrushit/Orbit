import Foundation

/// What Orbit.app does with PDF files opened in it, by the Finder extension or any other way (such as the Dock).
///
/// The Finder menu offers Merge only for several PDFs and Split only for one, so the number of files
/// tells the two apart.
public enum PDFToolsRequest: Equatable, Sendable {
    /// Documents in the order Finder sorts them by name.
    case merge([URL])
    case split(URL)

    /// `nil` if there is no PDF file among `urls`.
    public init?(urls: [URL]) {
        var seen = Set<String>()
        let documents = urls.filter { $0.isFileURL && PDFTools.isPDF($0) && seen.insert($0.standardizedFileURL.path).inserted }
        switch documents.count {
        case 0: return nil
        case 1: self = .split(documents[0])
        default: self = .merge(PDFTools.sortedByName(documents))
        }
    }
}
