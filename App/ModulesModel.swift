import Observation
import OrbitKit

/// On/off state of every module, kept in memory for the UI and persisted to the shared store.
@MainActor @Observable
final class ModulesModel {
    let modules: [any OrbitModule] = ModuleRegistry.all

    private var enabledIDs: Set<ModuleID>
    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore = .shared) {
        self.store = store
        enabledIDs = Set(ModuleRegistry.all.filter { store.isEnabled($0) }.map(\.id))
    }

    func isEnabled(_ module: any OrbitModule) -> Bool {
        enabledIDs.contains(module.id)
    }

    func setEnabled(_ isEnabled: Bool, for module: any OrbitModule) {
        store.setEnabled(isEnabled, for: module)
        if isEnabled {
            enabledIDs.insert(module.id)
        } else {
            enabledIDs.remove(module.id)
        }
    }
}
