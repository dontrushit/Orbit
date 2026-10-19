import Foundation
import Testing
@testable import OrbitKit

@Suite final class FileCreatorTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func create(_ template: FileTemplate = .plainText) throws -> URL {
        try FileCreator.createFile(from: template, baseName: "Untitled", in: folder)
    }

    @Test(arguments: FileTemplate.builtIn)
    func createsFileWithTemplateContents(template: FileTemplate) throws {
        let url = try create(template)
        #expect(url.lastPathComponent == "Untitled.\(template.fileExtension)")
        #expect(try String(contentsOf: url, encoding: .utf8) == template.contents)
    }

    @Test func numbersSubsequentFiles() throws {
        let names = try (1...3).map { _ in try create().lastPathComponent }
        #expect(names == ["Untitled.txt", "Untitled 2.txt", "Untitled 3.txt"])
    }

    @Test func neverOverwritesExistingFiles() throws {
        let existing = folder.appendingPathComponent("Untitled.txt")
        try Data("keep me".utf8).write(to: existing)

        #expect(try create().lastPathComponent == "Untitled 2.txt")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep me")
    }

    @Test func treatsFolderWithSameNameAsTaken() throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Untitled.txt"), withIntermediateDirectories: false)
        #expect(try create().lastPathComponent == "Untitled 2.txt")
    }

    @Test func differentExtensionsDontCollide() throws {
        _ = try create(.plainText)
        #expect(try create(.markdown).lastPathComponent == "Untitled.md")
    }

    @Test func throwsForMissingFolder() {
        #expect(throws: (any Error).self) {
            try FileCreator.createFile(from: .plainText, baseName: "Untitled", in: self.folder.appendingPathComponent("missing"))
        }
    }

    @Test func numbersFoldersAndTreatsFilesAsTaken() throws {
        try Data().write(to: folder.appendingPathComponent("Pages 2"))
        let names = try (1...2).map { _ in try FileCreator.createFolder(baseName: "Pages", in: folder).lastPathComponent }
        #expect(names == ["Pages", "Pages 3"])
    }
}

@Suite struct NewFileSettingsTests {
    @Test func allTemplatesEnabledByDefault() {
        #expect(NewFileSettings().enabledTemplates.map(\.id) == FileTemplate.builtIn.map(\.id))
    }

    @Test func disablingKeepsMenuOrder() {
        var settings = NewFileSettings()
        settings.setEnabled(false, for: .markdown)
        #expect(settings.enabledTemplates.map(\.id) == ["txt", "json", "html"])
        settings.setEnabled(true, for: .markdown)
        #expect(settings.enabledTemplates.map(\.id) == ["txt", "md", "json", "html"])
    }

    @Test func decodesSettingsWithMissingFields() throws {
        let settings = try JSONDecoder().decode(NewFileSettings.self, from: Data("{}".utf8))
        #expect(settings == NewFileSettings())
    }

    @Test func unknownMenuStyleFallsBackToDefault() throws {
        let json = #"{"baseName": "Note", "menuStyle": "carousel"}"#
        let settings = try JSONDecoder().decode(NewFileSettings.self, from: Data(json.utf8))
        #expect(settings.menuStyle == .submenu)
        #expect(settings.baseName == "Note")
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = NewFileSettings()
        settings.setEnabled(false, for: .html)
        settings.baseName = "Note"
        settings.menuStyle = .inline
        let decoded = try JSONDecoder().decode(NewFileSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test(arguments: [
        ("", "Untitled"),
        ("   ", "Untitled"),
        ("Note", "Note"),
        ("  Note  ", "Note"),
        ("a/b:c", "a-b-c"),
        (".hidden", "hidden"),
        ("...", "Untitled"),
    ])
    func resolvesBaseName(input: String, expected: String) {
        var settings = NewFileSettings()
        settings.baseName = input
        #expect(settings.resolvedBaseName == expected)
    }

    @Test func limitsBaseNameLength() {
        var settings = NewFileSettings()
        settings.baseName = String(repeating: "a", count: 500)
        #expect(settings.resolvedBaseName.count == NewFileSettings.maxBaseNameLength)
    }
}
