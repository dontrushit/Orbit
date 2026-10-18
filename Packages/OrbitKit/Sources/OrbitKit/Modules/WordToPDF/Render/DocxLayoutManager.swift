import AppKit

/// Draws what TextKit leaves out: drawings in place of attachments and leaders before tab stops.
final class DocxLayoutManager: NSLayoutManager {
    private let spacing = PageTopSpacing()

    override init() {
        super.init()
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = spacing
        typesetter = WordTypesetter()
        // Paragraph styles already include the line gap the way Word counts it (`TextStyler.singleLineHeight`).
        usesFontLeading = false
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawDrawings(forGlyphRange: glyphsToShow, at: origin)
        drawTabLeaders(forGlyphRange: glyphsToShow, at: origin)
    }

    /// The attachments of drawings carry empty images; the drawings are painted in the space they take.
    private func drawDrawings(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let context = NSGraphicsContext.current?.cgContext else { return }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        storage.enumerateAttribute(.docxDrawing, in: characters) { value, range, _ in
            guard let drawing = value as? Drawing else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            guard let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return }
            let frame = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            // The glyph box spans the line height; the drawing sits on the baseline.
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + location(forGlyphAt: glyph).y
            let rect = CGRect(x: origin.x + frame.minX, y: origin.y + baseline - drawing.size.height, width: drawing.size.width, height: drawing.size.height)
            DrawingRenderer.draw(drawing, in: rect, context: context)
        }
    }

    private func drawTabLeaders(forGlyphRange glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let string = storage.string as NSString

        storage.enumerateAttribute(.docxTabLeaders, in: characters) { value, range, _ in
            guard let leaders = value as? TabLeaders else { return }
            var search = range
            while search.length > 0 {
                let tab = string.range(of: "\t", range: search)
                guard tab.location != NSNotFound else { break }
                drawLeader(leaders, tabAt: tab.location, origin: origin)
                search = NSRange(location: NSMaxRange(tab), length: NSMaxRange(search) - NSMaxRange(tab))
            }
        }
    }

    private func drawLeader(_ leaders: TabLeaders, tabAt characterIndex: Int, origin: NSPoint) {
        guard let storage = textStorage else { return }
        let glyph = glyphIndexForCharacter(at: characterIndex)
        guard glyph < numberOfGlyphs, let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return }

        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let tab = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        // Tab stops are measured from the start of the line's box: the margin, or the cell in a table.
        let leader = leaders.leader(forTabStartingAt: tab.minX - line.minX)
        let character = switch leader {
        case .none: ""
        case .dot: "."
        case .hyphen: "-"
        case .underscore: "_"
        case .middleDot: "·"
        }
        guard !character.isEmpty else { return }

        var attributes = storage.attributes(at: characterIndex, effectiveRange: nil)
        attributes[.underlineStyle] = nil
        attributes[.strikethroughStyle] = nil
        attributes[.backgroundColor] = nil
        guard let font = attributes[.font] as? NSFont else { return }
        let unitWidth = (character as NSString).size(withAttributes: attributes).width
        let gap = font.pointSize * 0.15
        let count = Int((tab.width - gap) / unitWidth)
        guard unitWidth > 0, count > 0 else { return }

        // Right-aligned, so leaders of different lines end evenly at the stop.
        let baseline = line.minY + location(forGlyphAt: glyph).y
        let point = NSPoint(x: origin.x + tab.maxX - gap - CGFloat(count) * unitWidth, y: origin.y + baseline - font.ascender)
        (String(repeating: character, count: count) as NSString).draw(at: point, withAttributes: attributes)
    }
}

/// Lays out lines the way Word does. Justification widens only spaces. TextKit also spreads letters when the spaces
/// would grow a lot, and spreads the letters of a line without spaces, such as a long word alone in a narrow
/// table cell, which Word leaves aligned to the left.
private final class WordTypesetter: NSATSTypesetter {
    /// Word drops the space after a line at the bottom of a page: a line fits when its text does.
    /// TextKit wants the spacing to fit too, and would push the line to the next page.
    override func getLineFragmentRect(
        _ lineFragmentRect: NSRectPointer!, usedRect lineFragmentUsedRect: NSRectPointer!, remaining remainingRect: NSRectPointer!,
        forStartingGlyphAt startingGlyphIndex: Int, proposedRect: NSRect,
        lineSpacing: CGFloat, paragraphSpacingBefore: CGFloat, paragraphSpacingAfter: CGFloat
    ) {
        // Decided up front: asking TextKit twice isn't possible, a line that doesn't fit moves on to the next container.
        var lineSpacing = lineSpacing
        var paragraphSpacingAfter = paragraphSpacingAfter
        if lineSpacing + paragraphSpacingAfter > 0, let container = currentTextContainer {
            let textBottom = proposedRect.minY + paragraphSpacingBefore + lineHeight(startingAt: startingGlyphIndex, proposed: proposedRect.height)
            let room = container.size.height - textBottom
            if room >= 0, room < lineSpacing + paragraphSpacingAfter {
                lineSpacing = min(lineSpacing, room)
                paragraphSpacingAfter = min(paragraphSpacingAfter, room - lineSpacing)
            }
        }
        super.getLineFragmentRect(
            lineFragmentRect, usedRect: lineFragmentUsedRect, remaining: remainingRect,
            forStartingGlyphAt: startingGlyphIndex, proposedRect: proposedRect,
            lineSpacing: lineSpacing, paragraphSpacingBefore: paragraphSpacingBefore, paragraphSpacingAfter: paragraphSpacingAfter
        )
    }

    /// The height of the line's text: the proposed height within the paragraph's minimum and maximum.
    private func lineHeight(startingAt glyphIndex: Int, proposed: CGFloat) -> CGFloat {
        guard let layoutManager, let storage = layoutManager.textStorage, glyphIndex < layoutManager.numberOfGlyphs else { return proposed }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < storage.length,
              let style = storage.attribute(.paragraphStyle, at: characterIndex, effectiveRange: nil) as? NSParagraphStyle
        else { return proposed }
        let height = max(proposed, style.minimumLineHeight)
        return style.maximumLineHeight > 0 ? min(height, style.maximumLineHeight) : height
    }

    override func endLine(withGlyphRange lineGlyphRange: NSRange) {
        super.endLine(withGlyphRange: lineGlyphRange)
        guard let layoutManager, let storage = layoutManager.textStorage, lineGlyphRange.length > 1 else { return }
        let characters = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
        guard let style = storage.attribute(.paragraphStyle, at: characters.location, effectiveRange: nil) as? NSParagraphStyle,
              style.alignment == .justified
        else { return }
        let string = storage.string as NSString
        // Tabs and pictures have widths of their own; such lines keep TextKit's layout.
        let text = string.substring(with: characters)
        guard !text.contains("\t"), !text.contains("\u{FFFC}") else { return }

        struct Glyph {
            let index: Int
            let advance: CGFloat
            let isSpace: Bool
        }
        var glyphs: [Glyph] = []
        for index in lineGlyphRange.location..<NSMaxRange(lineGlyphRange) where !layoutManager.notShownAttribute(forGlyphAt: index) {
            let characterIndex = layoutManager.characterIndexForGlyph(at: index)
            let attributes = storage.attributes(at: characterIndex, effectiveRange: nil)
            guard let font = attributes[.font] as? NSFont else { return }
            var cgGlyph = layoutManager.cgGlyph(at: index)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &cgGlyph, &advance, 1)
            let character = string.character(at: characterIndex)
            glyphs.append(Glyph(
                index: index,
                advance: advance.width + ((attributes[.kern] as? CGFloat) ?? 0),
                isSpace: character == 0x20 || character == 0x0A || character == 0x2028
            ))
        }
        // Spaces at the end of the line hang outside it and don't take part.
        while glyphs.last?.isSpace == true {
            glyphs.removeLast()
        }
        guard let first = glyphs.first, let last = glyphs.last else { return }

        let start = layoutManager.location(forGlyphAt: first.index).x
        let justifiedEnd = layoutManager.location(forGlyphAt: last.index).x + last.advance
        let naturalWidth = glyphs.reduce(0) { $0 + $1.advance }
        let extra = justifiedEnd - start - naturalWidth
        // Lines TextKit didn't stretch, such as the last line of a paragraph, stay as they are.
        guard extra > 0.5 else { return }
        let spaces = glyphs.filter(\.isSpace).count
        let extraPerSpace = spaces > 0 ? extra / CGFloat(spaces) : 0

        var x = start
        for glyph in glyphs {
            let y = layoutManager.location(forGlyphAt: glyph.index).y
            layoutManager.setLocation(NSPoint(x: x, y: y), forStartOfGlyphRange: NSRange(location: glyph.index, length: 1))
            x += glyph.advance + (glyph.isSpace ? extraPerSpace : 0)
        }
    }
}

/// Like Word, a paragraph at the top of a page doesn't get its space before, except on the first page.
private final class PageTopSpacing: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager, paragraphSpacingBeforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect
    ) -> CGFloat {
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard let storage = layoutManager.textStorage, characterIndex < storage.length,
              let style = storage.attribute(.paragraphStyle, at: characterIndex, effectiveRange: nil) as? NSParagraphStyle
        else { return 0 }
        // Below the near-zero line of a page break paragraph still counts as the top.
        let isPageTop = rect.minY < 1 && characterIndex > 0
        return isPageTop && style.textBlocks.isEmpty ? 0 : style.paragraphSpacingBefore
    }
}

enum DrawingRenderer {
    /// Draws into a flipped context: the origin of `rect` is its top left corner.
    static func draw(_ drawing: Drawing, in rect: CGRect, context: CGContext) {
        if let fill = drawing.fill {
            context.setFillColor(fill.cgColor)
            context.fill(rect)
        }

        switch drawing.content {
        case .image(let image):
            context.saveGState()
            context.interpolationQuality = .high
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        case .text(let text, let insets):
            let frame = CGRect(
                x: rect.minX + insets.left, y: rect.minY + insets.top,
                width: max(rect.width - insets.left - insets.right, 1), height: max(rect.height - insets.top - insets.bottom, 1)
            )
            TextStory(text, width: frame.width).draw(at: frame.origin, clippedTo: rect)
        case .unsupported:
            // A faint frame instead of silently leaving a hole where a picture was.
            context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
            context.setLineWidth(0.5)
            context.stroke(rect.insetBy(dx: 0.25, dy: 0.25))
        }

        if let outline = drawing.outline {
            context.setStrokeColor(outline.color.cgColor)
            context.setLineWidth(outline.width)
            context.stroke(rect)
        }
    }
}

/// A separate piece of text laid out in a fixed width: a header, a footer or the inside of a text box.
struct TextStory {
    let layoutManager = DocxLayoutManager()
    let container: NSTextContainer
    private let storage: NSTextStorage

    init(_ text: NSAttributedString, width: CGFloat) {
        storage = NSTextStorage(attributedString: text)
        container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    /// Height of the lines, without the empty line TextKit adds after a final paragraph break.
    var height: CGFloat {
        let glyphs = layoutManager.glyphRange(for: container)
        guard glyphs.length > 0 else { return 0 }
        return layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil).maxY
    }

    var glyphRange: NSRange {
        layoutManager.glyphRange(for: container)
    }

    /// Draws into the current flipped graphics context.
    func draw(at origin: CGPoint, clippedTo clip: CGRect? = nil) {
        let context = NSGraphicsContext.current?.cgContext
        if let clip {
            context?.saveGState()
            context?.clip(to: clip)
        }
        let range = glyphRange
        layoutManager.drawBackground(forGlyphRange: range, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
        if clip != nil {
            context?.restoreGState()
        }
    }
}
