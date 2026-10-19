import Foundation

public struct PDFToolsSettings: Codable, Equatable, Sendable {
    /// What a Finder menu item does when chosen.
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Process whole documents at once, from the extension.
        case immediate
        /// Open a window in Orbit to choose pages first.
        case choosePages
    }

    public var mergeMode = Mode.immediate
    public var splitMode = Mode.immediate

    public init() {}

    // Every field is optional so that settings saved by older versions still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A mode added by a newer version falls back to the default instead of resetting everything.
        mergeMode = (try? container.decodeIfPresent(Mode.self, forKey: .mergeMode)) ?? .immediate
        splitMode = (try? container.decodeIfPresent(Mode.self, forKey: .splitMode)) ?? .immediate
    }
}

extension SettingsStore {
    public var pdfTools: PDFToolsSettings {
        get { settings(PDFToolsSettings.self, for: PDFToolsModule.id) ?? PDFToolsSettings() }
        nonmutating set { setSettings(newValue, for: PDFToolsModule.id) }
    }
}
