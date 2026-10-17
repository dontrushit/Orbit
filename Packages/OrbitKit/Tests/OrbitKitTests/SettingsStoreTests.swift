import Foundation
import Testing
@testable import OrbitKit

// Serialized: all tests share one defaults suite, so they don't litter ~/Library/Preferences.
@Suite(.serialized) struct SettingsStoreTests {
    private struct TestModule: OrbitModule {
        var id: ModuleID = "test"
        var title: LocalizedStringResource { "Test" }
        var summary: LocalizedStringResource { "Test" }
        var symbolName: String { "star" }
        var tint: ModuleTint { .gray }
        var isEnabledByDefault = true
    }

    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
    }

    private let defaults: UserDefaults
    private let store: SettingsStore

    init() {
        defaults = UserDefaults(suiteName: "OrbitKitTests")!
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("module.") {
            defaults.removeObject(forKey: key)
        }
        store = SettingsStore(defaults: defaults)
    }

    @Test func enabledFallsBackToModuleDefault() {
        #expect(store.isEnabled(TestModule(isEnabledByDefault: true)))
        #expect(!store.isEnabled(TestModule(isEnabledByDefault: false)))
    }

    @Test func enabledStateIsPersisted() {
        let module = TestModule()
        store.setEnabled(false, for: module)
        #expect(!store.isEnabled(module))
        #expect(!SettingsStore(defaults: defaults).isEnabled(module))
    }

    @Test func modulesHaveIndependentState() {
        store.setEnabled(false, for: TestModule(id: "a"))
        #expect(store.isEnabled(TestModule(id: "b")))
    }

    @Test func settingsRoundTrip() {
        let sample = Sample(name: "Orbit", count: 3)
        store.setSettings(sample, for: "test")
        #expect(store.settings(Sample.self, for: "test") == sample)
    }

    @Test func missingSettingsAreNil() {
        #expect(store.settings(Sample.self, for: "test") == nil)
    }

    @Test func corruptSettingsAreNil() {
        defaults.set(Data("not json".utf8), forKey: "module.test.settings")
        #expect(store.settings(Sample.self, for: "test") == nil)
    }
}

@Suite struct AppGroupTests {
    @Test func readsResolvedIdentifier() {
        #expect(AppGroup.identifier(in: ["OrbitAppGroupID": "ABCDE12345.dev.orbit.mac.shared"]) == "ABCDE12345.dev.orbit.mac.shared")
    }

    @Test(arguments: [[:], ["OrbitAppGroupID": ""], ["OrbitAppGroupID": "$(ORBIT_APP_GROUP_ID)"]] as [[String: String]])
    func rejectsMissingOrUnresolvedIdentifier(info: [String: String]) {
        #expect(AppGroup.identifier(in: info) == nil)
    }
}

@Suite struct ModuleRegistryTests {
    @Test func moduleIDsAreUnique() {
        let ids = ModuleRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func findsModuleByID() {
        #expect(ModuleRegistry.module(withID: NewFileModule.id) != nil)
        #expect(ModuleRegistry.module(withID: "missing") == nil)
    }
}
