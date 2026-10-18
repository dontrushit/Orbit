import OrbitKit
import SwiftUI

/// Sections inserted into the Copy Path module's detail screen.
struct CopyPathSettingsView: View {
    @State private var model = CopyPathSettingsModel()

    var body: some View {
        Section {
            Picker("Path Format", selection: $model.settings.format) {
                Text("Full Path").tag(CopyPathSettings.PathFormat.full)
                Text("Relative to Home Folder").tag(CopyPathSettings.PathFormat.homeRelative)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Path Format")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paths look like “\(example)”. When several items are selected, each path goes on its own line.")
                // Since macOS 14, Finder doesn't show third-party Finder Sync menu items in iCloud Drive.
                Text("The menu isn’t available in iCloud Drive folders, including Desktop and Documents when they’re stored in iCloud.")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var example: String {
        let home = PathFormatter.userHomeDirectory
        let documents = URL(fileURLWithPath: home).appendingPathComponent("Documents", isDirectory: true)
        return PathFormatter.string(for: [documents], format: model.settings.format, homeDirectory: home)
    }
}

@MainActor @Observable
private final class CopyPathSettingsModel {
    var settings: CopyPathSettings {
        didSet {
            if settings != oldValue { store.copyPath = settings }
        }
    }

    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = .shared) {
        self.store = store
        settings = store.copyPath
    }
}
