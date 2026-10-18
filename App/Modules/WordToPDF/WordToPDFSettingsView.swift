import SwiftUI

/// Sections inserted into the Word to PDF module's detail screen. The module has no settings,
/// so the screen tells where to find it and what to expect from the result.
struct WordToPDFSettingsView: View {
    var body: some View {
        Section {
            Label("Select Word documents in Finder, Control-click and choose Convert to PDF.", systemImage: "cursorarrow.click.2")
            Label("The PDF is saved next to the document. An existing file is never replaced.", systemImage: "doc.on.doc")
            Label("Conversion happens on this Mac. Documents aren’t uploaded anywhere.", systemImage: "lock")
        } header: {
            Text("How It Works")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pictures in EMF and WMF formats, such as equations from the old Equation Editor, appear as empty frames. Footnotes are placed at the end of the document.")
                // Since macOS 14, Finder doesn't show third-party Finder Sync menu items in iCloud Drive.
                Text("The menu isn’t available in iCloud Drive folders, including Desktop and Documents when they’re stored in iCloud.")
            }
            .foregroundStyle(.secondary)
        }
    }
}
