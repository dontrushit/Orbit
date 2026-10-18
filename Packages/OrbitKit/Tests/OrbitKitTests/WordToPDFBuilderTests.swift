import AppKit
import Testing
@testable import OrbitKit

private typealias Fixture = DocxFixture

/// Paragraphs of the built text, each with its attributes at the first character.
private func paragraphs(_ text: NSAttributedString) -> [(text: String, attributes: [NSAttributedString.Key: Any])] {
    let string = text.string as NSString
    var result: [(String, [NSAttributedString.Key: Any])] = []
    var index = 0
    while index < string.length {
        let range = string.paragraphRange(for: NSRange(location: index, length: 0))
        result.append((string.substring(with: range), text.attributes(at: range.location, effectiveRange: nil)))
        index = NSMaxRange(range)
    }
    return result
}

private func style(_ attributes: [NSAttributedString.Key: Any]) -> NSParagraphStyle? {
    attributes[.paragraphStyle] as? NSParagraphStyle
}

extension WordToPDFTests {
    @Suite struct DocumentBuilderTests {
        @Test func translatesParagraphFormatting() throws {
            let document = try Fixture(body: Fixture.paragraph(
                "Centered",
                properties: #"<w:jc w:val="center"/><w:ind w:left="720" w:right="360" w:firstLine="360"/><w:spacing w:before="240" w:after="120"/>"#
            )).build()
            let paragraph = try #require(style(paragraphs(document.body)[0].attributes))

            #expect(paragraph.alignment == .center)
            #expect(paragraph.headIndent == 36)
            #expect(paragraph.firstLineHeadIndent == 54)
            #expect(paragraph.tailIndent == -18)
            #expect(paragraph.paragraphSpacingBefore == 12)
            #expect(paragraph.paragraphSpacing == 6)
        }

        @Test func usesWordsSingleLineHeight() throws {
            let document = try Fixture(body: #"<w:p><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="28"/></w:rPr><w:t>Text</w:t></w:r></w:p>"#).build()
            let paragraph = try #require(style(paragraphs(document.body)[0].attributes))
            let font = NSFont(name: "Times New Roman", size: 14)! as CTFont
            let expected = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            #expect(abs(paragraph.minimumLineHeight - expected) < 0.01)
        }

        @Test func translatesRunFormatting() throws {
            let document = try Fixture(body: """
                <w:p><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:b/><w:i/><w:sz w:val="32"/><w:color w:val="FF0000"/><w:u w:val="single"/></w:rPr><w:t>Bold</w:t></w:r></w:p>
                """).build()
            let attributes = document.body.attributes(at: 0, effectiveRange: nil)
            let font = try #require(attributes[.font] as? NSFont)

            #expect(font.familyName == "Arial")
            #expect(font.pointSize == 16)
            #expect(CTFontGetSymbolicTraits(font as CTFont).contains([.traitBold, .traitItalic]))
            #expect((attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.redComponent == 1)
            #expect(attributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
            // Word doesn't kern unless the document asks for it.
            #expect(attributes[.kern] as? CGFloat == 0)
        }

        @Test func appliesCapsAndSkipsHiddenText() throws {
            let document = try Fixture(body: """
                <w:p><w:r><w:rPr><w:caps/></w:rPr><w:t>loud</w:t></w:r><w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r></w:p>
                """).build()
            #expect(document.body.string == "LOUD\n")
        }

        @Test func readsEverySectionOfTheDocument() throws {
            // Section properties sit in the last paragraph of each section and in the body.
            let body = Fixture.paragraph("Portrait", properties: Fixture.section(width: 11906, height: 16838))
                + Fixture.paragraph("Landscape")
                + Fixture.section(width: 16838, height: 11906)
            let document = try Fixture(body: body).build()

            #expect(document.sections.count == 2)
            #expect(document.sections[0].page.size == CGSize(width: 595.3, height: 841.9))
            #expect(document.sections[1].page.size == CGSize(width: 841.9, height: 595.3))
            #expect(document.sections[1].startIndex == ("Portrait\n" as NSString).length)
            #expect(document.body.string.contains("\u{0C}"), "A new section starts on a new page")
        }

        @Test func pageBreakRunsBecomeParagraphsOfTheirOwn() throws {
            let body = """
                <w:p><w:r><w:t>Before</w:t></w:r><w:r><w:br w:type="page"/></w:r></w:p>
                <w:p><w:r><w:br w:type="page"/></w:r><w:r><w:t>After</w:t></w:r></w:p>
                """
            let texts = paragraphs(try Fixture(body: body).build().body).map(\.text)
            #expect(texts == ["Before\n", "\u{0C}\n", "\u{0C}\n", "After\n"])
        }

        @Test func emptyParagraphWithAPageBreakStaysBeforeTheBreak() throws {
            let body = Fixture.paragraph("Text") + #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# + Fixture.paragraph("Next")
            let texts = paragraphs(try Fixture(body: body).build().body).map(\.text)
            #expect(texts == ["Text\n", "\n", "\u{0C}\n", "Next\n"])
        }

        @Test func numbersListParagraphs() throws {
            let numbering = """
                <w:abstractNum w:abstractNumId="0">
                  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1)"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
                </w:abstractNum>
                <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
                """
            let item = #"<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>"#
            let document = try Fixture(body: Fixture.paragraph("First", properties: item) + Fixture.paragraph("Second", properties: item), numbering: numbering).build()
            let list = paragraphs(document.body)

            #expect(list.map(\.text) == ["1)\tFirst\n", "2)\tSecond\n"])
            let paragraph = try #require(style(list[0].attributes))
            #expect(paragraph.headIndent == 36)
            #expect(paragraph.firstLineHeadIndent == 18)
            #expect(paragraph.tabStops.contains { $0.location == 36 }, "The hanging indent is a tab stop")
        }

        @Test func buildsTablesFromCells() throws {
            let table = """
                <w:tbl>
                  <w:tblPr><w:tblBorders><w:insideV w:val="single" w:sz="8"/></w:tblBorders></w:tblPr>
                  <w:tblGrid><w:gridCol w:w="2880"/><w:gridCol w:w="2880"/></w:tblGrid>
                  <w:tr><w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc></w:tr>
                  <w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:shd w:val="clear" w:fill="FFFF00"/></w:tcPr><w:p><w:r><w:t>Wide</w:t></w:r></w:p></w:tc></w:tr>
                </w:tbl>
                """
            let document = try Fixture(body: table + Fixture.paragraph("After")).build()
            let list = paragraphs(document.body)
            #expect(list.map(\.text) == ["A1\n", "B1\n", "Wide\n", "After\n"])

            let first = try #require(style(list[0].attributes)?.textBlocks.first as? NSTextTableBlock)
            let second = try #require(style(list[1].attributes)?.textBlocks.first as? NSTextTableBlock)
            let wide = try #require(style(list[2].attributes)?.textBlocks.first as? NSTextTableBlock)
            #expect(first.table === wide.table)
            #expect(second.startingColumn == 1)
            #expect(first.width(for: .border, edge: .maxX) == 1, "Inside border between the cells")
            #expect(first.width(for: .border, edge: .minX) == 0, "No outer border was set")
            #expect(wide.columnSpan == 2)
            #expect(wide.backgroundColor?.usingColorSpace(.sRGB)?.blueComponent == 0)
            // Cell content is the column width without Word's default margins of 5.4 pt.
            #expect(abs(first.value(for: .width) - (144 - 10.8 - 0.5)) < 0.01)
            #expect(style(list[3].attributes)?.textBlocks.isEmpty == true)
        }

        @Test func mergesCellsVertically() throws {
            let table = """
                <w:tbl><w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="2000"/></w:tblGrid>
                  <w:tr><w:tc><w:tcPr><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>Tall</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc></w:tr>
                  <w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc><w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc></w:tr>
                </w:tbl>
                """
            let list = paragraphs(try Fixture(body: table + "<w:p/>").build().body)
            #expect(list.map(\.text) == ["Tall\n", "1\n", "2\n", "\n"])
            let tall = try #require(style(list[0].attributes)?.textBlocks.first as? NSTextTableBlock)
            #expect(tall.rowSpan == 2)
        }

        @Test func placesPicturesAsAttachments() throws {
            var fixture = Fixture(body: """
                <w:p><w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="457200"/>
                  <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImg1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
                </wp:inline></w:drawing></w:r></w:p>
                """)
            fixture.media["rIdImg1"] = Fixture.png
            let document = try fixture.build()
            let drawing = try #require(document.body.attribute(.docxDrawing, at: 0, effectiveRange: nil) as? Drawing)

            #expect(drawing.size == CGSize(width: 72, height: 36))
            guard case .image(let image) = drawing.content else {
                Issue.record("The picture should be decoded")
                return
            }
            #expect(image.width == 2)
        }

        @Test func scalesPicturesDownToTheTextWidth() throws {
            var fixture = Fixture(body: """
                <w:p><w:r><w:drawing><wp:inline><wp:extent cx="12700000" cy="6350000"/>
                  <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImg1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
                </wp:inline></w:drawing></w:r></w:p>
                """ + Fixture.section())
            fixture.media["rIdImg1"] = Fixture.png
            let drawing = try #require(try fixture.build().body.attribute(.docxDrawing, at: 0, effectiveRange: nil) as? Drawing)
            let textWidth = (11906 - 2 * 1440) / 20.0
            #expect(abs(drawing.size.width - textWidth) < 0.01)
            #expect(abs(drawing.size.height - textWidth / 2) < 0.01)
        }

        @Test func keepsTheSpaceOfPicturesMacOSCantDecode() throws {
            var fixture = Fixture(body: """
                <w:p><w:r><w:drawing><wp:inline><wp:extent cx="914400" cy="914400"/>
                  <a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rIdImg1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
                </wp:inline></w:drawing></w:r></w:p>
                """)
            fixture.media["rIdImg1"] = Data("not an image".utf8)
            let drawing = try #require(try fixture.build().body.attribute(.docxDrawing, at: 0, effectiveRange: nil) as? Drawing)
            #expect(drawing.isUnsupported)
            #expect(drawing.size == CGSize(width: 72, height: 72))
        }

        @Test func linksToWebPagesAndBookmarks() throws {
            var fixture = Fixture(body: """
                <w:p><w:hyperlink r:id="rIdLink"><w:r><w:t>web</w:t></w:r></w:hyperlink><w:hyperlink w:anchor="Target"><w:r><w:t>inside</w:t></w:r></w:hyperlink></w:p>
                <w:p><w:bookmarkStart w:id="0" w:name="Target"/><w:r><w:t>Here</w:t></w:r></w:p>
                """)
            fixture.links["rIdLink"] = "https://example.com"
            let text = try fixture.build().body

            #expect(text.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
            #expect(text.attribute(.docxInternalLink, at: 3, effectiveRange: nil) as? String == "Target")
            let here = (text.string as NSString).range(of: "Here").location
            #expect(text.attribute(.docxBookmarks, at: here, effectiveRange: nil) as? [String] == ["Target"])
        }

        @Test func showsCachedFieldResultsInTheBody() throws {
            let field = """
                <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>DATE \\@ "d.M.yyyy"</w:instrText></w:r>
                <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1.1.2026</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
                """
            #expect(try Fixture(body: field).build().body.string == "1.1.2026\n")
        }

        @Test func headerPageNumbersArePlaceholders() throws {
            var fixture = Fixture(body: Fixture.paragraph("Body") + Fixture.section(extra: #"<w:headerReference w:type="default" r:id="rIdH1"/>"#))
            fixture.headers["rIdH1"] = """
                <w:p><w:r><w:t xml:space="preserve">Page </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>PAGE</w:instrText></w:r>
                <w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>7</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
                """
            let header = try #require(try fixture.build().sections[0].headers.standard)

            #expect(header.string == "Page 0\n", "The cached 7 is dropped for a live value")
            guard case .page = header.attribute(.docxField, at: 5, effectiveRange: nil) as? FieldPlaceholder else {
                Issue.record("The page number should be a placeholder")
                return
            }
        }

        @Test func tableOfContentsEntriesDontGetTheHyperlinkStyle() throws {
            let styles = #"<w:style w:type="character" w:styleId="af6"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0000FF"/><w:u w:val="single"/></w:rPr></w:style>"#
            let body = """
                <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>TOC \\o "1-3" \\h</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r>
                <w:hyperlink w:anchor="_Toc1"><w:r><w:rPr><w:rStyle w:val="af6"/></w:rPr><w:t>Entry</w:t></w:r></w:hyperlink></w:p>
                <w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
                <w:p><w:r><w:rPr><w:rStyle w:val="af6"/></w:rPr><w:t>Link</w:t></w:r></w:p>
                """
            let text = try Fixture(body: body, styles: styles).build().body
            let entry = text.attributes(at: 0, effectiveRange: nil)
            let link = text.attributes(at: (text.string as NSString).range(of: "Link").location, effectiveRange: nil)
            #expect(entry[.underlineStyle] == nil)
            #expect(link[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        }

        @Test func writesOutLinearEquations() throws {
            let math = """
                <w:p><m:oMath><m:f><m:num><m:r><m:t>a+b</m:t></m:r></m:num><m:den><m:r><m:t>2</m:t></m:r></m:den></m:f>
                <m:sSup><m:e><m:r><m:t>x</m:t></m:r></m:e><m:sup><m:r><m:t>2</m:t></m:r></m:sup></m:sSup></m:oMath></w:p>
                """
            let text = try Fixture(body: math).build().body
            #expect(text.string == "(𝑎+𝑏)/2𝑥2\n")
            let exponent = text.attributes(at: (text.string as NSString).length - 2, effectiveRange: nil)
            #expect((exponent[.baselineOffset] as? CGFloat ?? 0) > 0)
        }

        @Test func numbersFootnotesAndPutsThemAtTheEnd() throws {
            // A document whose footnotes part is missing must not fail; the reference is just left out.
            let body = #"<w:p><w:r><w:t>Claim</w:t></w:r><w:r><w:footnoteReference w:id="2"/></w:r></w:p>"#
            #expect(try Fixture(body: body).build().body.string == "Claim\n")
        }

        @Test func emptyDocumentStillHasAParagraph() throws {
            #expect(try Fixture(body: "").build().body.string == "\n")
        }
    }
}
