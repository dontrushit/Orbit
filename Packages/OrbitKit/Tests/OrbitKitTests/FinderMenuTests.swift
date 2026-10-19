import Foundation
import Testing
@testable import OrbitKit

// Serialized: all tests share one defaults suite, so they don't litter ~/Library/Preferences.
@Suite(.serialized) final class FinderMenuTests {
    private let store: SettingsStore
    private let folder: URL

    init() throws {
        let defaults = UserDefaults(suiteName: "OrbitKitTests.FinderMenu")!
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("module.") {
            defaults.removeObject(forKey: key)
        }
        store = SettingsStore(defaults: defaults)

        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// New File items only, so the tests don't depend on other modules.
    private func items() -> [FinderMenuItem] {
        FinderMenu.items(store: store, modules: [NewFileModule()])
    }

    private func newFileSubmenu() throws -> [FinderMenuItem] {
        let items = self.items()
        try #require(items.count == 1)
        guard case .submenu(let children) = items[0].kind else {
            Issue.record("New File should be a submenu")
            return []
        }
        return children
    }

    @Test func newFileShowsEnabledTemplates() throws {
        var settings = store.newFile
        settings.setEnabled(false, for: .markdown)
        store.newFile = settings

        let children = try newFileSubmenu()
        #expect(children.map(\.icon) == [.fileType("txt"), .fileType("json"), .fileType("html")])
    }

    @Test func inlineStyleListsTemplatesInContextMenu() {
        var settings = store.newFile
        settings.menuStyle = .inline
        settings.setEnabled(false, for: .html)
        store.newFile = settings

        let items = self.items()
        #expect(items.map(\.icon) == [.fileType("txt"), .fileType("md"), .fileType("json")])
        #expect(items.map { String(localized: $0.title) } == ["New Text File", "New Markdown File", "New JSON File"])
        #expect(items.allSatisfy { !$0.isLongRunning })
        for item in items {
            guard case .action = item.kind else {
                Issue.record("Inline items should be actions")
                return
            }
        }
    }

    @Test func inlineActionCreatesFile() throws {
        var settings = store.newFile
        settings.menuStyle = .inline
        store.newFile = settings

        guard case .action(let action) = items()[0].kind else {
            Issue.record("Inline item should be an action")
            return
        }
        #expect(try action(FinderContext(targetFolder: folder)) == .reveal([folder.appendingPathComponent("Untitled.txt")]))
    }

    @Test func disabledModuleAddsNothing() {
        store.setEnabled(false, for: NewFileModule())
        #expect(items().isEmpty)
    }

    @Test(arguments: NewFileSettings.MenuStyle.allCases)
    func noTemplatesAddsNothing(style: NewFileSettings.MenuStyle) {
        var settings = store.newFile
        settings.menuStyle = style
        FileTemplate.builtIn.forEach { settings.setEnabled(false, for: $0) }
        store.newFile = settings
        #expect(items().isEmpty)
    }

    @Test func actionCreatesFileAndRevealsIt() throws {
        var settings = store.newFile
        settings.baseName = "Note"
        store.newFile = settings

        guard case .action(let action) = try newFileSubmenu()[1].kind else {
            Issue.record("Template item should be an action")
            return
        }
        let result = try action(FinderContext(targetFolder: folder))

        let expected = folder.appendingPathComponent("Note.md")
        #expect(result == .reveal([expected]))
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    private func createFile(selecting selection: [URL]) throws -> URL? {
        guard case .action(let action) = try newFileSubmenu()[0].kind else {
            Issue.record("Template item should be an action")
            return nil
        }
        guard case .reveal(let urls) = try action(FinderContext(targetFolder: folder, selectedItems: selection)), urls.count == 1 else {
            Issue.record("New File should reveal the created file")
            return nil
        }
        return urls[0]
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func createsFileInsideSelectedFolder() throws {
        let subfolder = try makeFolder("Projects")
        #expect(try createFile(selecting: [subfolder]) == subfolder.appendingPathComponent("Untitled.txt"))
    }

    @Test(arguments: ["Tool.app", "Plugin.bundle"])
    func createsFileNextToSelectedPackage(name: String) throws {
        let package = try makeFolder(name)
        #expect(try createFile(selecting: [package]) == folder.appendingPathComponent("Untitled.txt"))
    }

    @Test func createsFileNextToSelectedFile() throws {
        let file = folder.appendingPathComponent("Notes.txt")
        try Data().write(to: file)
        #expect(try createFile(selecting: [file]) == folder.appendingPathComponent("Untitled.txt"))
    }

    @Test func createsFileNextToSeveralSelectedFolders() throws {
        let selection = [try makeFolder("A"), try makeFolder("B")]
        #expect(try createFile(selecting: selection) == folder.appendingPathComponent("Untitled.txt"))
    }
}
