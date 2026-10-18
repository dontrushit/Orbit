import Foundation
import Testing
@testable import OrbitKit

private func xml(_ string: String) throws -> MarkupElement {
    try MarkupParser.parse(Data(string.utf8))
}

private let w = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#

@Suite struct MeasureTests {
    @Test func convertsWordUnitsToPoints() {
        #expect(Measure.twips("1440") == 72)
        #expect(Measure.halfPoints("28") == 14)
        #expect(Measure.eighthPoints("4") == 0.5)
        #expect(Measure.emu("914400") == 72)
        #expect(Measure.twips(nil) == nil)
        #expect(Measure.twips("wide") == nil)
    }

    @Test(arguments: [("12pt", 12.0), ("1in", 72.0), ("2.54cm", 72.0), ("25.4mm", 72.0), ("1pc", 12.0)])
    func readsUniversalMeasures(value: String, points: Double) throws {
        let result = try #require(Measure.twips(value))
        #expect(abs(Double(result) - points) < 0.001)
    }

    @Test func readsColors() {
        #expect(RGBColor(hex: "FF0000") == RGBColor(red: 1, green: 0, blue: 0))
        #expect(RGBColor(hex: "auto") == nil)
        #expect(RGBColor(highlight: "yellow") == RGBColor(red: 1, green: 1, blue: 0))
        #expect(RGBColor(highlight: "none") == nil)
    }
}

@Suite struct NumberFormatTests {
    @Test(arguments: [
        (NumberFormat.decimal, 12, "12"),
        (.decimalZero, 7, "07"),
        (.upperRoman, 1994, "MCMXCIV"),
        (.lowerRoman, 4, "iv"),
        (.upperLetter, 1, "A"),
        (.lowerLetter, 27, "aa"),
        (.lowerLetter, 54, "bbb"),
        (.russianLower, 10, "к"),
        (.russianUpper, 29, "АА"),
        (.none, 3, ""),
    ])
    func formats(format: NumberFormat, number: Int, expected: String) {
        #expect(format.format(number) == expected)
    }

    @Test func fallsBackToDecimalForOutOfRangeNumbers() {
        #expect(NumberFormat.upperRoman.format(0) == "0")
        #expect(NumberFormat.lowerLetter.format(-1) == "-1")
    }
}

@Suite struct NumberingTests {
    private func definitions() throws -> NumberingDefinitions {
        try NumberingDefinitions(xml: xml("""
            <w:numbering \(w)>
              <w:abstractNum w:abstractNumId="0">
                <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
                <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2."/></w:lvl>
              </w:abstractNum>
              <w:abstractNum w:abstractNumId="1">
                <w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl>
              </w:abstractNum>
              <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
              <w:num w:numId="2"><w:abstractNumId w:val="0"/></w:num>
              <w:num w:numId="3"><w:abstractNumId w:val="0"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride></w:num>
              <w:num w:numId="4"><w:abstractNumId w:val="1"/></w:num>
            </w:numbering>
            """))
    }

    @Test func numbersNestedLevels() throws {
        var counter = NumberingCounter(definitions: try definitions())
        let labels = [(0), (1), (1), (0), (1)].map { counter.nextLabel(list: "1", level: $0) }
        #expect(labels == ["1.", "1.1.", "1.2.", "2.", "2.1."])
    }

    @Test func listsSharingADefinitionContinueEachOther() throws {
        var counter = NumberingCounter(definitions: try definitions())
        #expect(counter.nextLabel(list: "1", level: 0) == "1.")
        #expect(counter.nextLabel(list: "2", level: 0) == "2.")
    }

    @Test func startOverrideRestartsTheList() throws {
        var counter = NumberingCounter(definitions: try definitions())
        _ = counter.nextLabel(list: "1", level: 0)
        #expect(counter.nextLabel(list: "3", level: 0) == "5.")
        #expect(counter.nextLabel(list: "3", level: 0) == "6.")
    }

    @Test func bulletsUseTheirText() throws {
        var counter = NumberingCounter(definitions: try definitions())
        #expect(counter.nextLabel(list: "4", level: 0) == "•")
    }

    @Test func unknownListHasNoLabel() throws {
        var counter = NumberingCounter(definitions: try definitions())
        #expect(counter.nextLabel(list: "99", level: 0) == nil)
        #expect(counter.nextLabel(list: "1", level: 5) == nil)
    }
}

@Suite struct SymbolFontTests {
    @Test func coversTheWholeSymbolEncoding() {
        #expect(SymbolFonts.lowTable.count == 0x7E - 0x20 + 1)
        #expect(SymbolFonts.highTable.count == 0xFE - 0xA1 + 1)
    }

    @Test func translatesSymbolCharactersToUnicode() {
        #expect(SymbolFonts.resolve("\u{F0B7}", font: "Symbol").text == "•")
        #expect(SymbolFonts.resolve("\u{F0B7}", font: "Symbol").font == nil)
        #expect(SymbolFonts.resolve("a", font: "Symbol").text == "α")
        #expect(SymbolFonts.resolve("\u{F0D6}", font: "Symbol").text == "√")
    }

    @Test func keepsWingdingsInItsPrivateEncoding() {
        let resolved = SymbolFonts.resolve("\u{A7}", font: "Wingdings")
        #expect(resolved.text == "\u{F0A7}")
        #expect(resolved.font == "Wingdings")
    }

    @Test func leavesRegularFontsAlone() {
        #expect(SymbolFonts.resolve("text", font: "Arial").text == "text")
    }
}

@Suite struct FieldInstructionTests {
    @Test func splitsNameArgumentsAndSwitches() {
        let field = FieldInstruction(#" PAGEREF _Toc138331684 \h "#)
        #expect(field.name == "PAGEREF")
        #expect(field.arguments == ["_Toc138331684"])
        #expect(field.switches == ["h"])
    }

    @Test func keepsQuotedArgumentsWhole() {
        let field = FieldInstruction(#"HYPERLINK "https://example.com/a b" \o "Tip text""#)
        #expect(field.name == "HYPERLINK")
        #expect(field.arguments == ["https://example.com/a b", "Tip text"])
        #expect(field.switches == ["o"])
    }

    @Test func handlesEmptyInstructions() {
        #expect(FieldInstruction("   ").name == "")
    }
}

@Suite struct StyleSheetTests {
    private func styles() throws -> StyleSheet {
        try StyleSheet(xml: xml("""
            <w:styles \(w)>
              <w:docDefaults>
                <w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault>
                <w:pPrDefault><w:pPr><w:spacing w:after="160"/></w:pPr></w:pPrDefault>
              </w:docDefaults>
              <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>
                <w:pPr><w:jc w:val="both"/></w:pPr><w:rPr><w:sz w:val="28"/></w:rPr></w:style>
              <w:style w:type="paragraph" w:styleId="Heading1"><w:basedOn w:val="Normal"/>
                <w:pPr><w:keepNext/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>
              <w:style w:type="paragraph" w:styleId="LoopA"><w:basedOn w:val="LoopB"/><w:pPr><w:jc w:val="right"/></w:pPr></w:style>
              <w:style w:type="paragraph" w:styleId="LoopB"><w:basedOn w:val="LoopA"/></w:style>
              <w:style w:type="character" w:styleId="af6"><w:name w:val="Hyperlink"/><w:rPr><w:u w:val="single"/></w:rPr></w:style>
            </w:styles>
            """))
    }

    @Test func inheritsAlongBasedOn() throws {
        let heading = try styles().paragraphStyle("Heading1")
        #expect(heading.paragraph.alignment == .center)
        #expect(heading.paragraph.keepWithNext == true)
        #expect(heading.run.bold == true)
        #expect(heading.run.size == 14)
    }

    @Test func fallsBackToTheDefaultStyle() throws {
        let sheet = try styles()
        #expect(sheet.paragraphStyle(nil).paragraph.alignment == .justified)
        #expect(sheet.paragraphStyle("Missing").paragraph.alignment == .justified)
        #expect(sheet.defaultParagraphStyleID == "Normal")
    }

    @Test func survivesCyclesInBasedOn() throws {
        #expect(try styles().paragraphStyle("LoopA").paragraph.alignment == .right)
    }

    @Test func readsDocumentDefaults() throws {
        let sheet = try styles()
        #expect(sheet.defaultRun.size == 11)
        #expect(sheet.defaultParagraph.spacingAfter == 8)
    }

    @Test func findsStylesByLocalizedID() throws {
        #expect(try styles().name(ofStyle: "af6") == "Hyperlink")
    }
}

@Suite struct ParagraphPropertiesTests {
    @Test func laterTabStopsReplaceAndClearEarlierOnes() throws {
        var properties = try ParagraphProperties(xml: xml("""
            <w:pPr \(w)><w:tabs><w:tab w:val="left" w:pos="720"/><w:tab w:val="right" w:leader="dot" w:pos="9000"/></w:tabs></w:pPr>
            """))
        properties.apply(try ParagraphProperties(xml: xml("""
            <w:pPr \(w)><w:tabs><w:tab w:val="clear" w:pos="720"/><w:tab w:val="center" w:pos="1440"/></w:tabs></w:pPr>
            """)))
        #expect(properties.resolvedTabs == [
            TabStop(position: 72, alignment: .center),
            TabStop(position: 450, alignment: .right, leader: .dot),
        ])
    }

    @Test func readsHangingIndentAsNegativeFirstLine() throws {
        let properties = try ParagraphProperties(xml: xml(#"<w:pPr \#(w)><w:ind w:left="720" w:hanging="360"/></w:pPr>"#))
        #expect(properties.indentLeft == 36)
        #expect(properties.indentFirstLine == -18)
    }

    @Test func readsLineSpacingRules() throws {
        func spacing(_ attributes: String) throws -> ParagraphProperties.LineSpacing? {
            try ParagraphProperties(xml: xml(#"<w:pPr \#(w)><w:spacing \#(attributes)/></w:pPr>"#)).lineSpacing
        }
        #expect(try spacing(#"w:line="360" w:lineRule="auto""#) == .auto(1.5))
        #expect(try spacing(#"w:line="240""#) == .auto(1))
        #expect(try spacing(#"w:line="300" w:lineRule="exact""#) == .exact(15))
        #expect(try spacing(#"w:line="280" w:lineRule="atLeast""#) == .atLeast(14))
    }
}

@Suite struct TableRegionTests {
    private func regions(row: Int, column: Int, look: TableProperties.Look = TableProperties.Look()) -> [StyleSheet.TableRegion] {
        TableRegionSelector(row: row, rowSpan: 1, rowCount: 4, column: column, columnSpan: 1, columnCount: 3, look: look).regions
    }

    @Test func headerRowAndFirstColumnByDefault() {
        #expect(regions(row: 0, column: 0) == [.firstCol, .firstRow, .nwCell])
        #expect(regions(row: 0, column: 1) == [.firstRow])
    }

    @Test func bandsSkipTheHeaderRow() {
        #expect(regions(row: 1, column: 1) == [.band1Horz])
        #expect(regions(row: 2, column: 1) == [.band2Horz])
    }

    @Test func lookTurnsRegionsOff() throws {
        let look = TableProperties.Look(xml: try xml(#"<w:tblLook \#(w) w:firstRow="0" w:firstColumn="0" w:noHBand="1"/>"#))
        #expect(regions(row: 0, column: 0, look: look).isEmpty)
    }
}
