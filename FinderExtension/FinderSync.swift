import Cocoa
import FinderSync
import OrbitKit
import UniformTypeIdentifiers

final class FinderSync: FIFinderSync {
    private let logger = Log.logger("FinderSync")
    /// Actions run here, one at a time. Not in a Swift concurrency task: conversion blocks on CoreText,
    /// which deadlocks once every thread of the cooperative pool waits for it.
    private static let actionQueue = DispatchQueue(label: "dev.orbit.FinderSync.actions", qos: .userInitiated)

    /// Actions of the menu built most recently, indexed by `NSMenuItem.tag`.
    /// Finder hands the action a copy of the menu item, so only the tag survives the round trip.
    private var actions: [FinderMenuItem.Action] = []
    /// Kind of the menu built most recently. Only the items menu acts on the selection:
    /// on the folder background the subject is the folder itself.
    private var menuKind = FIMenuKind.contextualMenuForContainer

    override init() {
        super.init()
        // Observe the whole file system so the menu appears in every folder.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        logger.info("Finder extension started")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else { return nil }

        let selection = menuKind == .contextualMenuForItems ? FIFinderSyncController.default().selectedItemURLs() ?? [] : []
        let items = FinderMenu.items(store: .shared, selection: selection)
        guard !items.isEmpty else { return nil }

        self.menuKind = menuKind
        actions = []
        let menu = NSMenu(title: "")
        for item in items {
            menu.addItem(makeMenuItem(item))
        }
        return menu
    }

    private func makeMenuItem(_ item: FinderMenuItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: String(localized: item.title), action: nil, keyEquivalent: "")
        menuItem.image = item.icon.flatMap(image(for:))

        switch item.kind {
        case .action(let action):
            menuItem.action = #selector(performAction(_:))
            menuItem.tag = actions.count
            actions.append(action)
        case .submenu(let children):
            let submenu = NSMenu(title: menuItem.title)
            for child in children {
                submenu.addItem(makeMenuItem(child))
            }
            menuItem.submenu = submenu
        }
        return menuItem
    }

    private func image(for icon: FinderMenuItem.Icon) -> NSImage? {
        switch icon {
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .fileType(let fileExtension):
            let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? .data)
            image.size = NSSize(width: 16, height: 16)
            return image
        }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else {
            logger.error("Unknown menu action \(sender.tag)")
            return
        }
        // Items menu: targetedURL() is still the folder being shown, which is where new items belong.
        let controller = FIFinderSyncController.default()
        guard let folder = controller.targetedURL() else {
            logger.error("No targeted folder")
            return
        }
        let selectedItems = menuKind == .contextualMenuForItems ? controller.selectedItemURLs() ?? [] : []
        let action = actions[sender.tag]
        let context = FinderContext(targetFolder: folder, selectedItems: selectedItems)
        let logger = logger

        // Off the main thread: converting a long document takes a while, and the extension must keep answering Finder.
        Self.actionQueue.async {
            do {
                let result = try action(context)
                DispatchQueue.main.async { Self.apply(result) }
            } catch {
                logger.error("Action failed in \(folder.path, privacy: .public): \(error, privacy: .public)")
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    @MainActor
    private static func apply(_ result: FinderActionResult) {
        switch result {
        case .done:
            break
        case .reveal(let urls):
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .copy(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
}
