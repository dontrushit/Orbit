import Foundation

/// Fonts and colors of the document theme, referenced by styles instead of concrete values.
struct DocxTheme {
    var majorFont: String?
    var minorFont: String?
    private var colors: [String: RGBColor] = [:]

    init(xml: MarkupElement?) {
        guard let elements = xml?.child("themeElements", in: .a) else { return }

        let fonts = elements.child("fontScheme", in: .a)
        majorFont = fonts?.child("majorFont", in: .a)?.child("latin", in: .a)?.attribute("typeface", in: .none)
        minorFont = fonts?.child("minorFont", in: .a)?.child("latin", in: .a)?.attribute("typeface", in: .none)

        for color in elements.child("clrScheme", in: .a)?.children ?? [] {
            let value = color.child("srgbClr", in: .a)?.attribute("val", in: .none)
                ?? color.child("sysClr", in: .a)?.attribute("lastClr", in: .none)
            colors[color.name] = RGBColor(hex: value)
        }
    }

    /// A DrawingML scheme color such as "accent1" or "tx1".
    func color(named name: String) -> RGBColor? {
        let aliases = ["tx1": "dk1", "bg1": "lt1", "tx2": "dk2", "bg2": "lt2"]
        return colors[aliases[name] ?? name]
    }
}

/// How fonts of the document are classified, used to pick a similar font when one isn't installed.
struct FontTable {
    enum Kind {
        case serif, sansSerif, monospace
    }

    private var kinds: [String: Kind] = [:]

    init(xml: MarkupElement?) {
        for font in xml?.children("font") ?? [] {
            guard let name = font.attribute("name") else { continue }
            if font.value(of: "pitch") == "fixed" || font.value(of: "family") == "modern" {
                kinds[name] = .monospace
            } else if font.value(of: "family") == "swiss" {
                kinds[name] = .sansSerif
            } else if font.value(of: "family") == "roman" {
                kinds[name] = .serif
            }
        }
    }

    func kind(of name: String) -> Kind? {
        kinds[name]
    }
}

/// Document-wide settings from settings.xml.
struct DocumentSettings {
    /// Interval of the tab stops that aren't set explicitly.
    var defaultTabStop: CGFloat = 36
    /// Even pages use the "even" headers and footers.
    var evenAndOddHeaders = false

    init(xml: MarkupElement?) {
        guard let xml else { return }
        if let interval = Measure.twips(xml.value(of: "defaultTabStop")), interval > 0 {
            defaultTabStop = interval
        }
        evenAndOddHeaders = xml.flag("evenAndOddHeaders") ?? false
    }
}

/// Title and author for the PDF's document info.
struct DocumentMetadata {
    var title: String?
    var author: String?

    init(xml: MarkupElement?) {
        func text(_ name: String, _ namespace: MarkupNamespace) -> String? {
            let value = xml?.child(name, in: namespace)?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        title = text("title", .dublinCore)
        author = text("creator", .dublinCore)
    }
}
