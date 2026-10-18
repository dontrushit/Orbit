import AppKit

/// Office Math (OMML), written out in linear form: "(a+b)/c", raised exponents, lowered indices.
extension DocumentBuilder {
    private struct MathStyle {
        var properties: RunProperties
        var scale: CGFloat = 1
        var baselineOffset: CGFloat = 0

        /// Superscripts and subscripts: smaller, and shifted from the current baseline.
        func script(raised: Bool) -> MathStyle {
            let size = (properties.size ?? 10) * scale
            var style = self
            style.scale *= 0.7
            style.baselineOffset += raised ? size * 0.4 : -size * 0.2
            return style
        }
    }

    func appendMath(_ element: MarkupElement, state: InlineState, to content: inout ParagraphContent) {
        var properties = state.base
        properties.asciiFont = .named("Cambria Math")
        properties.otherFont = .named("Cambria Math")
        let style = MathStyle(properties: properties)

        if element.is("oMathPara", in: .math) {
            content.isDisplayMath = true
            for (index, equation) in element.children("oMath", in: .math).enumerated() {
                if index > 0 {
                    content.text.append(mathText("\u{2028}", style: style, italic: false))
                }
                content.text.append(math(equation.children, style: style))
            }
        } else {
            content.text.append(math(element.children, style: style))
        }
    }

    private func math(_ elements: [MarkupElement], style: MathStyle) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for element in elements where element.namespace == .math {
            result.append(math(element, style: style))
        }
        return result
    }

    private func math(_ element: MarkupElement, style: MathStyle) -> NSAttributedString {
        func part(_ name: String, _ partStyle: MathStyle? = nil) -> NSMutableAttributedString {
            math(element.child(name, in: .math)?.children ?? [], style: partStyle ?? style)
        }
        func property(_ name: String) -> String? {
            element.children.first { $0.name.hasSuffix("Pr") && $0.namespace == .math }?
                .child(name, in: .math)?.attribute("val", in: .math)
        }
        func isHidden(_ name: String) -> Bool {
            property(name).map(MarkupElement.isOn) ?? false
        }
        func joined(_ parts: NSAttributedString...) -> NSMutableAttributedString {
            let result = NSMutableAttributedString()
            parts.forEach(result.append)
            return result
        }
        func text(_ string: String) -> NSAttributedString {
            mathText(string, style: style, italic: false)
        }

        switch element.name {
        case "r":
            var properties = style.properties
            properties.apply(RunProperties(xml: element.child("rPr")))
            var runStyle = style
            runStyle.properties = properties
            let mathProperties = element.child("rPr", in: .math)
            let isPlain = mathProperties?.child("sty", in: .math)?.attribute("val", in: .math) == "p"
                || mathProperties?.child("nor", in: .math) != nil
            let string = element.children("t", in: .math).map(\.text).joined()
            return mathText(string, style: runStyle, italic: !isPlain)
        case "f":
            return joined(Self.grouped(part("num")), text("/"), Self.grouped(part("den")))
        case "sSup":
            return joined(part("e"), part("sup", style.script(raised: true)))
        case "sSub":
            return joined(part("e"), part("sub", style.script(raised: false)))
        case "sSubSup":
            return joined(part("e"), part("sub", style.script(raised: false)), part("sup", style.script(raised: true)))
        case "sPre":
            return joined(part("sub", style.script(raised: false)), part("sup", style.script(raised: true)), part("e"))
        case "rad":
            let degree = isHidden("degHide") ? NSAttributedString() : part("deg", style.script(raised: true))
            return joined(degree, text("√"), Self.grouped(part("e")))
        case "nary":
            let symbol = property("chr") ?? "∫"
            let lower = isHidden("subHide") ? NSAttributedString() : part("sub", style.script(raised: false))
            let upper = isHidden("supHide") ? NSAttributedString() : part("sup", style.script(raised: true))
            return joined(text(symbol), lower, upper, part("e"))
        case "d":
            let opening = property("begChr") ?? "("
            let separator = property("sepChr") ?? "|"
            let closing = property("endChr") ?? ")"
            let items = element.children("e", in: .math).map { math($0.children, style: style) }
            let result = joined(text(opening))
            for (index, item) in items.enumerated() {
                if index > 0 { result.append(text(separator)) }
                result.append(item)
            }
            result.append(text(closing))
            return result
        case "func":
            return joined(part("fName"), text("\u{2009}"), part("e"))
        case "acc":
            return Self.combining(part("e"), with: property("chr") ?? "\u{0302}")
        case "bar":
            return Self.combining(part("e"), with: "\u{0305}")
        case "limLow":
            return joined(part("e"), part("lim", style.script(raised: false)))
        case "limUpp":
            return joined(part("e"), part("lim", style.script(raised: true)))
        case "eqArr":
            let result = NSMutableAttributedString()
            for (index, row) in element.children("e", in: .math).enumerated() {
                if index > 0 { result.append(text("\u{2028}")) }
                result.append(math(row.children, style: style))
            }
            return result
        case "m":
            let result = NSMutableAttributedString()
            for (index, row) in element.children("mr", in: .math).enumerated() {
                if index > 0 { result.append(text("; ")) }
                for (column, cell) in row.children("e", in: .math).enumerated() {
                    if column > 0 { result.append(text("  ")) }
                    result.append(math(cell.children, style: style))
                }
            }
            return result
        default:
            // Containers (e, num, den, box, groupChr, …) and unknown structures show their content.
            return math(element.children, style: style)
        }
    }

    private func mathText(_ string: String, style: MathStyle, italic: Bool) -> NSAttributedString {
        let text = italic ? Self.mathItalic(string) : string
        var attributes = styler.attributes(for: style.properties, text: text, scale: style.scale)
        if style.baselineOffset != 0 {
            attributes[.baselineOffset] = ((attributes[.baselineOffset] as? CGFloat) ?? 0) + style.baselineOffset
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Parentheses around anything longer than one character, so "a+b/c" reads as Word shows it.
    private static func grouped(_ string: NSMutableAttributedString) -> NSAttributedString {
        guard string.length > 1 else { return string }
        let attributes = string.attributes(at: 0, effectiveRange: nil)
        string.insert(NSAttributedString(string: "(", attributes: attributes), at: 0)
        string.append(NSAttributedString(string: ")", attributes: attributes))
        return string
    }

    private static func combining(_ string: NSMutableAttributedString, with mark: String) -> NSAttributedString {
        guard string.length > 0 else { return string }
        string.append(NSAttributedString(string: mark, attributes: string.attributes(at: string.length - 1, effectiveRange: nil)))
        return string
    }

    /// Latin letters as Mathematical Italic characters, the way Word sets variables.
    static func mathItalic(_ string: String) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.map { scalar -> UnicodeScalar in
            switch scalar.value {
            case 0x68: return UnicodeScalar(0x210E)! // italic h has its own code point
            case 0x41...0x5A: return UnicodeScalar(0x1D434 + scalar.value - 0x41) ?? scalar
            case 0x61...0x7A: return UnicodeScalar(0x1D44E + scalar.value - 0x61) ?? scalar
            default: return scalar
            }
        }))
    }
}
