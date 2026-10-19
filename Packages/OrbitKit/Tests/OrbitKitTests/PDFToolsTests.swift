import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import OrbitKit

@Suite final class PDFToolsTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes a PDF whose pages are as wide as `widths`, so tests can tell pages apart by size.
    @discardableResult
    private func makePDF(_ name: String, widths: [CGFloat], password: String? = nil) throws -> URL {
        let url = folder.appendingPathComponent(name)
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        let context = try #require(CGContext(url as CFURL, mediaBox: nil, info as CFDictionary))
        for width in widths {
            var box = CGRect(x: 0, y: 0, width: width, height: 100)
            context.beginPage(mediaBox: &box)
            context.fill(box.insetBy(dx: 10, dy: 10))
            context.endPage()
        }
        context.closePDF()
        return url
    }

    private func pageWidths(_ url: URL) throws -> [CGFloat] {
        let document = try #require(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .mediaBox).width }
    }

    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Merge

    @Test func mergeOrdersByName() throws {
        let ten = try makePDF("10.pdf", widths: [300])
        let two = try makePDF("2.pdf", widths: [200, 201])
        let result = try PDFTools.merge([ten, two])
        #expect(result == folder.appendingPathComponent("2 (merged).pdf"))
        #expect(try pageWidths(result) == [200, 201, 300])
    }

    @Test func mergeTakesNextFreeName() throws {
        let sources = [try makePDF("A.pdf", widths: [100]), try makePDF("B.pdf", widths: [110])]
        try Data("taken".utf8).write(to: folder.appendingPathComponent("A (merged).pdf"))
        let result = try PDFTools.merge(sources)
        #expect(result.lastPathComponent == "A (merged) 2.pdf")
        #expect(try String(contentsOf: folder.appendingPathComponent("A (merged).pdf"), encoding: .utf8) == "taken")
    }

    @Test func mergeNeedsTwoDocuments() throws {
        #expect(throws: PDFTools.Failure.tooFewDocuments) {
            try PDFTools.merge([try self.makePDF("A.pdf", widths: [100])])
        }
    }

    @Test func mergeWritesNothingIfDocumentIsLocked() throws {
        let sources = [try makePDF("A.pdf", widths: [100]), try makePDF("B.pdf", widths: [110], password: "secret")]
        #expect(throws: PDFTools.Failure.locked) { try PDFTools.merge(sources) }
        #expect(try contents(of: folder) == ["A.pdf", "B.pdf"])
    }

    @Test func mergeWritesNothingIfDocumentIsUnreadable() throws {
        let broken = folder.appendingPathComponent("B.pdf")
        try Data("not a PDF".utf8).write(to: broken)
        let sources = [try makePDF("A.pdf", widths: [100]), broken]
        #expect(throws: PDFTools.Failure.unreadable) { try PDFTools.merge(sources) }
        #expect(try contents(of: folder) == ["A.pdf", "B.pdf"])
    }

    // MARK: Split

    @Test func splitSavesPagesInNewFolder() throws {
        let source = try makePDF("Report.pdf", widths: [100, 110, 120])
        let result = try PDFTools.split(source)
        #expect(result.lastPathComponent == "Report Pages")
        let names = try contents(of: result)
        #expect(names == ["Report 1.pdf", "Report 2.pdf", "Report 3.pdf"])
        #expect(try names.map { try pageWidths(result.appendingPathComponent($0)) } == [[100], [110], [120]])
    }

    @Test func splitNeverWritesIntoExistingFolder() throws {
        let source = try makePDF("Report.pdf", widths: [100, 110])
        let existing = folder.appendingPathComponent("Report Pages")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        try Data("mine".utf8).write(to: existing.appendingPathComponent("Report 1.pdf"))

        let result = try PDFTools.split(source)
        #expect(result.lastPathComponent == "Report Pages 2")
        #expect(try contents(of: result) == ["Report 1.pdf", "Report 2.pdf"])
        #expect(try String(contentsOf: existing.appendingPathComponent("Report 1.pdf"), encoding: .utf8) == "mine")
    }

    @Test func splitRejectsSinglePage() throws {
        let source = try makePDF("Report.pdf", widths: [100])
        #expect(throws: PDFTools.Failure.singlePage) { try PDFTools.split(source) }
        #expect(try contents(of: folder) == ["Report.pdf"])
    }

    @Test func splitRejectsLockedDocument() throws {
        let source = try makePDF("Report.pdf", widths: [100, 110], password: "secret")
        #expect(throws: PDFTools.Failure.locked) { try PDFTools.split(source) }
        #expect(try contents(of: folder) == ["Report.pdf"])
    }

    @Test(arguments: [("Report.pdf", true), ("REPORT.PDF", true), ("Report.pdf.zip", false), ("Report", false), ("Report.docx", false)])
    func recognizesPDFs(name: String, expected: Bool) {
        #expect(PDFTools.isPDF(URL(fileURLWithPath: "/tmp/\(name)")) == expected)
    }
}

// Serialized: all tests share one defaults suite, so they don't litter ~/Library/Preferences.
@Suite(.serialized) struct PDFToolsMenuTests {
    private let store: SettingsStore
    private let folder = URL(fileURLWithPath: "/tmp/Orbit")

    init() {
        let defaults = UserDefaults(suiteName: "OrbitKitTests.PDFTools")!
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("module.") {
            defaults.removeObject(forKey: key)
        }
        store = SettingsStore(defaults: defaults)
    }

    private func titles(_ names: [String]) -> [String] {
        FinderMenu.items(store: store, selection: names.map { folder.appendingPathComponent($0) }, modules: [PDFToolsModule()])
            .map { String(localized: $0.title) }
    }

    @Test func offersSplitForOnePDF() {
        #expect(titles(["A.pdf"]) == ["Split PDF"])
    }

    @Test func offersMergeForSeveralPDFs() {
        #expect(titles(["A.pdf", "B.PDF"]) == ["Merge PDFs"])
        #expect(titles(["A.pdf", "B.pdf", "C.pdf"]) == ["Merge PDFs"])
    }

    @Test(arguments: [["A.pdf"], ["A.pdf", "B.pdf"]])
    func actionsRunApartFromQuickOnes(names: [String]) {
        let items = FinderMenu.items(store: store, selection: names.map { folder.appendingPathComponent($0) }, modules: [PDFToolsModule()])
        #expect(items.count == 1)
        #expect(items.first?.isLongRunning == true)
    }

    @Test func staysOutOfOtherMenus() {
        #expect(titles([]).isEmpty)
        #expect(titles(["A.pdf", "Photo.jpg"]).isEmpty)
        #expect(titles(["Folder"]).isEmpty)
    }

    @Test func disabledModuleAddsNothing() {
        store.setEnabled(false, for: PDFToolsModule())
        #expect(titles(["A.pdf"]).isEmpty)
        #expect(titles(["A.pdf", "B.pdf"]).isEmpty)
    }

    @Test func choosingPagesOpensOrbit() throws {
        var settings = store.pdfTools
        settings.mergeMode = .choosePages
        settings.splitMode = .choosePages
        store.pdfTools = settings

        #expect(titles(["A.pdf"]) == ["Split PDF…"])
        #expect(titles(["A.pdf", "B.pdf"]) == ["Merge PDFs…"])

        let selection = ["B.pdf", "A.pdf"].map { folder.appendingPathComponent($0) }
        let items = FinderMenu.items(store: store, selection: selection, modules: [PDFToolsModule()])
        // Opening a window is quick: it shouldn't wait behind a long merge.
        #expect(items.first?.isLongRunning == false)
        guard case .action(let action) = try #require(items.first).kind else {
            Issue.record("Merge should be an action")
            return
        }
        #expect(try action(FinderContext(targetFolder: folder, selectedItems: selection)) == .openInOrbit(selection))
    }

    @Test func modesAreIndependent() {
        var settings = store.pdfTools
        settings.splitMode = .choosePages
        store.pdfTools = settings

        #expect(titles(["A.pdf"]) == ["Split PDF…"])
        #expect(titles(["A.pdf", "B.pdf"]) == ["Merge PDFs"])
    }
}

@Suite struct PDFToolsSettingsTests {
    @Test func defaultsToImmediateMode() {
        #expect(PDFToolsSettings().mergeMode == .immediate)
        #expect(PDFToolsSettings().splitMode == .immediate)
    }

    @Test func decodesSettingsWithMissingFields() throws {
        let settings = try JSONDecoder().decode(PDFToolsSettings.self, from: Data(#"{"splitMode": "choosePages"}"#.utf8))
        #expect(settings.mergeMode == .immediate)
        #expect(settings.splitMode == .choosePages)
    }

    @Test func unknownModeFallsBackToDefault() throws {
        let json = #"{"mergeMode": "magic", "splitMode": "choosePages"}"#
        let settings = try JSONDecoder().decode(PDFToolsSettings.self, from: Data(json.utf8))
        #expect(settings.mergeMode == .immediate)
        #expect(settings.splitMode == .choosePages)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = PDFToolsSettings()
        settings.mergeMode = .choosePages
        let decoded = try JSONDecoder().decode(PDFToolsSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}

@Suite struct PDFToolsRequestTests {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/Orbit/\(name)")
    }

    @Test func onePDFIsSplit() {
        #expect(PDFToolsRequest(urls: [url("A.pdf")]) == .split(url("A.pdf")))
    }

    @Test func severalPDFsAreMergedInNameOrder() {
        #expect(PDFToolsRequest(urls: [url("10.pdf"), url("2.PDF")]) == .merge([url("2.PDF"), url("10.pdf")]))
    }

    @Test func ignoresOtherFilesAndDuplicates() {
        let urls = [url("A.pdf"), url("Photo.jpg"), url("A.pdf"), URL(string: "https://example.com/B.pdf")!]
        #expect(PDFToolsRequest(urls: urls) == .split(url("A.pdf")))
    }

    @Test func nothingToDoWithoutPDFs() {
        #expect(PDFToolsRequest(urls: []) == nil)
        #expect(PDFToolsRequest(urls: [url("Photo.jpg")]) == nil)
    }
}
