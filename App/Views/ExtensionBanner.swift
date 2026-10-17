import SwiftUI

/// Explains that the Finder extension is off and leads the user to the switch in System Settings.
struct ExtensionBanner: View {
    let status: FinderExtensionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Finder extension is turned off")
                    .font(.headline)
                Text("Turn on Orbit in General → Login Items & Extensions → Finder to add items to the context menu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Turn On…") {
                status.openSystemSettings()
            }
        }
        .padding(.vertical, 4)
    }
}
