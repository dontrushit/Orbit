import CoreGraphics
import Foundation
import Testing
@testable import OrbitKit

/// Choosing pages: inspecting documents, merging chosen pages, thumbnails.
@Suite final class PDFPagesTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func makePDF(_ name: String, widths: [CGFloat], password: String? = nil) throws -> URL {
        try PDFFixture.write(to: folder.appendingPathComponent(name), widths: widths, password: password)
    }

    private func page(_ document: URL, _ index: Int) -> PDFTools.PageReference {
        PDFTools.PageReference(document: document, index: index)
    }

    // MARK: Inspecting

    @Test func inspectsPageCount() throws {
        let url = try makePDF("A.pdf", widths: [100, 110, 120])
        #expect(try PDFDocumentInfo(contentsOf: url).pageCount == 3)
    }

    @Test func reportsLockedUnreadableAndMissingFiles() throws {
        let locked = try makePDF("Locked.pdf", widths: [100], password: "secret")
        #expect(throws: PDFTools.Failure.locked) { try PDFDocumentInfo(contentsOf: locked) }

        let broken = folder.appendingPathComponent("Broken.pdf")
        try Data("not a PDF".utf8).write(to: broken)
        #expect(throws: PDFTools.Failure.unreadable) { try PDFDocumentInfo(contentsOf: broken) }

        #expect(throws: PDFTools.Failure.missing) { try PDFDocumentInfo(contentsOf: self.folder.appendingPathComponent("Gone.pdf")) }
    }

    @Test func noticesChangedAndDeletedFiles() throws {
        let url = try makePDF("A.pdf", widths: [100, 110])
        let info = try PDFDocumentInfo(contentsOf: url)
        try info.verifyUnchanged()

        try makePDF("A.pdf", widths: [100, 110, 120])
        #expect(throws: PDFTools.Failure.modified) { try info.verifyUnchanged() }

        try FileManager.default.removeItem(at: url)
        #expect(throws: PDFTools.Failure.missing) { try info.verifyUnchanged() }
    }

    // MARK: Merging chosen pages

    @Test func mergesPagesInGivenOrder() throws {
        let a = try makePDF("A.pdf", widths: [100, 110, 120])
        let b = try makePDF("B.pdf", widths: [200, 210])
        let result = try PDFTools.merge(pages: [page(b, 1), page(a, 2), page(a, 0)])
        #expect(try PDFFixture.pageWidths(result) == [210, 120, 100])
    }

    @Test func namesResultAfterDocumentOfFirstPage() throws {
        let sub = folder.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        let a = try makePDF("A.pdf", widths: [100])
        let b = try PDFFixture.write(to: sub.appendingPathComponent("B.pdf"), widths: [200])

        let result = try PDFTools.merge(pages: [page(b, 0), page(a, 0)])
        #expect(result == sub.appendingPathComponent("B (merged).pdf"))
        #expect(try PDFTools.merge(pages: [page(b, 0), page(a, 0)]).lastPathComponent == "B (merged) 2.pdf")
    }

    @Test func refusesEmptyChoiceAndPagesThatAreGone() throws {
        #expect(throws: PDFTools.Failure.noPages) { try PDFTools.merge(pages: []) }

        let a = try makePDF("A.pdf", widths: [100])
        #expect(throws: PDFTools.Failure.modified) { try PDFTools.merge(pages: [self.page(a, 0), self.page(a, 5)]) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["A.pdf"])
    }

    // MARK: Thumbnails

    @Test func rendersThumbnailWithinMaxSize() throws {
        let url = try makePDF("A.pdf", widths: [200])
        let document = try #require(CGPDFDocument(url as CFURL))
        let page = try #require(document.page(at: 1))
        let image = try #require(PDFThumbnailLoader.render(page, maxPixelSize: 100))
        #expect(image.width == 100)
        #expect(image.height == 50)
    }

    @Test func scalesUpSmallPages() throws {
        let url = try makePDF("A.pdf", widths: [50])
        let document = try #require(CGPDFDocument(url as CFURL))
        let page = try #require(document.page(at: 1))
        let image = try #require(PDFThumbnailLoader.render(page, maxPixelSize: 200))
        #expect(image.width == 100)
        #expect(image.height == 200)
    }
}

@Suite struct PageArrangementTests {
    private let a = URL(fileURLWithPath: "/tmp/A.pdf")
    private let b = URL(fileURLWithPath: "/tmp/B.pdf")

    private func arrangement() -> PageArrangement {
        PageArrangement(pages: [(a, 3), (b, 2)].flatMap { url, count in
            (0..<count).map { PDFTools.PageReference(document: url, index: $0) }
        })
    }

    private func names(_ pages: [PDFTools.PageReference]) -> [String] {
        pages.map { "\($0.document.deletingPathExtension().lastPathComponent)\($0.index + 1)" }
    }

    @Test func startsWithEveryPageIncluded() {
        let arrangement = arrangement()
        #expect(names(arrangement.includedPages) == ["A1", "A2", "A3", "B1", "B2"])
        #expect(arrangement.includedCount == 5)
    }

    @Test func togglesPages() {
        var arrangement = arrangement()
        arrangement.toggle(1)
        arrangement.toggle(3)
        #expect(names(arrangement.includedPages) == ["A1", "A3", "B2"])
        arrangement.toggle(1)
        #expect(names(arrangement.includedPages) == ["A1", "A2", "A3", "B2"])
        arrangement.setIncluded(false, for: 0)
        #expect(arrangement.includedCount == 3)
    }

    @Test func includesOrExcludesAll() {
        var arrangement = arrangement()
        arrangement.setAllIncluded(false)
        #expect(arrangement.includedPages.isEmpty)
        arrangement.setAllIncluded(true)
        #expect(arrangement.includedCount == 5)
    }

    @Test func movesForwardAndBackward() {
        var arrangement = arrangement()
        arrangement.move(0, to: 3) // A1 onto B1: B1 shifts back
        #expect(names(arrangement.includedPages) == ["A2", "A3", "B1", "A1", "B2"])
        arrangement.move(4, to: 1) // B2 onto A2: A2 shifts forward
        #expect(names(arrangement.includedPages) == ["B2", "A2", "A3", "B1", "A1"])
    }

    @Test func movingKeepsExclusion() {
        var arrangement = arrangement()
        arrangement.toggle(4)
        arrangement.move(4, to: 0)
        #expect(arrangement.items.first?.isIncluded == false)
        #expect(names(arrangement.includedPages) == ["A1", "A2", "A3", "B1"])
    }

    @Test func ignoresUnknownIDs() {
        var arrangement = arrangement()
        arrangement.move(0, to: 42)
        arrangement.toggle(42)
        #expect(arrangement == self.arrangement())
    }
}
