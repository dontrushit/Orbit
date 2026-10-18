import Foundation

public struct NewFileSettings: Codable, Equatable, Sendable {
    /// Localized like the "Untitled" of system apps, since it ends up in file names.
    public static var defaultBaseName: String { String(localized: "Untitled") }

    /// How file types appear in the Finder context menu.
    public enum MenuStyle: String, Codable, CaseIterable, Sendable {
        /// One "New File" item with a submenu of file types.
        case submenu
        /// A separate item for every file type, right in the context menu.
        case inline
    }

    /// Stored as "disabled" so that file types added in future versions show up enabled.
    public var disabledTemplateIDs: Set<String> = []
    /// Name for new files as typed by the user; may be empty or unsafe — see `resolvedBaseName`.
    public var baseName = ""
    public var menuStyle = MenuStyle.submenu

    public init() {}

    // Every field is optional so that settings saved by older versions still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabledTemplateIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledTemplateIDs) ?? []
        baseName = try container.decodeIfPresent(String.self, forKey: .baseName) ?? ""
        // A style added by a newer version falls back to the default instead of resetting everything.
        menuStyle = (try? container.decodeIfPresent(MenuStyle.self, forKey: .menuStyle)) ?? .submenu
    }

    public func isEnabled(_ template: FileTemplate) -> Bool {
        !disabledTemplateIDs.contains(template.id)
    }

    public mutating func setEnabled(_ isEnabled: Bool, for template: FileTemplate) {
        if isEnabled {
            disabledTemplateIDs.remove(template.id)
        } else {
            disabledTemplateIDs.insert(template.id)
        }
    }

    public var enabledTemplates: [FileTemplate] {
        FileTemplate.builtIn.filter(isEnabled)
    }

    /// `baseName` made safe for the file system, or the default name if nothing usable is left.
    public var resolvedBaseName: String {
        let cleaned = baseName
            .replacing("/", with: "-")
            .replacing(":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0 == "." } // a leading dot would make the file hidden
            .prefix(Self.maxBaseNameLength)
        return cleaned.isEmpty ? Self.defaultBaseName : String(cleaned)
    }

    /// Leaves room for " 999.html" within the 255-byte file name limit.
    static let maxBaseNameLength = 200
}

extension SettingsStore {
    public var newFile: NewFileSettings {
        get { settings(NewFileSettings.self, for: NewFileModule.id) ?? NewFileSettings() }
        nonmutating set { setSettings(newValue, for: NewFileModule.id) }
    }
}
