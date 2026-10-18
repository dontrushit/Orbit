import Foundation

/// Where a Finder menu action was invoked.
public struct FinderContext: Sendable {
    /// The folder the user right-clicked in.
    public let targetFolder: URL
    /// The items the user right-clicked; empty when the menu was opened on the folder background.
    public let selectedItems: [URL]

    public init(targetFolder: URL, selectedItems: [URL] = []) {
        self.targetFolder = targetFolder
        self.selectedItems = selectedItems
    }
}

/// What the Finder extension should do after an action succeeds.
public enum FinderActionResult: Sendable, Equatable {
    case done
    /// Select the items in Finder.
    case reveal([URL])
    /// Put the text on the clipboard.
    case copy(String)
}

/// A platform-neutral description of a Finder context menu item. The extension turns it into `NSMenuItem`.
public struct FinderMenuItem: Sendable {
    public typealias Action = @Sendable (FinderContext) throws -> FinderActionResult

    public enum Icon: Sendable, Equatable {
        case symbol(String)
        /// The Finder icon for files with this extension.
        case fileType(String)
    }

    public enum Kind: Sendable {
        case action(Action)
        case submenu([FinderMenuItem])
    }

    public let title: LocalizedStringResource
    public let icon: Icon?
    public let kind: Kind

    public init(title: LocalizedStringResource, icon: Icon? = nil, action: @escaping Action) {
        self.title = title
        self.icon = icon
        kind = .action(action)
    }

    public init(title: LocalizedStringResource, icon: Icon? = nil, children: [FinderMenuItem]) {
        self.title = title
        self.icon = icon
        kind = .submenu(children)
    }
}

/// A module that adds items to the Finder context menu.
public protocol FinderMenuProviding: OrbitModule {
    /// Called every time the menu opens, so it must be cheap: no file access. Return `[]` to add nothing.
    /// - Parameter selection: The items the menu was opened on; empty on the folder background.
    func finderMenuItems(store: SettingsStore, selection: [URL]) -> [FinderMenuItem]
}

public enum FinderMenu {
    /// Items from every enabled module, in registry order.
    public static func items(store: SettingsStore, selection: [URL] = [], modules: [any OrbitModule] = ModuleRegistry.all) -> [FinderMenuItem] {
        modules
            .filter { store.isEnabled($0) }
            .compactMap { $0 as? any FinderMenuProviding }
            .flatMap { $0.finderMenuItems(store: store, selection: selection) }
    }
}
