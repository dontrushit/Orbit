import Foundation
import Testing
@testable import OrbitKit

@Suite struct PathFormatterTests {
    private let home = "/Users/anna"

    private func format(_ paths: [String], _ format: CopyPathSettings.PathFormat) -> String {
        PathFormatter.string(for: paths.map { URL(fileURLWithPath: $0) }, format: format, homeDirectory: home)
    }

    @Test(arguments: [
        ("/Users/anna/Documents/Report.pdf", "~/Documents/Report.pdf"),
        ("/Users/anna", "~"),
        ("/Applications/Safari.app", "/Applications/Safari.app"),
        ("/Users/annabel/Documents", "/Users/annabel/Documents"),
        ("/Users/anna/My Files/Отчёт 2.txt", "~/My Files/Отчёт 2.txt"),
    ])
    func formatsRelativeToHome(path: String, expected: String) {
        #expect(format([path], .homeRelative) == expected)
    }

    @Test(arguments: [
        "/Users/anna/Documents/Report.pdf",
        "/Users/anna",
        "/Users/anna/My Files/Отчёт 2.txt",
    ])
    func keepsFullPath(path: String) {
        #expect(format([path], .full) == path)
    }

    @Test func dropsTrailingSlashOfFolders() {
        let folder = URL(fileURLWithPath: "/Users/anna/Documents/", isDirectory: true)
        #expect(PathFormatter.string(for: [folder], format: .full, homeDirectory: home) == "/Users/anna/Documents")
    }

    @Test func acceptsHomeWithTrailingSlash() {
        let url = URL(fileURLWithPath: "/Users/anna/Documents")
        #expect(PathFormatter.string(for: [url], format: .homeRelative, homeDirectory: "/Users/anna/") == "~/Documents")
    }

    @Test func putsEveryPathOnItsOwnLine() {
        let paths = ["/Users/anna/a.txt", "/Users/anna/Folder", "/tmp/b.txt"]
        #expect(format(paths, .homeRelative) == "~/a.txt\n~/Folder\n/tmp/b.txt")
        #expect(format(paths, .full) == paths.joined(separator: "\n"))
    }

    @Test func findsRealHomeDirectory() {
        #expect(PathFormatter.userHomeDirectory.hasPrefix("/"))
        #expect(!PathFormatter.userHomeDirectory.contains("/Library/Containers/"))
    }
}

@Suite struct CopyPathSettingsTests {
    @Test func defaultsToFullPath() {
        #expect(CopyPathSettings().format == .full)
    }

    @Test func decodesSettingsWithMissingFields() throws {
        let settings = try JSONDecoder().decode(CopyPathSettings.self, from: Data("{}".utf8))
        #expect(settings == CopyPathSettings())
    }

    @Test func unknownFormatFallsBackToDefault() throws {
        let json = #"{"format": "url"}"#
        let settings = try JSONDecoder().decode(CopyPathSettings.self, from: Data(json.utf8))
        #expect(settings == CopyPathSettings())
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = CopyPathSettings()
        settings.format = .homeRelative
        let decoded = try JSONDecoder().decode(CopyPathSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}

// Serialized: all tests share one defaults suite, so they don't litter ~/Library/Preferences.
@Suite(.serialized) struct CopyPathMenuTests {
    private let store: SettingsStore
    private let folder = URL(fileURLWithPath: PathFormatter.userHomeDirectory).appendingPathComponent("Projects")

    init() {
        let defaults = UserDefaults(suiteName: "OrbitKitTests.CopyPath")!
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("module.") {
            defaults.removeObject(forKey: key)
        }
        store = SettingsStore(defaults: defaults)
    }

    private func perform(_ context: FinderContext) throws -> FinderActionResult? {
        let items = FinderMenu.items(store: store, modules: [CopyPathModule()])
        try #require(items.count == 1)
        guard case .action(let action) = items[0].kind else {
            Issue.record("Copy Path should be an action")
            return nil
        }
        return try action(context)
    }

    @Test func disabledModuleAddsNothing() {
        store.setEnabled(false, for: CopyPathModule())
        #expect(FinderMenu.items(store: store, modules: [CopyPathModule()]).isEmpty)
    }

    @Test func comesAfterNewFile() {
        let items = FinderMenu.items(store: store)
        #expect(items.map { String(localized: $0.title) } == ["New File", "Copy Path"])
    }

    @Test func copiesSelectedItems() throws {
        let selection = [folder.appendingPathComponent("a.txt"), folder.appendingPathComponent("b c.txt")]
        let result = try perform(FinderContext(targetFolder: folder, selectedItems: selection))
        #expect(result == .copy("\(folder.path)/a.txt\n\(folder.path)/b c.txt"))
    }

    @Test func copiesTargetFolderWithoutSelection() throws {
        #expect(try perform(FinderContext(targetFolder: folder)) == .copy(folder.path))
    }

    @Test func usesFormatFromSettings() throws {
        var settings = store.copyPath
        settings.format = .homeRelative
        store.copyPath = settings
        #expect(try perform(FinderContext(targetFolder: folder)) == .copy("~/Projects"))
    }
}
