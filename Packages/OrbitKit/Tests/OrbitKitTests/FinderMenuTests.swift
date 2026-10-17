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

    private func newFileSubmenu() throws -> [FinderMenuItem] {
        let items = FinderMenu.items(store: store)
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

    @Test func disabledModuleAddsNothing() {
        store.setEnabled(false, for: NewFileModule())
        #expect(FinderMenu.items(store: store).isEmpty)
    }

    @Test func noTemplatesAddsNothing() {
        var settings = store.newFile
        FileTemplate.builtIn.forEach { settings.setEnabled(false, for: $0) }
        store.newFile = settings
        #expect(FinderMenu.items(store: store).isEmpty)
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
        #expect(result == .reveal(expected))
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }
}
