import Foundation

public struct CopyPathSettings: Codable, Equatable, Sendable {
    public enum PathFormat: String, Codable, CaseIterable, Sendable {
        /// "/Users/name/Documents"
        case full
        /// "~/Documents"
        case homeRelative
    }

    public var format = PathFormat.full

    public init() {}

    // Every field is optional so that settings saved by older versions still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A format added by a newer version falls back to the default instead of resetting everything.
        format = (try? container.decodeIfPresent(PathFormat.self, forKey: .format)) ?? .full
    }
}

extension SettingsStore {
    public var copyPath: CopyPathSettings {
        get { settings(CopyPathSettings.self, for: CopyPathModule.id) ?? CopyPathSettings() }
        nonmutating set { setSettings(newValue, for: CopyPathModule.id) }
    }
}
