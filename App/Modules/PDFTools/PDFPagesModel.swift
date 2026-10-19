import AppKit
import Observation
import OrbitKit

/// State of a page window: the documents, the pages the user arranged or chose, and the work on them.
@MainActor @Observable
final class PDFPagesModel {
    enum Action {
        case merge
        case split
    }

    enum Phase {
        case loading, ready, saving
    }

    enum SplitOutput: Hashable {
        /// The chosen pages in one file.
        case oneFile
        /// Every chosen page in its own file.
        case separateFiles
    }

    struct Alert {
        let title: String
        let message: String
        /// The window has nothing left to show, so dismissing the alert closes it.
        let closesWindow: Bool
    }

    let action: Action
    let documents: [URL]
    var arrangement = PageArrangement(pages: [])
    var splitOutput = SplitOutput.oneFile
    private(set) var phase = Phase.loading
    var alert: Alert?

    @ObservationIgnored let thumbnails = PDFThumbnailLoader(maxPixelSize: 260)
    @ObservationIgnored private var infos: [PDFDocumentInfo] = []
    @ObservationIgnored private let close: () -> Void
    @ObservationIgnored private let logger = Log.logger("PDFTools")

    /// Reading and writing PDFs may block on CoreText, so it runs in a dispatch queue, not in Swift concurrency.
    private static let workQueue = DispatchQueue(label: "dev.orbit.PDFTools.work", qos: .userInitiated)

    init(request: PDFToolsRequest, close: @escaping () -> Void) {
        switch request {
        case .merge(let documents):
            action = .merge
            self.documents = documents
        case .split(let document):
            action = .split
            documents = [document]
        }
        self.close = close
    }

    var totalCount: Int { arrangement.items.count }
    var canPerform: Bool { phase == .ready && arrangement.includedCount > 0 }

    private var failureTitle: String {
        switch action {
        case .merge: String(localized: "Can’t Merge PDFs")
        case .split: String(localized: "Can’t Split PDF")
        }
    }

    /// Reads page counts, so that a locked or unreadable file is reported right away, not after the button is clicked.
    func load() {
        let documents = documents
        let action = action
        Self.workQueue.async { [weak self] in
            let result = Result {
                try documents.map { url in
                    try Self.attributed(to: url) {
                        let info = try PDFDocumentInfo(contentsOf: url)
                        if action == .split, info.pageCount < 2 { throw PDFTools.Failure.singlePage }
                        return info
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let infos):
                    self.infos = infos
                    self.arrangement = PageArrangement(documents: infos)
                    // Merge starts with every page; Split with none, the user picks what to take out.
                    if action == .split { self.arrangement.setAllIncluded(false) }
                    self.phase = .ready
                case .failure(let error):
                    self.show(error, closesWindow: true)
                }
            }
        }
    }

    /// Merges or splits, then shows the result in Finder and closes the window.
    func perform() {
        guard canPerform else { return }
        phase = .saving
        let infos = infos
        let action = action
        let pages = arrangement.includedPages
        let splitOutput = splitOutput
        Self.workQueue.async { [weak self] in
            let result = Result {
                for info in infos {
                    try Self.attributed(to: info.url) { try info.verifyUnchanged() }
                }
                switch (action, splitOutput) {
                case (.merge, _):
                    return try PDFTools.merge(pages: pages)
                case (.split, .oneFile):
                    return try PDFTools.extract(pages: pages.map(\.index), from: infos[0].url)
                case (.split, .separateFiles):
                    return try PDFTools.split(infos[0].url, pages: pages.map(\.index))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let url):
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    self.close()
                case .failure(let error):
                    self.phase = .ready
                    self.show(error, closesWindow: false)
                }
            }
        }
    }

    func cancel() {
        guard phase != .saving else { return }
        close()
    }

    func dismissAlert() {
        let closesWindow = alert?.closesWindow == true
        alert = nil
        if closesWindow { close() }
    }

    private func show(_ error: any Error, closesWindow: Bool) {
        logger.error("\(self.failureTitle, privacy: .public): \(String(describing: error), privacy: .public)")
        alert = Alert(title: failureTitle, message: Self.message(for: error), closesWindow: closesWindow)
    }

    // MARK: Errors

    /// A failure of a particular file, so the message can name it.
    private struct DocumentError: Error {
        let document: URL
        let underlying: any Error
    }

    private nonisolated static func attributed<T>(to document: URL, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw DocumentError(document: document, underlying: error)
        }
    }

    private static func message(for error: any Error) -> String {
        guard let error = error as? DocumentError else {
            switch error {
            case PDFTools.Failure.unreadable, PDFTools.Failure.modified:
                return String(localized: "One of the files can’t be read. Close the window and try again.")
            case let error as CocoaError:
                return error.localizedDescription
            default:
                return String(localized: "The PDF file couldn’t be saved.")
            }
        }
        let name = error.document.lastPathComponent
        switch error.underlying {
        case PDFTools.Failure.locked:
            return String(localized: "“\(name)” is protected with a password.")
        case PDFTools.Failure.missing:
            return String(localized: "“\(name)” was moved or deleted.")
        case PDFTools.Failure.modified:
            return String(localized: "“\(name)” changed while the window was open. Close the window and try again to see its current pages.")
        case PDFTools.Failure.singlePage:
            return String(localized: "“\(name)” has only one page, so there’s nothing to split.")
        default:
            return String(localized: "“\(name)” can’t be read. It may be damaged or not a PDF file.")
        }
    }
}
