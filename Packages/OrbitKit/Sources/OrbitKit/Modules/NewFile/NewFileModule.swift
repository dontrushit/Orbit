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
    public func finderMenuItems(store: SettingsStore) -> [FinderMenuItem] {
        let settings = store.newFile
        let templates = settings.enabledTemplates
        guard !templates.isEmpty else { return [] }

        let baseName = settings.resolvedBaseName
        func item(for template: FileTemplate, title: LocalizedStringResource) -> FinderMenuItem {
            FinderMenuItem(title: title, icon: .fileType(template.fileExtension)) { context in
                .reveal(try FileCreator.createFile(from: template, baseName: baseName, in: context.targetFolder))
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
