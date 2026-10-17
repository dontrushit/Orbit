import Foundation

/// The App Group shared by Orbit.app and its extensions.
public enum AppGroup {
    /// Info.plist key holding the resolved group ID, injected at build time from `ORBIT_APP_GROUP_ID`.
    static let infoPlistKey = "OrbitAppGroupID"

    /// The group ID of the running bundle, or `nil` if the build didn't provide one.
    public static var identifier: String? {
        identifier(in: Bundle.main.infoDictionary ?? [:])
    }

    static func identifier(in infoDictionary: [String: Any]) -> String? {
        guard let value = infoDictionary[infoPlistKey] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        // An unexpanded build variable means the plist wasn't processed by Xcode.
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
