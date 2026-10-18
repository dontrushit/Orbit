import Foundation

/// Copies paths of files and folders from the Finder context menu.
public struct CopyPathModule: OrbitModule {
    public static let id: ModuleID = "copyPath"

    public init() {}

    public var id: ModuleID { Self.id }
    public var title: LocalizedStringResource { "Copy Path" }
    public var summary: LocalizedStringResource { "Copy the full path of files and folders right from the Finder context menu." }
    public var symbolName: String { "doc.on.clipboard" }
    public var tint: ModuleTint { .green }
}

extension CopyPathModule: FinderMenuProviding {
    public func finderMenuItems(store: SettingsStore) -> [FinderMenuItem] {
        let format = store.copyPath.format
        return [FinderMenuItem(title: "Copy Path", icon: .symbol(symbolName)) { context in
            // On the folder background there's no selection: copy the folder itself.
            let urls = context.selectedItems.isEmpty ? [context.targetFolder] : context.selectedItems
            return .copy(PathFormatter.string(for: urls, format: format, homeDirectory: PathFormatter.userHomeDirectory))
        }]
    }
}
