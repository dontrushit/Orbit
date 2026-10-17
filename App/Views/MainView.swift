import OrbitKit
import SwiftUI

struct MainView: View {
    @State private var modules = ModulesModel()
    @State private var extensionStatus = FinderExtensionStatus()
    @State private var path: [ModuleID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if !extensionStatus.isEnabled {
                    Section {
                        ExtensionBanner(status: extensionStatus)
                    }
                }

                Section("Modules") {
                    ForEach(modules.modules, id: \.id) { module in
                        ModuleRow(
                            module: module,
                            isEnabled: isEnabled(module),
                            showSettings: ModuleSettingsScreens.hasSettings(for: module.id) ? { path.append(module.id) } : nil
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Orbit")
            .navigationDestination(for: ModuleID.self) { id in
                if let module = ModuleRegistry.module(withID: id) {
                    ModuleDetailView(module: module, isEnabled: isEnabled(module))
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionStatus.refresh()
        }
    }

    private func isEnabled(_ module: any OrbitModule) -> Binding<Bool> {
        Binding(
            get: { modules.isEnabled(module) },
            set: { modules.setEnabled($0, for: module) }
        )
    }
}

#Preview {
    MainView()
}
