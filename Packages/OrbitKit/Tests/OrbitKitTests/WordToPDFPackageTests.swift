import Foundation
import Testing
@testable import OrbitKit

@Suite struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        let text = String(repeating: "Привет, Word! ", count: 200)
        var zip = ZipWriter()
        zip.add("word/document.xml", text)
        zip.add("plain.txt", "stored", deflate: false)
        let archive = try ZipArchive(data: zip.data())

        #expect(try archive.contents(of: "word/document.xml") == Data(text.utf8))
        #expect(try archive.contents(of: "plain.txt") == Data("stored".utf8))
    }

    @Test func findsEntriesIgnoringCaseAndLeadingSlash() throws {
        var zip = ZipWriter()
        zip.add("word/Document.xml", "x")
        let archive = try ZipArchive(data: zip.data())

        #expect(archive.contains("/word/document.xml"))
        #expect(try archive.contents(of: "WORD/document.xml") == Data("x".utf8))
        #expect(try archive.contents(of: "word/missing.xml") == nil)
    }

    @Test func handlesEmptyEntries() throws {
        var zip = ZipWriter()
        zip.add("empty.xml", "")
        #expect(try ZipArchive(data: zip.data()).contents(of: "empty.xml") == Data())
    }

    @Test func rejectsDataThatIsNotAnArchive() {
        #expect(throws: ZipArchive.Failure.notAnArchive) {
            try ZipArchive(data: Data("This is an old binary .doc".utf8))
        }
        #expect(throws: ZipArchive.Failure.notAnArchive) {
            try ZipArchive(data: Data())
        }
    }

    @Test func reportsDamagedEntriesInsteadOfCrashing() throws {
        var zip = ZipWriter()
        zip.add("word/document.xml", String(repeating: "a", count: 1000))
        // The directory is intact, but the entry it points to isn't.
        var damaged = zip.data()
        damaged[0] = 0
        let archive = try ZipArchive(data: damaged)
        #expect(throws: ZipArchive.Failure.self) { try archive.contents(of: "word/document.xml") }
    }

    @Test func reportsDirectoriesPointingOutsideTheArchive() throws {
        var zip = ZipWriter()
        zip.add("a.txt", "a")
        var damaged = zip.data()
        // The local header offset of the only directory entry: the last field before its name.
        let directoryStart = damaged.count - 22 - (46 + 5)
        damaged.replaceSubrange((directoryStart + 42)..<(directoryStart + 46), with: [0xFF, 0xFF, 0x00, 0x00])
        let archive = try ZipArchive(data: damaged)
        #expect(throws: ZipArchive.Failure.self) { try archive.contents(of: "a.txt") }
    }

    @Test func readsSlicesOfLargerData() throws {
        var zip = ZipWriter()
        zip.add("a.txt", "slice")
        let padded = Data([1, 2, 3]) + zip.data()
        #expect(try ZipArchive(data: padded.dropFirst(3)).contents(of: "a.txt") == Data("slice".utf8))
    }
}

@Suite struct MarkupParserTests {
    @Test func matchesElementsByNamespaceNotPrefix() throws {
        let xml = """
            <doc:document xmlns:doc="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                          xmlns:rel="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <doc:body><doc:p><doc:pPr><doc:jc doc:val="center"/></doc:pPr><doc:hyperlink rel:id="rId5"/></doc:p></doc:body>
            </doc:document>
            """
        let root = try MarkupParser.parse(Data(xml.utf8))
        let paragraph = try #require(root.child("body")?.child("p"))

        #expect(paragraph.child("pPr")?.value(of: "jc") == "center")
        #expect(paragraph.child("hyperlink")?.attribute("id", in: .r) == "rId5")
    }

    @Test func understandsStrictOOXML() throws {
        let xml = #"<w:p xmlns:w="http://purl.oclc.org/ooxml/wordprocessingml/main"><w:r/></w:p>"#
        let root = try MarkupParser.parse(Data(xml.utf8))
        #expect(root.is("p"))
        #expect(root.child("r") != nil)
    }

    @Test func keepsSpacesInText() throws {
        let xml = #"<w:t xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xml:space="preserve">  two  spaces &amp; more </w:t>"#
        #expect(try MarkupParser.parse(Data(xml.utf8)).text == "  two  spaces & more ")
    }

    @Test func readsOnOffProperties() throws {
        let xml = """
            <w:rPr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:b/><w:i w:val="0"/><w:caps w:val="false"/><w:strike w:val="true"/>
            </w:rPr>
            """
        let properties = try MarkupParser.parse(Data(xml.utf8))
        #expect(properties.flag("b") == true)
        #expect(properties.flag("i") == false)
        #expect(properties.flag("caps") == false)
        #expect(properties.flag("strike") == true)
        #expect(properties.flag("u") == nil)
    }

    @Test func rejectsMalformedXML() {
        #expect(throws: MarkupParser.Failure.self) {
            try MarkupParser.parse(Data("<w:p><unclosed>".utf8))
        }
    }
}

@Suite struct DocxPackageTests {
    @Test(arguments: [
        ("media/image1.png", "word", "word/media/image1.png"),
        ("../customXml/item1.xml", "word", "customXml/item1.xml"),
        ("/word/styles.xml", "word", "word/styles.xml"),
        ("./theme/theme1.xml", "word", "word/theme/theme1.xml"),
        ("media/Image%201.png", "word", "word/media/Image 1.png"),
    ])
    func resolvesRelationshipTargets(target: String, directory: String, expected: String) {
        #expect(DocxPackage.resolve(target, from: directory) == expected)
    }

    @Test func findsTheMainDocumentThroughRelationships() throws {
        let package = try DocxPackage(data: DocxFixture(body: DocxFixture.paragraph("Hi")).data())
        #expect(try package.mainDocumentPath() == "word/document.xml")
    }

    @Test func reportsFilesThatAreNotWordDocuments() {
        #expect(throws: DocxError.notADocx) {
            try DocxPackage(data: Data("{\\rtf1 not a docx}".utf8))
        }
        var zip = ZipWriter()
        zip.add("hello.txt", "A ZIP, but not a Word document")
        #expect(throws: DocxError.notADocx) {
            try DocxPackage(data: zip.data()).mainDocumentPath()
        }
    }
}
