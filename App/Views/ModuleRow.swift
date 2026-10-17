import OrbitKit
import SwiftUI

struct ModuleRow: View {
    let module: any OrbitModule
    @Binding var isEnabled: Bool
    /// `nil` when the module has nothing to configure.
    let showSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ModuleIcon(symbolName: module.symbolName, tint: module.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                Text(module.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let showSettings {
                Button(action: showSettings) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel(Text("Settings"))
            }

            Toggle(isOn: $isEnabled) {
                Text(module.title)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
