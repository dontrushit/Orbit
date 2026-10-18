import AppKit

/// Turns resolved WordprocessingML formatting into TextKit attributes.
struct TextStyler {
    let fonts: FontResolver
    let theme: DocxTheme
    let settings: DocumentSettings

    /// The text's language, which TextKit uses for language-specific line breaking.
    static let languageKey = NSAttributedString.Key(kCTLanguageAttributeName as String)

    /// Superscript and subscript text is this much smaller than the run's size.
    static let scriptScale: CGFloat = 0.65

    func family(for run: RunProperties, text: String) -> String {
        let isASCII = text.unicodeScalars.allSatisfy(\.isASCII)
        let reference = isASCII ? run.asciiFont ?? run.otherFont : run.otherFont ?? run.asciiFont
        switch reference {
        case .named(let name): return name
        case .theme(let major): return (major ? theme.majorFont : theme.minorFont) ?? "Times New Roman"
        case nil: return "Times New Roman"
        }
    }

    /// - Parameter scale: Extra scaling of the font size, used for small capitals.
    func attributes(for run: RunProperties, text: String, scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        var size = (run.size ?? 10) * scale
        var baselineOffset = run.position ?? 0
        switch run.verticalAlignment {
        case .superscript:
            baselineOffset += size / 3
            size *= Self.scriptScale
        case .subscript:
            baselineOffset -= size / 7
            size *= Self.scriptScale
        case .baseline, nil:
            break
        }

        let font = fonts.font(family: family(for: run, text: text), size: max(size, 1), bold: run.bold ?? false, italic: run.italic ?? false)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font.font,
            .foregroundColor: (run.color ?? .black).nsColor,
        ]
        if font.needsSyntheticBold {
            // A negative width fills and strokes the glyphs, thickening them.
            attributes[.strokeWidth] = -3.0
        }
        if font.needsSyntheticItalic {
            attributes[.obliqueness] = 0.2
        }
        if baselineOffset != 0 {
            attributes[.baselineOffset] = baselineOffset
        }
        // A fixed kern turns font kerning off, which matches Word unless the document asks for kerning.
        let usesFontKerning = run.kerningThreshold.map { $0 > 0 && size >= $0 } ?? false
        if let spacing = run.characterSpacing, spacing != 0 {
            attributes[.kern] = spacing
        } else if !usesFontKerning {
            attributes[.kern] = 0
        }
        if let underline = run.underline, underline != .none {
            attributes[.underlineStyle] = Self.underlineStyle(underline).rawValue
            if let color = run.underlineColor {
                attributes[.underlineColor] = color.nsColor
            }
        }
        if run.doubleStrike == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.double.rawValue
        } else if run.strike == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let background = run.highlight?.color ?? run.shading?.color {
            attributes[.backgroundColor] = background.nsColor
        }
        if let language = run.language {
            attributes[Self.languageKey] = language
        }
        return attributes
    }

    private static func underlineStyle(_ underline: RunProperties.Underline) -> NSUnderlineStyle {
        switch underline {
        case .none: []
        case .single, .wavy: .single
        case .double: .double
        case .thick: .thick
        case .dotted: [.single, .patternDot]
        case .dashed: [.single, .patternDash]
        }
    }

    /// - Parameters:
    ///   - blocks: Table cells around the paragraph, outermost first.
    ///   - singleLineHeight: Word's single line height for the paragraph's largest font; see `singleLineHeight(of:)`.
    func paragraphStyle(for paragraph: ParagraphProperties, blocks: [NSTextBlock], singleLineHeight: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch paragraph.alignment {
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        case .justified: style.alignment = .justified
        case .left, nil: style.alignment = .left
        }

        // TextKit can't draw outside the text container, so text indented into the margin starts at the margin.
        let left = max(paragraph.indentLeft ?? 0, 0)
        let firstLine = max(left + (paragraph.indentFirstLine ?? 0), 0)
        style.headIndent = left
        style.firstLineHeadIndent = firstLine
        if let right = paragraph.indentRight, right > 0 {
            style.tailIndent = -right
        }

        style.paragraphSpacingBefore = max(paragraph.spacingBefore ?? 0, 0)
        style.paragraphSpacing = max(paragraph.spacingAfter ?? 0, 0)
        switch paragraph.lineSpacing ?? .auto(1) {
        case .auto(let multiple) where multiple > 0:
            // TextKit leaves out the font's line gap, which Word counts: without it every line is about 3% shorter.
            // Word adds the extra space of 1.5 or double spacing below the text, as TextKit's line spacing does.
            style.minimumLineHeight = singleLineHeight
            if multiple > 1 {
                style.lineSpacing = singleLineHeight * (multiple - 1)
            } else if multiple < 1 {
                style.minimumLineHeight = singleLineHeight * multiple
                style.maximumLineHeight = singleLineHeight * multiple
            }
        case .exact(let height) where height > 0:
            style.minimumLineHeight = height
            style.maximumLineHeight = height
        case .atLeast(let height) where height > 0:
            style.minimumLineHeight = height
        default:
            break
        }

        var stops = paragraph.resolvedTabs.map(Self.textTab)
        // A hanging indent is an implicit tab stop: list labels end there and the text starts at the indent.
        if firstLine < left, !stops.contains(where: { $0.location > firstLine && $0.location <= left }) {
            stops.append(NSTextTab(textAlignment: .left, location: left))
            stops.sort { $0.location < $1.location }
        }
        style.tabStops = stops
        style.defaultTabInterval = settings.defaultTabStop
        style.textBlocks = blocks
        // Word's automatic hyphenation isn't reproduced: where it hyphenates depends on the proofing tools
        // installed with Word, and lines broken differently would move text across pages.
        return style
    }

    /// Word's single line spacing: the largest font's ascent, descent and line gap.
    static func singleLineHeight(of text: NSAttributedString) -> CGFloat {
        var height: CGFloat = 0
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? NSFont, text.attribute(.attachment, at: range.location, effectiveRange: nil) == nil else { return }
            let ctFont = font as CTFont
            height = max(height, CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        }
        return height
    }

    private static func textTab(_ stop: TabStop) -> NSTextTab {
        switch stop.alignment {
        case .center:
            NSTextTab(textAlignment: .center, location: stop.position)
        case .right:
            NSTextTab(textAlignment: .right, location: stop.position)
        case .decimal:
            NSTextTab(textAlignment: .right, location: stop.position, options: [.columnTerminators: CharacterSet(charactersIn: ".,")])
        case .left, .clear:
            NSTextTab(textAlignment: .left, location: stop.position)
        }
    }

    /// Leaders to draw for the paragraph's tabs, or `nil` if none of its stops has one.
    static func tabLeaders(for paragraph: ParagraphProperties) -> TabLeaders? {
        let stops = paragraph.resolvedTabs
        guard stops.contains(where: { $0.leader != .none }) else { return nil }
        return TabLeaders(stops: stops.map { ($0.position, $0.leader) })
    }

    /// Makes a paragraph nearly zero high. Not zero: TextKit treats a zero maximum as no limit.
    static func collapse(_ style: NSMutableParagraphStyle) {
        style.minimumLineHeight = 0.001
        style.maximumLineHeight = 0.001
        style.lineSpacing = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
    }

    /// A paragraph of nearly zero height holding a page break. A break inside a paragraph would make
    /// TextKit treat the text after it as a continuation line and drop the first-line indent.
    static func pageBreakParagraph(_ kind: PageBreak) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        collapse(style)
        let paragraph = NSMutableAttributedString(string: "\u{0C}\n", attributes: [
            .font: NSFont.systemFont(ofSize: 1),
            .paragraphStyle: style,
        ])
        paragraph.addAttribute(.docxPageBreak, value: kind, range: NSRange(location: 0, length: 1))
        return paragraph
    }
}
