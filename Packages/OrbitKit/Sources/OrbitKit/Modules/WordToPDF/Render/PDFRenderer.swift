import AppKit

/// Paginates a built document and draws it into a PDF.
final class PDFRenderer {
    enum Failure: Error {
        /// Some content never fits on a page, so pagination doesn't advance.
        case layoutStalled
        case tooManyPages
    }

    static let maxPages = 10_000

    private struct Page {
        let container: NSTextContainer
        let sectionIndex: Int
        /// The number shown on the page, before formatting.
        let number: Int
        let isFirstInSection: Bool
        /// Where the body text goes on this page.
        let bodyRect: CGRect
        let glyphRange: NSRange
        let characterRange: NSRange
    }

    private let document: BuiltDocument
    private let storage: NSTextStorage
    private let layoutManager = DocxLayoutManager()
    private var pages: [Page] = []
    private var storyHeights: [ObjectIdentifier: CGFloat] = [:]

    init(document: BuiltDocument) {
        self.document = document
        storage = NSTextStorage(attributedString: document.body)
        storage.addLayoutManager(layoutManager)
        // Glyphs are laid out once, front to back; there is nothing to gain from skipping ahead.
        layoutManager.allowsNonContiguousLayout = false
    }

    func render(title: String) throws -> Data {
        try paginate()
        // Page references (a table of contents) are known only now; if they change, pages may shift.
        if updatePageReferences() {
            try paginate()
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var info: [CFString: Any] = [kCGPDFContextCreator: "Orbit", kCGPDFContextTitle: document.metadata.title ?? title]
        if let author = document.metadata.author {
            info[kCGPDFContextAuthor] = author
        }
        var mediaBox = CGRect(origin: .zero, size: document.sections[0].page.size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else { return Data() }

        for index in pages.indices {
            drawPage(index, in: context)
        }
        context.closePDF()
        return data as Data
    }

    /// Characters of the body on each page, after rendering. For tests.
    var pageCharacterRanges: [NSRange] { pages.map(\.characterRange) }

    // MARK: Pagination

    private func paginate() throws {
        while !layoutManager.textContainers.isEmpty {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        pages = []

        var nextCharacter = 0
        var number = 0
        var emptyPages = 0
        while true {
            let sectionIndex = section(containing: firstVisibleCharacter(from: nextCharacter))
            let section = document.sections[sectionIndex]
            let isFirstInSection = pages.last?.sectionIndex != sectionIndex
            number = isFirstInSection ? section.pageNumberStart ?? number + 1 : number + 1
            let body = bodyRect(section: section, isFirstInSection: isFirstInSection, number: number)

            let container = NSTextContainer(size: body.size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            // TextKit honors a page break only when there is a next container to move to,
            // so a spare one follows the page while it's laid out.
            let spare = NSTextContainer(size: body.size)
            layoutManager.addTextContainer(spare)
            defer { layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1) }

            var glyphs = layoutManager.glyphRange(for: container)
            while cancelRedundantBreak(in: glyphs) {
                glyphs = layoutManager.glyphRange(for: container)
            }
            if let height = keepTogetherHeight(container, glyphs: glyphs) {
                container.size = CGSize(width: body.width, height: height)
                glyphs = layoutManager.glyphRange(for: container)
            }
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            pages.append(Page(
                container: container, sectionIndex: sectionIndex, number: number, isFirstInSection: isFirstInSection,
                bodyRect: body, glyphRange: glyphs, characterRange: characters
            ))

            if NSMaxRange(glyphs) >= layoutManager.numberOfGlyphs { break }
            emptyPages = glyphs.length == 0 ? emptyPages + 1 : 0
            guard emptyPages < 3 else { throw Failure.layoutStalled }
            guard pages.count < Self.maxPages else { throw Failure.tooManyPages }
            nextCharacter = NSMaxRange(characters)
        }
    }

    /// The text area of a page. Like Word, a header taller than the top margin pushes the text down,
    /// and a tall footer pushes it up.
    private func bodyRect(section: DocumentSection, isFirstInSection: Bool, number: Int) -> CGRect {
        let setup = section.page
        var top = setup.top
        var bottom = setup.bottom
        if let header = headerFooter(section.headers, section: section, isFirstInSection: isFirstInSection, number: number) {
            top = max(top, setup.header + height(of: header, width: setup.contentRect.width))
        }
        if let footer = headerFooter(section.footers, section: section, isFirstInSection: isFirstInSection, number: number) {
            bottom = max(bottom, setup.footer + height(of: footer, width: setup.contentRect.width))
        }
        return CGRect(x: setup.contentRect.minX, y: top, width: setup.contentRect.width, height: max(setup.size.height - top - bottom, 72))
    }

    private func headerFooter(_ set: HeaderFooterSet, section: DocumentSection, isFirstInSection: Bool, number: Int) -> NSAttributedString? {
        if isFirstInSection, section.hasTitlePage { return set.first }
        if document.usesEvenPageHeaders, number % 2 == 0 { return set.even }
        return set.standard
    }

    private func height(of story: NSAttributedString, width: CGFloat) -> CGFloat {
        if let height = storyHeights[ObjectIdentifier(story)] { return height }
        let height = TextStory(story, width: width).height
        storyHeights[ObjectIdentifier(story)] = height
        return height
    }

    /// Like Word, a break with nothing visible before it on its page doesn't leave a blank page when there is
    /// nothing left to break: the previous page ended on its own, or the break starts a section. After another
    /// manual break it does, so two page breaks in a row still make a blank page, as in Word.
    /// Neutralizes the form feed of such a break and returns whether it did.
    private func cancelRedundantBreak(in glyphs: NSRange) -> Bool {
        guard let previous = pages.last, glyphs.length > 0 else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let string = storage.string as NSString
        let previousEndedWithBreak = previous.characterRange.length > 0 && string.character(at: NSMaxRange(previous.characterRange) - 1) == 0x0C
        for index in characters.location..<NSMaxRange(characters) {
            if let kind = storage.attribute(.docxPageBreak, at: index, effectiveRange: nil) as? PageBreak {
                guard kind == .section || !previousEndedWithBreak else { return false }
                var attributes = storage.attributes(at: index, effectiveRange: nil)
                attributes[.docxPageBreak] = nil
                storage.replaceCharacters(in: NSRange(location: index, length: 1), with: NSAttributedString(string: "\u{200B}", attributes: attributes))
                return true
            }
            guard Self.invisibleCharacters.contains(string.character(at: index)) else { return false }
        }
        return false
    }

    /// Characters that leave a page looking empty: paragraph ends, spaces and neutralized breaks.
    private static let invisibleCharacters: Set<unichar> = Set("\n\u{2028}\u{200B}\t ".utf16)

    /// Pages begin with leftovers of the previous section, such as the break that ended it;
    /// the page takes its setup from the first thing it shows.
    private func firstVisibleCharacter(from index: Int) -> Int {
        let string = storage.string as NSString
        var current = index
        while current < string.length, Self.invisibleCharacters.contains(string.character(at: current)) || string.character(at: current) == 0x0C {
            current += 1
        }
        return current < string.length ? current : index
    }

    private func section(containing characterIndex: Int) -> Int {
        document.sections.lastIndex { $0.startIndex <= characterIndex } ?? 0
    }

    /// Word moves a heading to the next page together with the paragraph it belongs to, and doesn't
    /// leave a paragraph's first line alone at the bottom of a page. Returns the shortened page height
    /// that pushes such paragraphs to the next page, or `nil` if the page is fine.
    private func keepTogetherHeight(_ container: NSTextContainer, glyphs: NSRange) -> CGFloat? {
        guard glyphs.length > 0, NSMaxRange(glyphs) < layoutManager.numberOfGlyphs else { return nil }
        let string = storage.string as NSString
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let lastCharacter = NSMaxRange(characters) - 1
        // A page ended by a page break is already where the document wants it.
        guard string.character(at: lastCharacter) != 0x0C else { return nil }
        let lastParagraph = string.paragraphRange(for: NSRange(location: lastCharacter, length: 0))

        var cut: Int
        if NSMaxRange(lastParagraph) - 1 == lastCharacter {
            // The page ends with a whole paragraph: only a heading needs to move.
            guard keepsWithNext(lastParagraph.location) else { return nil }
            cut = lastParagraph.location
        } else {
            // The page ends inside a paragraph. With widow and orphan control, which Word applies unless
            // the document turns it off, at least two of its lines stay together on each page.
            guard storage.attribute(.docxWidowControl, at: lastParagraph.location, effectiveRange: nil) as? Bool == true else { return nil }
            let startsHere = lastParagraph.location >= characters.location
            let lines = lineStarts(from: glyphIndex(max(lastParagraph.location, characters.location)), to: NSMaxRange(glyphs))
            if startsHere, lines.count == 1 {
                // Its first line would be alone at the bottom.
                cut = lastParagraph.location
            } else if endsOnFirstLine(after: glyphs, paragraphEnd: glyphIndex(NSMaxRange(lastParagraph) - 1)), let last = lines.last {
                // Its last line would be alone at the top of the next page: another line goes with it,
                // or the whole paragraph if that would leave its first line alone here.
                cut = startsHere && lines.count <= 2 ? lastParagraph.location : layoutManager.characterIndexForGlyph(at: last)
            } else {
                return nil
            }
        }

        // Headings right before a moved paragraph go with it.
        while cut == string.paragraphRange(for: NSRange(location: cut, length: 0)).location, cut > characters.location {
            let previous = string.paragraphRange(for: NSRange(location: cut - 1, length: 0))
            guard keepsWithNext(previous.location) else { break }
            cut = previous.location
        }
        guard cut > characters.location, !isInTable(cut) else { return nil }

        let top = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex(cut), effectiveRange: nil).minY
        return top > 1 ? top : nil
    }

    /// The first glyph of every line from `start` up to `end`.
    private func lineStarts(from start: Int, to end: Int) -> [Int] {
        var starts: [Int] = []
        var glyph = start
        while glyph < end {
            var line = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
            starts.append(glyph)
            glyph = max(NSMaxRange(line), glyph + 1)
        }
        return starts
    }

    /// Whether the rest of a paragraph that continues past the page fits on one line of the next page,
    /// laid out in the spare container that follows the page.
    private func endsOnFirstLine(after glyphs: NSRange, paragraphEnd: Int) -> Bool {
        var line = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs), effectiveRange: &line)
        return NSMaxRange(line) > paragraphEnd
    }

    private func keepsWithNext(_ characterIndex: Int) -> Bool {
        storage.attribute(.docxKeepWithNext, at: characterIndex, effectiveRange: nil) as? Bool ?? false
    }

    private func isInTable(_ characterIndex: Int) -> Bool {
        let style = storage.attribute(.paragraphStyle, at: characterIndex, effectiveRange: nil) as? NSParagraphStyle
        return !(style?.textBlocks.isEmpty ?? true)
    }

    private func glyphIndex(_ characterIndex: Int) -> Int {
        layoutManager.glyphIndexForCharacter(at: characterIndex)
    }

    private func pageLabel(_ page: Page) -> String {
        document.sections[page.sectionIndex].pageNumberFormat.format(page.number)
    }

    // MARK: Page references

    /// Replaces cached page numbers of page references with the real ones. Returns whether anything changed.
    private func updatePageReferences() -> Bool {
        var bookmarkPages: [String: String] = [:]
        storage.enumerateAttribute(.docxBookmarks, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let names = value as? [String], let page = page(containing: range.location) else { return }
            for name in names where bookmarkPages[name] == nil {
                bookmarkPages[name] = pageLabel(page)
            }
        }

        var replacements: [(NSRange, String)] = []
        storage.enumerateAttribute(.docxField, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard case .pageReference(let name) = value as? FieldPlaceholder, let label = bookmarkPages[name] else { return }
            if storage.attributedSubstring(from: range).string != label {
                replacements.append((range, label))
            }
        }
        guard !replacements.isEmpty else { return false }

        storage.beginEditing()
        for (range, label) in replacements.reversed() {
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attributes))
        }
        storage.endEditing()
        return true
    }

    private func page(containing characterIndex: Int) -> Page? {
        pages.last { $0.characterRange.location <= characterIndex }
    }

    // MARK: Drawing

    private func drawPage(_ index: Int, in context: CGContext) {
        let page = pages[index]
        let section = document.sections[page.sectionIndex]
        let setup = section.page
        var mediaBox = CGRect(origin: .zero, size: setup.size)
        let boxData = NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)

        context.saveGState()
        // AppKit text drawing expects a flipped context: origin at the top left, y going down.
        context.translateBy(x: 0, y: setup.size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let origin = page.bodyRect.origin
        let floating = floatingDrawings(on: page, origin: origin, setup: setup)
        for (drawing, rect) in floating where drawing.isBehindText {
            DrawingRenderer.draw(drawing.drawing, in: rect, context: context)
        }

        drawHeaderAndFooter(for: index, setup: setup)
        layoutManager.drawBackground(forGlyphRange: page.glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: page.glyphRange, at: origin)

        for (drawing, rect) in floating where !drawing.isBehindText {
            DrawingRenderer.draw(drawing.drawing, in: rect, context: context)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()

        addLinks(on: page, origin: origin, pageHeight: setup.size.height, context: context)
        context.endPDFPage()
    }

    private func drawHeaderAndFooter(for index: Int, setup: PageSetup) {
        let page = pages[index]
        let section = document.sections[page.sectionIndex]
        func choose(_ set: HeaderFooterSet) -> NSAttributedString? {
            headerFooter(set, section: section, isFirstInSection: page.isFirstInSection, number: page.number)
        }
        let width = setup.contentRect.width

        if let header = choose(section.headers).map({ resolveFields($0, page: page) }) {
            TextStory(header, width: width).draw(at: CGPoint(x: setup.left, y: setup.header))
        }
        if let footer = choose(section.footers).map({ resolveFields($0, page: page) }) {
            let story = TextStory(footer, width: width)
            story.draw(at: CGPoint(x: setup.left, y: setup.size.height - setup.footer - story.height))
        }
    }

    /// The header or footer text with this page's numbers in place of its page fields.
    private func resolveFields(_ text: NSAttributedString, page: Page) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        var replacements: [(NSRange, String)] = []
        result.enumerateAttribute(.docxField, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            switch value as? FieldPlaceholder {
            case .page: replacements.append((range, pageLabel(page)))
            case .pageCount: replacements.append((range, String(pages.count)))
            case .sectionPageCount: replacements.append((range, String(pages.filter { $0.sectionIndex == page.sectionIndex }.count)))
            case .pageReference, nil: break
            }
        }
        for (range, value) in replacements.reversed() {
            result.replaceCharacters(in: range, with: value)
        }
        return result
    }

    /// Floating drawings anchored in the page's paragraphs, with their frames on the page.
    private func floatingDrawings(on page: Page, origin: CGPoint, setup: PageSetup) -> [(FloatingDrawing, CGRect)] {
        var result: [(FloatingDrawing, CGRect)] = []
        storage.enumerateAttribute(.docxFloatingDrawings, in: page.characterRange) { value, range, _ in
            guard let drawings = value as? [FloatingDrawing] else { return }
            let glyph = glyphIndex(range.location)
            let paragraphTop = origin.y + layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            for drawing in drawings {
                result.append((drawing, Self.frame(of: drawing, setup: setup, paragraphTop: paragraphTop)))
            }
        }
        return result
    }

    static func frame(of drawing: FloatingDrawing, setup: PageSetup, paragraphTop: CGFloat) -> CGRect {
        let size = drawing.drawing.size
        let content = setup.contentRect

        func position(_ axis: FloatingDrawing.Axis, start: CGFloat, length: CGFloat, size: CGFloat) -> CGFloat {
            switch axis.placement {
            case .offset(let offset): start + offset
            case .leading: start
            case .center: start + (length - size) / 2
            case .trailing: start + length - size
            }
        }
        let horizontal: (CGFloat, CGFloat) = drawing.horizontal.origin == .page ? (0, setup.size.width) : (content.minX, content.width)
        let vertical: (CGFloat, CGFloat) = switch drawing.vertical.origin {
        case .page: (0, setup.size.height)
        case .margin: (content.minY, content.height)
        case .paragraph: (paragraphTop, content.maxY - paragraphTop)
        }
        return CGRect(
            x: position(drawing.horizontal, start: horizontal.0, length: horizontal.1, size: size.width),
            y: position(drawing.vertical, start: vertical.0, length: vertical.1, size: size.height),
            width: size.width, height: size.height
        )
    }

    // MARK: Links

    /// Bookmark destinations and links to them. Web links are added by AppKit as it draws the text.
    private func addLinks(on page: Page, origin: CGPoint, pageHeight: CGFloat, context: CGContext) {
        // PDF space has its origin at the bottom left.
        func pdfRect(_ rect: CGRect) -> CGRect {
            CGRect(x: origin.x + rect.minX, y: pageHeight - origin.y - rect.maxY, width: rect.width, height: rect.height)
        }

        storage.enumerateAttribute(.docxBookmarks, in: page.characterRange) { value, range, _ in
            guard let names = value as? [String] else { return }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex(range.location), effectiveRange: nil)
            let point = CGPoint(x: origin.x + line.minX, y: pageHeight - origin.y - line.minY)
            for name in names {
                context.addDestination(name as CFString, at: point)
            }
        }

        storage.enumerateAttribute(.docxInternalLink, in: page.characterRange) { value, range, _ in
            guard let name = value as? String else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: page.container
            ) { rect, _ in
                context.setDestination(name as CFString, for: pdfRect(rect))
            }
        }
    }
}
