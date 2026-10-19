import AppKit
import OrbitKit
import SwiftUI

/// A window for choosing pages before merging or splitting PDF files.
@MainActor
final class PDFToolsWindowController: NSObject, NSWindowDelegate {
    /// Keeps controllers alive while their windows are open.
    private static var openControllers: [PDFToolsWindowController] = []

    private let window: NSWindow

    static func show(_ request: PDFToolsRequest) {
        let controller = PDFToolsWindowController(request: request)
        openControllers.append(controller)
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private init(request: PDFToolsRequest) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        super.init()

        let close: () -> Void = { [weak window] in window?.close() }
        switch request {
        case .merge(let documents):
            let model = PDFPagesModel(documents: documents, close: close)
            window.contentViewController = NSHostingController(rootView: MergeView(model: model))
            model.load()
        case .split:
            window.contentViewController = NSHostingController(rootView: PDFToolsPlaceholderView(request: request, close: close))
        }
        window.setContentSize(NSSize(width: 600, height: 450))
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.title = Self.title(for: request)
        // Unlike the main window's "main", so the app delegate never mistakes one for the other.
        window.identifier = NSUserInterfaceItemIdentifier("pdfTools")
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    private static func title(for request: PDFToolsRequest) -> String {
        switch request {
        case .merge: String(localized: "Merge PDFs")
        case .split(let document): String(localized: "Split \(document.lastPathComponent)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}

// Temporary content until the page grid is ready.
private struct PDFToolsPlaceholderView: View {
    let request: PDFToolsRequest
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(documents, id: \.self) { url in
                Text(verbatim: url.lastPathComponent)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var documents: [URL] {
        switch request {
        case .merge(let documents): documents
        case .split(let document): [document]
        }
    }
}
