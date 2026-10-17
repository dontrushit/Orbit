import Foundation

/// Persistent settings shared between Orbit.app and its extensions.
///
/// Backed by `UserDefaults`, which is thread-safe and cheap to read, so the Finder extension
/// can read fresh values every time it builds a menu instead of keeping them in sync.
public struct SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The store in the shared App Group container.
    ///
    /// Falls back to the process's own defaults when the group is unavailable (e.g. an unsigned
    /// build): the app keeps working, but the extension won't see its changes.
    public static let shared: SettingsStore = {
        if let group = AppGroup.identifier, let defaults = UserDefaults(suiteName: group) {
            return SettingsStore(defaults: defaults)
        }
        Log.logger("Settings").error("App Group is unavailable; settings are not shared with extensions")
        return SettingsStore(defaults: .standard)
    }()

    // MARK: Module state

    public func isEnabled(_ module: some OrbitModule) -> Bool {
        defaults.object(forKey: Key.enabled(module.id)) as? Bool ?? module.isEnabledByDefault
    }

    public func setEnabled(_ isEnabled: Bool, for module: some OrbitModule) {
        defaults.set(isEnabled, forKey: Key.enabled(module.id))
    }

    // MARK: Module settings

    /// Decoded settings of a module, or `nil` if none were saved or the stored data is unreadable
    /// (for example, written by an incompatible version). Callers fall back to their defaults.
    public func settings<Value: Decodable>(_ type: Value.Type, for moduleID: ModuleID) -> Value? {
        guard let data = defaults.data(forKey: Key.settings(moduleID)) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Log.logger("Settings").error("Can't decode settings of \(moduleID, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    public func setSettings(_ value: some Encodable, for moduleID: ModuleID) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: Key.settings(moduleID))
        } catch {
            Log.logger("Settings").error("Can't encode settings of \(moduleID, privacy: .public): \(error, privacy: .public)")
        }
    }

    private enum Key {
        static func enabled(_ id: ModuleID) -> String { "module.\(id).enabled" }
        static func settings(_ id: ModuleID) -> String { "module.\(id).settings" }
    }
}
