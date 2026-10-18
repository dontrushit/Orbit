import AppKit

/// Translates a .docx package into attributed text and page setup.
///
/// Builds text in document order, keeping the state that spans paragraphs:
/// list counters, open fields, bookmarks waiting for their first character.
final class DocumentBuilder {
    /// A part with text of its own: the document body, a header, a footer or the notes.
    struct Story {
        let path: String
        let relationships: Relationships
        /// Headers and footers show live page numbers instead of the values cached in the file.
        let hasLivePageFields: Bool
    }

    /// Where blocks are being added.
    struct BlockContext {
        /// Table cells around the content, outermost first.
        var blocks: [NSTextBlock] = []
        /// Formatting that the table style gives this cell.
        var tableFormatting: StyleSheet.TableFormatting?
        /// Width available to the content.
        var width: CGFloat

        var isInTable: Bool { !blocks.isEmpty }
    }

    /// The paragraph added last at the current level, for spacing that depends on the neighbor.
    struct PreviousParagraph {
        let range: NSRange
        let styleID: String?
        let hasContextualSpacing: Bool
        let style: NSMutableParagraphStyle
    }

    let package: DocxPackage
    let styles: StyleSheet
    let numberingDefinitions: NumberingDefinitions
    let theme: DocxTheme
    let settings: DocumentSettings
    let styler: TextStyler
    var numbering: NumberingCounter
    /// Page setup of the section being built; drawings larger than its text area are scaled down.
    var page = PageSetup()

    /// Fields whose begin has been read but not their end. Fields can span paragraphs, like a table of contents.
    var openFields: [OpenField] = []
    /// Bookmarks waiting for the next character.
    var pendingBookmarks: [String] = []
    var notes = NoteCollector()
    var images: [String: Drawing.Content] = [:]
    private var headerFooterCache: [String: NSAttributedString] = [:]

    init(package: DocxPackage) throws {
        self.package = package
        let documentPath = try package.mainDocumentPath()
        let relationships = try package.relationships(of: documentPath)
        func part(_ type: String) throws -> MarkupElement? {
            guard let path = relationships.first(ofType: type)?.target else { return nil }
            return try package.xml(at: path)
        }

        let styles = StyleSheet(xml: try part("styles"))
        self.styles = styles
        numberingDefinitions = NumberingDefinitions(xml: try part("numbering")) { styleID in
            styles.paragraphStyle(styleID).paragraph.numberingID
        }
        numbering = NumberingCounter(definitions: numberingDefinitions)
        theme = DocxTheme(xml: try part("theme"))
        settings = DocumentSettings(xml: try part("settings"))
        styler = TextStyler(fonts: FontResolver(fontTable: FontTable(xml: try part("fontTable"))), theme: theme, settings: settings)
        notes.footnotes = try part("footnotes")
        notes.endnotes = try part("endnotes")
        notes.footnotesPath = relationships.first(ofType: "footnotes")?.target
        notes.endnotesPath = relationships.first(ofType: "endnotes")?.target
    }

    func build() throws -> BuiltDocument {
        let path = try package.mainDocumentPath()
        guard let body = try package.xml(at: path)?.child("body") else { throw DocxError.missingPart(path) }
        let story = Story(path: path, relationships: try package.relationships(of: path), hasLivePageFields: false)

        // Section properties come at the end of each section, but its page setup and break type
        // are needed from its first paragraph on.
        let sectionProperties = Self.sectionProperties(in: body)
        var sectionIndex = 0
        page = Self.pageSetup(sectionProperties[0])
        var sections = [makeSection(sectionProperties[0], startIndex: 0, previous: nil)]

        let output = NSMutableAttributedString()
        var previous: PreviousParagraph?
        var breakBeforeNext = false
        for element in body.children where !element.is("sectPr") {
            if breakBeforeNext {
                appendPageBreak(.section, to: output)
                breakBeforeNext = false
            }
            appendBlock(element, to: output, story: story, context: BlockContext(width: page.contentRect.width), previous: &previous)

            if element.is("p"), element.child("pPr")?.child("sectPr") != nil, sectionIndex + 1 < sectionProperties.count {
                sectionIndex += 1
                let next = sectionProperties[sectionIndex]
                page = Self.pageSetup(next)
                sections.append(makeSection(next, startIndex: output.length, previous: sections.last))
                breakBeforeNext = next?.value(of: "type") != "continuous"
                if breakBeforeNext, let previous, output.attributedSubstring(from: previous.range).string == "\n" {
                    // An empty paragraph that only carries the section break takes no space, as in Word.
                    TextStyler.collapse(previous.style)
                    output.addAttribute(.paragraphStyle, value: previous.style, range: previous.range)
                }
                previous = nil
            }
        }

        appendNotes(to: output)
        if output.length == 0 {
            output.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: styles.defaultRun, text: "")))
        }

        let metadata = DocumentMetadata(xml: try package.xml(at: "docProps/core.xml"))
        return BuiltDocument(body: output, sections: sections, usesEvenPageHeaders: settings.evenAndOddHeaders, metadata: metadata)
    }

    // MARK: Sections

    /// `sectPr` of every section in order. A document always has at least one.
    private static func sectionProperties(in body: MarkupElement) -> [MarkupElement?] {
        let breaks = body.children("p").compactMap { $0.child("pPr")?.child("sectPr") }
        return breaks + [body.child("sectPr")]
    }

    static func pageSetup(_ properties: MarkupElement?) -> PageSetup {
        var setup = PageSetup()
        if let size = properties?.child("pgSz"),
           let width = Measure.twips(size.attribute("w")), let height = Measure.twips(size.attribute("h")),
           width > 0, height > 0 {
            setup.size = CGSize(width: width, height: height)
        }
        if let margins = properties?.child("pgMar") {
            // Negative top and bottom margins mean the text doesn't move away from tall headers; the size is what counts.
            func margin(_ name: String) -> CGFloat? { Measure.twips(margins.attribute(name)).map(abs) }
            setup.top = margin("top") ?? setup.top
            setup.bottom = margin("bottom") ?? setup.bottom
            setup.left = (margin("left") ?? setup.left) + (margin("gutter") ?? 0)
            setup.right = margin("right") ?? setup.right
            setup.header = margin("header") ?? setup.header
            setup.footer = margin("footer") ?? setup.footer
        }
        return setup
    }

    private func makeSection(_ properties: MarkupElement?, startIndex: Int, previous: DocumentSection?) -> DocumentSection {
        var section = DocumentSection(startIndex: startIndex, page: Self.pageSetup(properties))
        section.hasTitlePage = properties?.flag("titlePg") ?? false
        if let numbering = properties?.child("pgNumType") {
            section.pageNumberStart = numbering.attribute("start").flatMap(Int.init)
            section.pageNumberFormat = NumberFormat(numbering.attribute("fmt"))
        }
        section.headers = headerFooters(properties, reference: "headerReference").inheriting(from: previous?.headers ?? HeaderFooterSet())
        section.footers = headerFooters(properties, reference: "footerReference").inheriting(from: previous?.footers ?? HeaderFooterSet())
        return section
    }

    private func headerFooters(_ properties: MarkupElement?, reference: String) -> HeaderFooterSet {
        var set = HeaderFooterSet()
        for element in properties?.children(reference) ?? [] {
            guard let id = element.attribute("id", in: .r), let text = headerFooter(relationshipID: id) else { continue }
            switch element.attribute("type") {
            case "first": set.first = text
            case "even": set.even = text
            default: set.standard = text
            }
        }
        return set
    }

    private func headerFooter(relationshipID: String) -> NSAttributedString? {
        guard let documentPath = try? package.mainDocumentPath(),
              let path = (try? package.relationships(of: documentPath))?[relationshipID]?.target
        else { return nil }
        if let cached = headerFooterCache[path] { return cached }
        guard let root = try? package.xml(at: path), let relationships = try? package.relationships(of: path) else { return nil }

        let story = Story(path: path, relationships: relationships, hasLivePageFields: true)
        let text = buildStory(root.children, story: story, width: page.contentRect.width)
        headerFooterCache[path] = text
        return text
    }

    /// Builds a separate piece of text, such as a header or a text box, without disturbing the body's state.
    func buildStory(_ elements: [MarkupElement], story: Story, width: CGFloat) -> NSAttributedString {
        let savedFields = openFields
        let savedBookmarks = pendingBookmarks
        openFields = []
        pendingBookmarks = []
        defer {
            openFields = savedFields
            pendingBookmarks = savedBookmarks
        }

        let output = NSMutableAttributedString()
        appendBlocks(elements, to: output, story: story, context: BlockContext(width: width))
        return output
    }

    // MARK: Blocks

    func appendBlocks(_ elements: [MarkupElement], to output: NSMutableAttributedString, story: Story, context: BlockContext) {
        var previous: PreviousParagraph?
        for element in elements {
            appendBlock(element, to: output, story: story, context: context, previous: &previous)
        }
    }

    private func appendBlock(
        _ element: MarkupElement, to output: NSMutableAttributedString, story: Story,
        context: BlockContext, previous: inout PreviousParagraph?
    ) {
        guard element.namespace == .w else {
            if element.is("AlternateContent", in: .markupCompatibility) {
                for child in Self.chosenAlternative(element) {
                    appendBlock(child, to: output, story: story, context: context, previous: &previous)
                }
            }
            return
        }
        switch element.name {
        case "p":
            appendParagraph(element, to: output, story: story, context: context, previous: &previous)
        case "tbl":
            appendTable(element, to: output, story: story, context: context)
            previous = nil
        case "sdt":
            for child in element.child("sdtContent")?.children ?? [] {
                appendBlock(child, to: output, story: story, context: context, previous: &previous)
            }
        case "customXml", "ins", "moveTo":
            for child in element.children {
                appendBlock(child, to: output, story: story, context: context, previous: &previous)
            }
        case "bookmarkStart":
            addBookmark(element)
        default:
            break
        }
    }

    func appendPageBreak(_ kind: PageBreak = .page, to output: NSMutableAttributedString) {
        guard output.length > 0 else { return }
        output.append(TextStyler.pageBreakParagraph(kind))
    }

    // MARK: Paragraphs

    private func appendParagraph(
        _ element: MarkupElement, to output: NSMutableAttributedString, story: Story,
        context: BlockContext, previous: inout PreviousParagraph?
    ) {
        let markProperties = element.child("pPr")
        let direct = ParagraphProperties(xml: markProperties)
        let style = styles.paragraphStyle(direct.styleID)
        let usesDefaultStyle = direct.styleID == nil || direct.styleID == styles.defaultParagraphStyleID

        var paragraph = styles.defaultParagraph
        var run = styles.defaultRun
        // Table styles take precedence over the default paragraph style, but not over a style chosen for the paragraph.
        if let table = context.tableFormatting, !usesDefaultStyle {
            paragraph.apply(table.paragraph)
            run.apply(table.run)
        }
        paragraph.apply(style.paragraph)
        run.apply(style.run)
        if let table = context.tableFormatting, usesDefaultStyle {
            paragraph.apply(table.paragraph)
            run.apply(table.run)
        }

        var label: (text: String, level: NumberingDefinitions.Level)?
        if let listID = direct.numberingID ?? style.paragraph.numberingID, listID != "0" {
            let levelIndex = direct.numberingLevel ?? style.paragraph.numberingLevel ?? 0
            if let level = numberingDefinitions.level(levelIndex, of: listID) {
                paragraph.apply(level.paragraph)
                if let text = numbering.nextLabel(list: listID, level: levelIndex) {
                    label = (text, level)
                }
            }
        }
        paragraph.apply(direct)

        var markRun = run
        let directMark = RunProperties(xml: markProperties?.child("rPr"))
        if let characterStyle = directMark.characterStyleID {
            markRun.apply(styles.characterStyle(characterStyle))
        }
        markRun.apply(directMark)

        // Content
        var content = ParagraphContent()
        if let label, !label.text.isEmpty {
            var labelRun = markRun
            labelRun.underline = nil
            labelRun.apply(label.level.run)
            let suffix = switch label.level.suffix {
            case .tab: "\t"
            case .space: " "
            case .nothing: ""
            }
            appendText(label.text, properties: labelRun, to: &content)
            appendText(suffix, properties: markRun, to: &content)
        }
        appendInline(element.children, state: InlineState(base: run), to: &content, story: story, context: context)
        if content.isDisplayMath {
            paragraph.alignment = .center
        }

        // Page breaks: a paragraph of its own before or after; inside the text only when there is text on both sides.
        // Word ignores page breaks in tables.
        var breakAfter = false
        if !context.isInTable {
            var breakBefore = paragraph.pageBreakBefore == true
            for position in content.pageBreaks.reversed() {
                // A paragraph holding nothing but the break stays on the page the break ends, as in Word.
                if position >= content.text.length {
                    breakAfter = true
                } else if position == 0 {
                    breakBefore = true
                } else {
                    content.text.insert(NSAttributedString(string: "\u{0C}", attributes: content.text.attributes(at: position, effectiveRange: nil)), at: position)
                }
            }
            if breakBefore {
                appendPageBreak(to: output)
            }
        }

        let start = output.length
        content.text.append(NSAttributedString(string: "\n", attributes: styler.attributes(for: markRun, text: "")))
        if !pendingBookmarks.isEmpty {
            content.text.addAttribute(.docxBookmarks, value: pendingBookmarks, range: NSRange(location: content.text.length - 1, length: 1))
            pendingBookmarks = []
        }
        output.append(content.text)
        let range = NSRange(location: start, length: output.length - start)

        let paragraphStyle = styler.paragraphStyle(
            for: paragraph, blocks: context.blocks, singleLineHeight: TextStyler.singleLineHeight(of: content.text)
        )
        let styleID = direct.styleID ?? styles.defaultParagraphStyleID
        let contextual = paragraph.contextualSpacing == true
        if let previous, previous.styleID == styleID {
            // Contextual spacing removes a paragraph's own spacing next to paragraphs of the same style.
            if contextual {
                paragraphStyle.paragraphSpacingBefore = 0
            }
            if previous.hasContextualSpacing {
                previous.style.paragraphSpacing = 0
                output.addAttribute(.paragraphStyle, value: previous.style, range: previous.range)
            }
        }
        output.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        if let leaders = TextStyler.tabLeaders(for: paragraph) {
            output.addAttribute(.docxTabLeaders, value: leaders, range: range)
        }
        if paragraph.keepWithNext == true {
            output.addAttribute(.docxKeepWithNext, value: true, range: range)
        }
        // Word keeps widow and orphan control on unless a style or the paragraph turns it off.
        if paragraph.widowControl != false {
            output.addAttribute(.docxWidowControl, value: true, range: range)
        }
        if !content.floating.isEmpty {
            output.addAttribute(.docxFloatingDrawings, value: content.floating, range: NSRange(location: start, length: 1))
        }
        previous = PreviousParagraph(range: range, styleID: styleID, hasContextualSpacing: contextual, style: paragraphStyle)

        if breakAfter {
            appendPageBreak(to: output)
        }
    }

    // MARK: Bookmarks

    func addBookmark(_ element: MarkupElement) {
        // Word adds "_GoBack" to remember the last edit position; it's never a link target.
        guard let name = element.attribute("name"), name != "_GoBack" else { return }
        pendingBookmarks.append(name)
    }

    // MARK: Alternate content

    /// Prefixes of the extensions whose markup the converter understands.
    private static let supportedExtensions: Set<String> = ["wps", "wpg", "wpc", "wp14", "w14", "w15", "a14", "m", "v", "o", "w10"]

    /// The children of the first `mc:Choice` that the converter supports, or of `mc:Fallback`.
    static func chosenAlternative(_ element: MarkupElement) -> [MarkupElement] {
        for choice in element.children("Choice", in: .markupCompatibility) {
            let requires = (choice.attribute("Requires", in: .none) ?? "").split(separator: " ").map(String.init)
            if requires.allSatisfy(supportedExtensions.contains) {
                return choice.children
            }
        }
        return element.child("Fallback", in: .markupCompatibility)?.children ?? []
    }
}

/// Text of a paragraph being built, before it's added to the output.
struct ParagraphContent {
    var text = NSMutableAttributedString()
    /// Positions in `text` where a page break was found.
    var pageBreaks: [Int] = []
    var floating: [FloatingDrawing] = []
    /// The paragraph is an equation on its own line, which Word centers.
    var isDisplayMath = false
}
