import AppKit
import PDFKit
import Testing
@testable import OrbitKit

private typealias Fixture = DocxFixture

private func render(_ fixture: Fixture) throws -> PDFDocument {
    let data = try PDFRenderer(document: fixture.build()).render(title: "Test")
    return try #require(PDFDocument(data: data))
}

private func pageTexts(_ pdf: PDFDocument) -> [String] {
    (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
}

private func pageBreak() -> String {
    #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"#
}

/// A field as Word stores it, with a cached result.
private func field(_ instruction: String, cached: String) -> String {
    """
    <w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve">\(instruction)</w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>\(cached)</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>
    """
}

extension WordToPDFTests {
    @Suite struct PDFRendererTests {
        @Test func makesPagesOfTheSectionSize() throws {
            let body = Fixture.paragraph("Portrait", properties: Fixture.section(width: 11906, height: 16838))
                + Fixture.paragraph("Landscape") + Fixture.section(width: 16838, height: 11906)
            let pdf = try render(Fixture(body: body))

            #expect(pdf.pageCount == 2)
            // PDF stores coordinates with limited precision.
            func size(_ index: Int) -> CGSize { pdf.page(at: index)?.bounds(for: .mediaBox).size ?? .zero }
            #expect(abs(size(0).width - 595.3) < 0.01 && abs(size(0).height - 841.9) < 0.01)
            #expect(abs(size(1).width - 841.9) < 0.01 && abs(size(1).height - 595.3) < 0.01)
            #expect(pageTexts(pdf)[1].contains("Landscape"))
            #expect(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Test")
        }

        @Test func numbersPagesInHeaders() throws {
            var fixture = Fixture(body: Fixture.paragraph("One") + pageBreak() + Fixture.paragraph("Two") + pageBreak() + Fixture.paragraph("Three")
                + Fixture.section(extra: #"<w:headerReference w:type="default" r:id="rIdH1"/><w:pgNumType w:start="5" w:fmt="upperRoman"/>"#))
            fixture.headers["rIdH1"] = "<w:p>" + field("PAGE", cached: "1") + #"<w:r><w:t xml:space="preserve"> of </w:t></w:r>"# + field("NUMPAGES", cached: "1") + "</w:p>"
            let texts = pageTexts(try render(fixture))

            #expect(texts.count == 3)
            #expect(texts[0].contains("V of 3"))
            #expect(texts[2].contains("VII of 3"))
            #expect(texts[2].contains("Three"))
        }

        @Test func pageReferencesShowTheRealPage() throws {
            let body = #"<w:p><w:r><w:t xml:space="preserve">See page </w:t></w:r>"# + field(#"PAGEREF Target \h"#, cached: "99") + "</w:p>"
                + pageBreak() + pageBreak()
                + #"<w:p><w:bookmarkStart w:id="1" w:name="Target"/><w:r><w:t>Target</w:t></w:r></w:p>"#
            let texts = pageTexts(try render(Fixture(body: body)))

            #expect(texts.count == 3)
            #expect(texts[0].contains("See page 3"))
        }

        @Test func doesNotLeaveBlankPagesBetweenBreaks() throws {
            // A page break right before a section break that starts a new page anyway.
            let body = #"<w:p><w:r><w:t>One</w:t></w:r><w:r><w:br w:type="page"/></w:r></w:p>"#
                + "<w:p><w:pPr>\(Fixture.section())</w:pPr></w:p>"
                + Fixture.paragraph("Two") + Fixture.section()
            let texts = pageTexts(try render(Fixture(body: body)))

            #expect(texts.count == 2)
            #expect(texts[1].contains("Two"))
        }

        @Test func keepsHeadingsWithTheNextParagraph() throws {
            // Ten lines of exactly 20 pt fill the 200 pt page; the heading is the tenth.
            let line = #"<w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/>"#
            let lines = (1...9).map { Fixture.paragraph("Line \($0)", properties: line) }.joined()
            let body = lines
                + Fixture.paragraph("Heading", properties: line + "<w:keepNext/>")
                + Fixture.paragraph("Body", properties: line)
                + #"<w:sectPr><w:pgSz w:w="6000" w:h="5440"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="0" w:footer="0"/></w:sectPr>"#
            let texts = pageTexts(try render(Fixture(body: body)))

            #expect(texts.count == 2)
            #expect(!texts[0].contains("Heading"))
            #expect(texts[1].contains("Heading"))
            #expect(texts[0].contains("Line 9"))
        }

        /// Ten lines of exactly 20 pt fill a 200 pt page: lines before, then a paragraph with forced line breaks.
        private func linesThenParagraph(before: Int, lines: [String], styles: String? = nil) throws -> [String] {
            let line = #"<w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/>"#
            let filler = (1...before).map { Fixture.paragraph("Line \($0)", properties: line) }.joined()
            let runs = lines.map { #"<w:r><w:t>\#($0)</w:t></w:r>"# }.joined(separator: #"<w:r><w:br/></w:r>"#)
            let body = filler + "<w:p><w:pPr>\(line)</w:pPr>\(runs)</w:p>"
                + #"<w:sectPr><w:pgSz w:w="6000" w:h="5440"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="0" w:footer="0"/></w:sectPr>"#
            return pageTexts(try render(Fixture(body: body, styles: styles)))
        }

        @Test func movesAFirstLineThatWouldBeAloneAtTheBottom() throws {
            let texts = try linesThenParagraph(before: 9, lines: ["Alpha", "Beta", "Gamma"])
            #expect(texts.count == 2)
            #expect(!texts[0].contains("Alpha"))
            #expect(texts[1].contains("Alpha"))
        }

        @Test func movesALineWithALastLineThatWouldBeAloneAtTheTop() throws {
            let texts = try linesThenParagraph(before: 7, lines: ["One", "Two", "Three", "Four"])
            #expect(texts.count == 2)
            #expect(texts[0].contains("Two"))
            #expect(texts[1].contains("Three"))
            #expect(texts[1].contains("Four"))
        }

        @Test func leavesLonelyLinesWhenTheDocumentTurnsTheControlOff() throws {
            let defaults = #"<w:docDefaults><w:pPrDefault><w:pPr><w:widowControl w:val="0"/></w:pPr></w:pPrDefault></w:docDefaults>"#
            let texts = try linesThenParagraph(before: 9, lines: ["Alpha", "Beta", "Gamma"], styles: defaults)
            #expect(texts[0].contains("Alpha"))
            #expect(texts[1].contains("Beta"))
        }

        @Test func addsWebLinksAndBookmarkDestinations() throws {
            var fixture = Fixture(body: """
                <w:p><w:hyperlink r:id="rIdLink"><w:r><w:t>Website</w:t></w:r></w:hyperlink></w:p>
                <w:p><w:hyperlink w:anchor="Target"><w:r><w:t>Jump</w:t></w:r></w:hyperlink></w:p>
                """ + pageBreak() + #"<w:p><w:bookmarkStart w:id="1" w:name="Target"/><w:r><w:t>Target</w:t></w:r></w:p>"#)
            fixture.links["rIdLink"] = "https://example.com"
            let pdf = try render(fixture)
            let annotations = try #require(pdf.page(at: 0)?.annotations)

            #expect(annotations.contains { ($0.action as? PDFActionURL)?.url == URL(string: "https://example.com") || $0.url == URL(string: "https://example.com") })
            let jump = annotations.compactMap { ($0.action as? PDFActionGoTo)?.destination ?? $0.destination }.first
            #expect(jump?.page.map { pdf.index(for: $0) } == 1)
        }

        @Test func survivesPicturesTallerThanThePage() throws {
            var fixture = Fixture(body: """
                <w:p><w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="91440000"/>
                  <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImg1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
                </wp:inline></w:drawing></w:r></w:p>
                """ + Fixture.paragraph("After"))
            fixture.media["rIdImg1"] = Fixture.png
            let pdf = try render(fixture)
            #expect(pdf.pageCount >= 1)
            #expect(pageTexts(pdf).joined().contains("After"))
        }
    }

    @Suite struct WordToPDFConverterTests {
        private let folder: URL

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitKitTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }

        @Test func writesThePDFNextToTheDocumentWithoutReplacingFiles() throws {
            let source = try Fixture(body: Fixture.paragraph("Report")).write(to: folder, name: "Report.docx")
            defer { try? FileManager.default.removeItem(at: folder) }

            let first = try WordToPDFConverter.convert(source)
            let second = try WordToPDFConverter.convert(source)
            #expect(first == folder.appendingPathComponent("Report.pdf"))
            #expect(second == folder.appendingPathComponent("Report 2.pdf"))
            #expect(PDFDocument(url: first)?.string?.contains("Report") == true)
        }

        @Test func convertsTheDocumentsThatCanBeConverted() throws {
            let good = try Fixture(body: Fixture.paragraph("Fine")).write(to: folder, name: "Good.docx")
            let broken = folder.appendingPathComponent("Broken.docx")
            try Data("not a zip".utf8).write(to: broken)
            defer { try? FileManager.default.removeItem(at: folder) }

            #expect(try WordToPDFConverter.convert([broken, good]) == [folder.appendingPathComponent("Good.pdf")])
            #expect(throws: DocxError.notADocx) { try WordToPDFConverter.convert([broken]) }
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Broken.pdf").path))
        }

        @Test(arguments: [
            ("Report.docx", true), ("REPORT.DOCX", true), ("Template.dotx", true), ("Macro.docm", true),
            ("Old.doc", false), ("Notes.pdf", false), ("~$Report.docx", false), ("Folder", false),
        ])
        func recognizesWordDocuments(name: String, expected: Bool) {
            #expect(WordToPDFConverter.canConvert(URL(fileURLWithPath: "/tmp/\(name)")) == expected)
        }
    }

    // Serialized: all tests share one defaults suite, so they don't litter ~/Library/Preferences.
    @Suite(.serialized) struct WordToPDFMenuTests {
        private let store: SettingsStore
        private let folder = URL(fileURLWithPath: "/tmp/Orbit")

        init() {
            let defaults = UserDefaults(suiteName: "OrbitKitTests.WordToPDF")!
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("module.") {
                defaults.removeObject(forKey: key)
            }
            store = SettingsStore(defaults: defaults)
        }

        private func items(_ names: [String]) -> [FinderMenuItem] {
            FinderMenu.items(store: store, selection: names.map { folder.appendingPathComponent($0) }, modules: [WordToPDFModule()])
        }

        @Test func offersConversionForWordDocuments() {
            let items = items(["A.docx", "B.DOCX"])
            #expect(items.map { String(localized: $0.title) } == ["Convert to PDF"])
            #expect(items.first?.icon == .fileType("pdf"))
            #expect(items.first?.isLongRunning == true)
        }

        @Test func staysOutOfOtherMenus() {
            #expect(items([]).isEmpty)
            #expect(items(["A.docx", "Photo.jpg"]).isEmpty)
            #expect(items(["Folder"]).isEmpty)
        }

        @Test func disabledModuleAddsNothing() {
            store.setEnabled(false, for: WordToPDFModule())
            #expect(items(["A.docx"]).isEmpty)
        }

        @Test func comesAfterCopyPath() {
            #expect(ModuleRegistry.all.map(\.id) == [NewFileModule.id, CopyPathModule.id, WordToPDFModule.id, PDFToolsModule.id])
        }
    }
}
