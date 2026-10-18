import Foundation

/// Creates new files from the Finder context menu.
public struct NewFileModule: OrbitModule {
    public static let id: ModuleID = "newFile"

    public init() {}

    public var id: ModuleID { Self.id }
    public var title: LocalizedStringResource { "New File" }
    public var summary: LocalizedStringResource { "Create text, Markdown, JSON and HTML files right from the Finder context menu." }
    public var symbolName: String { "doc.badge.plus" }
    public var tint: ModuleTint { .blue }
}

extension NewFileModule: FinderMenuProviding {
    public func finderMenuItems(store: SettingsStore, selection: [URL]) -> [FinderMenuItem] {
        let settings = store.newFile
        let templates = settings.enabledTemplates
        guard !templates.isEmpty else { return [] }

        let baseName = settings.resolvedBaseName
        func item(for template: FileTemplate, title: LocalizedStringResource) -> FinderMenuItem {
            FinderMenuItem(title: title, icon: .fileType(template.fileExtension)) { context in
                .reveal([try FileCreator.createFile(from: template, baseName: baseName, in: Self.destination(for: context))])
            }
        }

        switch settings.menuStyle {
        case .submenu:
            let children = templates.map { item(for: $0, title: $0.name) }
            return [FinderMenuItem(title: "New File", icon: .symbol(symbolName), children: children)]
        case .inline:
            return templates.map { item(for: $0, title: $0.menuTitle) }
        }
    }
}

extension NewFileModule {
    /// A single right-clicked folder gets the file inside it. Otherwise — files, several items,
    /// packages such as .app or .bundle that look like files in Finder — it goes next to them.
    static func destination(for context: FinderContext) -> URL {
        guard context.selectedItems.count == 1, let item = context.selectedItems.first,
              let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true
        else { return context.targetFolder }
        return item
    }
}
