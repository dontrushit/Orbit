import AppKit

/// Formatting and link that apply to inline content at the current point of a paragraph.
struct InlineState {
    enum Link {
        case url(URL)
        case bookmark(String)
    }

    /// Run formatting of the paragraph, before character styles and direct formatting.
    var base: RunProperties
    var link: Link?
}

/// A field whose begin has been read: `{ PAGE }`, `{ HYPERLINK "…" }`, `{ PAGEREF _Toc… }`.
final class OpenField {
    enum Phase {
        case instruction, result
    }

    var instruction = ""
    /// The field type, known once the instruction is complete: "PAGE", "TOC", "HYPERLINK", …
    var name = ""
    var phase = Phase.instruction
    /// The field shows a live value instead of the result cached in the file.
    var replacesResult = false
    var link: InlineState.Link?
    var placeholder: FieldPlaceholder?
}

extension DocumentBuilder {
    func appendInline(_ elements: [MarkupElement], state: InlineState, to content: inout ParagraphContent, story: Story, context: BlockContext) {
        for element in elements {
            switch element.namespace {
            case .w:
                appendInlineElement(element, state: state, to: &content, story: story, context: context)
            case .math where element.name == "oMath" || element.name == "oMathPara":
                appendMath(element, state: state, to: &content)
            case .markupCompatibility where element.name == "AlternateContent":
                appendInline(Self.chosenAlternative(element), state: state, to: &content, story: story, context: context)
            default:
                break
            }
        }
    }

    private func appendInlineElement(_ element: MarkupElement, state: InlineState, to content: inout ParagraphContent, story: Story, context: BlockContext) {
        switch element.name {
        case "r":
            appendRun(element, state: state, to: &content, story: story, context: context)
        case "hyperlink":
            var linked = state
            if let id = element.attribute("id", in: .r), let target = story.relationships[id], target.isExternal, let url = URL(string: target.target) {
                linked.link = .url(url)
            } else if let anchor = element.attribute("anchor") {
                linked.link = .bookmark(anchor)
            }
            appendInline(element.children, state: linked, to: &content, story: story, context: context)
        case "fldSimple":
            beginField()
            openFields.last?.instruction = element.attribute("instr") ?? ""
            separateField(properties: state.base, story: story, to: &content)
            appendInline(element.children, state: state, to: &content, story: story, context: context)
            endField(properties: state.base, story: story, to: &content)
        case "ins", "moveTo", "smartTag", "customXml", "dir", "bdo":
            appendInline(element.children, state: state, to: &content, story: story, context: context)
        case "sdt":
            appendInline(element.child("sdtContent")?.children ?? [], state: state, to: &content, story: story, context: context)
        case "bookmarkStart":
            addBookmark(element)
        default:
            // Deleted text, comments, proofing marks and permissions don't show on the page.
            break
        }
    }

    // MARK: Runs

    private func appendRun(_ run: MarkupElement, state: InlineState, to content: inout ParagraphContent, story: Story, context: BlockContext) {
        let direct = RunProperties(xml: run.child("rPr"))
        var properties = state.base
        // Word shows table of contents entries in the TOC styles, without the blue of their Hyperlink style.
        if let characterStyle = direct.characterStyleID,
           !(styles.name(ofStyle: characterStyle) == "Hyperlink" && openFields.contains { $0.name == "TOC" }) {
            properties.apply(styles.characterStyle(characterStyle))
        }
        properties.apply(direct)
        appendRunContent(run.children, properties: properties, state: state, to: &content, story: story, context: context)
    }

    private func appendRunContent(
        _ elements: [MarkupElement], properties: RunProperties, state: InlineState,
        to content: inout ParagraphContent, story: Story, context: BlockContext
    ) {
        for element in elements {
            if element.is("AlternateContent", in: .markupCompatibility) {
                appendRunContent(Self.chosenAlternative(element), properties: properties, state: state, to: &content, story: story, context: context)
                continue
            }
            guard element.namespace == .w else { continue }

            // Field structure is read even in hidden runs; only the visible result is added.
            switch element.name {
            case "fldChar":
                switch element.attribute("fldCharType") {
                case "begin": beginField()
                case "separate": separateField(properties: properties, story: story, to: &content)
                case "end": endField(properties: properties, story: story, to: &content)
                default: break
                }
                continue
            case "instrText":
                if let field = openFields.last, field.phase == .instruction {
                    field.instruction += element.text
                }
                continue
            default:
                break
            }
            guard isVisible(properties) else { continue }

            switch element.name {
            case "t":
                appendText(element.text, properties: properties, state: state, to: &content)
            case "tab", "ptab":
                appendText("\t", properties: properties, state: state, to: &content)
            case "br":
                switch element.attribute("type") {
                case "page", "column": content.pageBreaks.append(content.text.length)
                default: appendText("\u{2028}", properties: properties, state: state, to: &content)
                }
            case "cr":
                appendText("\u{2028}", properties: properties, state: state, to: &content)
            case "noBreakHyphen":
                appendText("\u{2011}", properties: properties, state: state, to: &content)
            case "softHyphen":
                appendText("\u{00AD}", properties: properties, state: state, to: &content)
            case "sym":
                appendSymbol(element, properties: properties, state: state, to: &content)
            case "drawing":
                appendDrawing(element, properties: properties, to: &content, story: story, context: context)
            case "pict", "object":
                appendVML(element, properties: properties, to: &content, story: story, context: context)
            case "footnoteReference", "endnoteReference":
                let kind: NoteCollector.Kind = element.name == "footnoteReference" ? .footnote : .endnote
                if let id = element.attribute("id"), let label = notes.reference(kind, id: id) {
                    appendText(label, properties: properties, state: state, to: &content)
                }
            case "footnoteRef", "endnoteRef":
                if let label = notes.currentLabel {
                    appendText(label, properties: properties, state: state, to: &content)
                }
            case "ruby":
                appendInline(element.child("rubyBase")?.children ?? [], state: state, to: &content, story: story, context: context)
            default:
                break
            }
        }
    }

    private func isVisible(_ properties: RunProperties) -> Bool {
        properties.hidden != true && openFields.allSatisfy { $0.phase == .result && !$0.replacesResult }
    }

    private func appendSymbol(_ element: MarkupElement, properties: RunProperties, state: InlineState, to content: inout ParagraphContent) {
        guard let code = element.attribute("char").flatMap({ UInt32($0, radix: 16) }), let scalar = UnicodeScalar(code) else { return }
        var symbol = properties
        if let font = element.attribute("font") {
            symbol.asciiFont = .named(font)
            symbol.otherFont = .named(font)
        }
        appendText(String(Character(scalar)), properties: symbol, state: state, to: &content)
    }

    // MARK: Text

    /// Adds text with the run's formatting, the link in effect and any bookmarks waiting for a character.
    func appendText(_ text: String, properties: RunProperties, state: InlineState? = nil, to content: inout ParagraphContent) {
        guard !text.isEmpty else { return }

        var properties = properties
        // Symbols and bullets set in a Windows symbol font.
        let resolved = SymbolFonts.resolve(text, font: styler.family(for: properties, text: text))
        let text = resolved.text
        if resolved.font == nil {
            // The Symbol characters are now Unicode, drawn in the document's regular font.
            properties.asciiFont = styles.defaultRun.asciiFont
            properties.otherFont = styles.defaultRun.otherFont
        }

        var extra: [NSAttributedString.Key: Any] = [:]
        if let link = openFields.last(where: { $0.link != nil })?.link ?? state?.link {
            switch link {
            case .url(let url): extra[.link] = url
            case .bookmark(let name): extra[.docxInternalLink] = name
            }
        }
        if let placeholder = openFields.last(where: { $0.placeholder != nil })?.placeholder {
            extra[.docxField] = placeholder
        }

        let start = content.text.length
        if properties.caps == true {
            append(text.uppercased(), properties: properties, scale: 1, extra: extra, to: &content)
        } else if properties.smallCaps == true {
            // Lowercase letters become smaller capitals.
            var segment = ""
            var isLower = false
            for character in text {
                let lower = character.isLowercase
                if lower != isLower, !segment.isEmpty {
                    append(isLower ? segment.uppercased() : segment, properties: properties, scale: isLower ? 0.8 : 1, extra: extra, to: &content)
                    segment = ""
                }
                isLower = lower
                segment.append(character)
            }
            append(isLower ? segment.uppercased() : segment, properties: properties, scale: isLower ? 0.8 : 1, extra: extra, to: &content)
        } else {
            append(text, properties: properties, scale: 1, extra: extra, to: &content)
        }

        if !pendingBookmarks.isEmpty, content.text.length > start {
            content.text.addAttribute(.docxBookmarks, value: pendingBookmarks, range: NSRange(location: start, length: 1))
            pendingBookmarks = []
        }
    }

    private func append(_ text: String, properties: RunProperties, scale: CGFloat, extra: [NSAttributedString.Key: Any], to content: inout ParagraphContent) {
        guard !text.isEmpty else { return }
        var attributes = styler.attributes(for: properties, text: text, scale: scale)
        attributes.merge(extra) { _, new in new }
        content.text.append(NSAttributedString(string: text, attributes: attributes))
    }

    // MARK: Fields

    private func beginField() {
        openFields.append(OpenField())
    }

    /// The instruction is complete: decide how the field shows.
    private func separateField(properties: RunProperties, story: Story, to content: inout ParagraphContent) {
        guard let field = openFields.last, field.phase == .instruction else { return }
        let parts = FieldInstruction(field.instruction)
        field.name = parts.name
        field.phase = .result
        switch parts.name {
        case "PAGE", "NUMPAGES", "SECTIONPAGES":
            guard story.hasLivePageFields else { break }
            // The renderer fills in the value for every page.
            let placeholder: FieldPlaceholder = switch parts.name {
            case "PAGE": .page
            case "NUMPAGES": .pageCount
            default: .sectionPageCount
            }
            var attributes = styler.attributes(for: properties, text: "0")
            attributes[.docxField] = placeholder
            content.text.append(NSAttributedString(string: "0", attributes: attributes))
            field.replacesResult = true
        case "HYPERLINK":
            if parts.switches.contains("l"), let anchor = parts.arguments.first {
                field.link = .bookmark(anchor)
            } else if let target = parts.arguments.first, let url = URL(string: target) {
                field.link = .url(url)
            }
        case "PAGEREF":
            if let bookmark = parts.arguments.first {
                field.placeholder = .pageReference(bookmark)
                if parts.switches.contains("h") {
                    field.link = .bookmark(bookmark)
                }
            }
        default:
            break
        }
    }

    private func endField(properties: RunProperties, story: Story, to content: inout ParagraphContent) {
        guard let field = openFields.last else { return }
        // A field without a separator has no cached result; live page fields still need their value.
        if field.phase == .instruction {
            separateField(properties: properties, story: story, to: &content)
        }
        openFields.removeLast()
    }
}

/// A field instruction split into its name, quoted or plain arguments and switches: `PAGEREF _Toc123 \h`.
struct FieldInstruction {
    let name: String
    let arguments: [String]
    /// Switch letters without the backslash.
    let switches: Set<String>

    init(_ instruction: String) {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        for character in instruction {
            if character == "\"" {
                if isQuoted {
                    tokens.append(current)
                    current = ""
                }
                isQuoted.toggle()
            } else if character.isWhitespace, !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        name = tokens.first?.uppercased() ?? ""
        var arguments: [String] = []
        var switches: Set<String> = []
        for token in tokens.dropFirst() {
            if token.hasPrefix("\\") {
                switches.insert(String(token.dropFirst()).lowercased())
            } else {
                arguments.append(token)
            }
        }
        self.arguments = arguments
        self.switches = switches
    }
}
