import SwiftUI

/// Sections inserted into the PDF Tools module's detail screen. The module has no settings yet,
/// so the screen tells where to find it and what to expect from the result.
struct PDFToolsSettingsView: View {
    var body: some View {
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
