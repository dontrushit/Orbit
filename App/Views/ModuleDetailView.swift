import OrbitKit
import SwiftUI

struct ModuleDetailView: View {
    let module: any OrbitModule
    @Binding var isEnabled: Bool

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    ModuleIcon(symbolName: module.symbolName, tint: module.tint, size: 56)
                    Text(module.title)
                        .font(.title2.weight(.semibold))
                    Text(module.summary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Toggle("Enabled", isOn: $isEnabled)
            }

            if let settings = ModuleSettingsScreens.view(for: module.id) {
                settings
                    .disabled(!isEnabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(module.title))
    }
}

/// Maps modules to their settings screens. A module without an entry has no settings.
enum ModuleSettingsScreens {
    @MainActor
    static func view(for id: ModuleID) -> AnyView? {
        switch id {
        case NewFileModule.id: AnyView(NewFileSettingsView())
        default: nil
        }
    }

    @MainActor
    static func hasSettings(for id: ModuleID) -> Bool {
        view(for: id) != nil
    }
}
