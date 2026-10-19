import OrbitKit
import SwiftUI

/// Sections inserted into the PDF Tools module's detail screen.
struct PDFToolsSettingsView: View {
    @State private var model = PDFToolsSettingsModel()

    var body: some View {
        Section("Merge PDFs") {
            Picker("Merge PDFs", selection: $model.settings.mergeMode) {
                Text("Merge right away").tag(PDFToolsSettings.Mode.immediate)
                Text("Choose pages and order first").tag(PDFToolsSettings.Mode.choosePages)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section("Split PDF") {
            Picker("Split PDF", selection: $model.settings.splitMode) {
                Text("Each page as a separate file").tag(PDFToolsSettings.Mode.immediate)
                Text("Choose pages first").tag(PDFToolsSettings.Mode.choosePages)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section {
            Label("Select several PDF files in Finder, Control-click and choose Merge PDFs. Pages follow the order of file names.", systemImage: "arrow.triangle.merge")
            Label("Select one PDF file and choose Split PDF to save each page as a separate file.", systemImage: "arrow.triangle.branch")
            Label("The merged PDF is saved next to the first file, the pages of a split PDF in a new folder next to it. An existing file is never replaced.", systemImage: "doc.on.doc")
            Label("PDF files are processed on this Mac. They aren’t uploaded anywhere.", systemImage: "lock")
        } header: {
            Text("How It Works")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bookmarks (the table of contents) aren’t kept when files are merged. Password-protected PDF files can’t be merged or split.")
                // Since macOS 14, Finder doesn't show third-party Finder Sync menu items in iCloud Drive.
                Text("The menu isn’t available in iCloud Drive folders, including Desktop and Documents when they’re stored in iCloud.")
            }
            .foregroundStyle(.secondary)
        }
    }
}

@MainActor @Observable
private final class PDFToolsSettingsModel {
    var settings: PDFToolsSettings {
        didSet {
            if settings != oldValue { store.pdfTools = settings }
        }
    }

    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = .shared) {
        self.store = store
        settings = store.pdfTools
    }
}
