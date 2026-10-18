import Foundation

// Formatting as WordprocessingML defines it. Every field is optional: `nil` means "inherit",
// and `apply(_:)` layers more specific formatting (a style, then direct formatting) on top.

/// A background: explicitly none, which cancels an inherited one, or a color.
enum Fill: Equatable {
    case none
    case color(RGBColor)

    /// `w:shd`. A solid pattern takes the foreground color; other patterns are approximated by the fill.
    init?(shading element: MarkupElement?) {
        guard let element else { return nil }
        let hex = element.attribute("val") == "solid" ? element.attribute("color") : element.attribute("fill")
        self = RGBColor(hex: hex).map(Fill.color) ?? .none
    }

    var color: RGBColor? {
        if case .color(let color) = self { color } else { nil }
    }
}

struct RunProperties: Equatable {
    enum FontReference: Equatable {
        case named(String)
        case theme(major: Bool)
    }

    enum Underline: Equatable {
        case none, single, double, thick, dotted, dashed, wavy
    }

    enum VerticalAlignment: Equatable {
        case baseline, superscript, `subscript`
    }

    var characterStyleID: String?
    /// For ASCII text.
    var asciiFont: FontReference?
    /// For the rest: Cyrillic, accented Latin, Greek.
    var otherFont: FontReference?
    var size: CGFloat?
    var bold: Bool?
    var italic: Bool?
    var underline: Underline?
    var underlineColor: RGBColor?
    var strike: Bool?
    var doubleStrike: Bool?
    var caps: Bool?
    var smallCaps: Bool?
    var hidden: Bool?
    var color: RGBColor?
    var highlight: Fill?
    var shading: Fill?
    var verticalAlignment: VerticalAlignment?
    /// Extra space between characters, in points.
    var characterSpacing: CGFloat?
    /// Font kerning applies from this font size up; Word doesn't kern without it.
    var kerningThreshold: CGFloat?
    /// Language of the text, such as "ru-RU"; line breaking follows its rules.
    var language: String?
    /// Baseline shift, in points.
    var position: CGFloat?

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        characterStyleID = xml.value(of: "rStyle")

        if let fonts = xml.child("rFonts") {
            asciiFont = Self.font(fonts, name: "ascii", theme: "asciiTheme")
            otherFont = Self.font(fonts, name: "hAnsi", theme: "hAnsiTheme")
        }
        size = Measure.halfPoints(xml.value(of: "sz"))
        bold = xml.flag("b")
        italic = xml.flag("i")
        strike = xml.flag("strike")
        doubleStrike = xml.flag("dstrike")
        caps = xml.flag("caps")
        smallCaps = xml.flag("smallCaps")
        hidden = xml.flag("vanish")

        if let element = xml.child("u") {
            underline = Self.underline(element.attribute("val"))
            underlineColor = RGBColor(hex: element.attribute("color"))
        }
        if let element = xml.child("color") {
            // "auto" is black text on the white page.
            color = RGBColor(hex: element.attribute("val")) ?? .black
        }
        if let name = xml.value(of: "highlight") {
            highlight = RGBColor(highlight: name).map(Fill.color) ?? Fill.none
        }
        shading = Fill(shading: xml.child("shd"))

        switch xml.value(of: "vertAlign") {
        case "superscript": verticalAlignment = .superscript
        case "subscript": verticalAlignment = .subscript
        case "baseline": verticalAlignment = .baseline
        default: break
        }
        characterSpacing = Measure.twips(xml.value(of: "spacing"))
        kerningThreshold = Measure.halfPoints(xml.value(of: "kern"))
        language = xml.value(of: "lang")
        position = Measure.halfPoints(xml.value(of: "position"))
    }

    mutating func apply(_ other: RunProperties) {
        characterStyleID = other.characterStyleID ?? characterStyleID
        asciiFont = other.asciiFont ?? asciiFont
        otherFont = other.otherFont ?? otherFont
        size = other.size ?? size
        bold = other.bold ?? bold
        italic = other.italic ?? italic
        underline = other.underline ?? underline
        underlineColor = other.underlineColor ?? underlineColor
        strike = other.strike ?? strike
        doubleStrike = other.doubleStrike ?? doubleStrike
        caps = other.caps ?? caps
        smallCaps = other.smallCaps ?? smallCaps
        hidden = other.hidden ?? hidden
        color = other.color ?? color
        highlight = other.highlight ?? highlight
        shading = other.shading ?? shading
        verticalAlignment = other.verticalAlignment ?? verticalAlignment
        characterSpacing = other.characterSpacing ?? characterSpacing
        kerningThreshold = other.kerningThreshold ?? kerningThreshold
        language = other.language ?? language
        position = other.position ?? position
    }

    private static func font(_ element: MarkupElement, name: String, theme: String) -> FontReference? {
        if let theme = element.attribute(theme) {
            return .theme(major: theme.hasPrefix("major"))
        }
        return element.attribute(name).map(FontReference.named)
    }

    private static func underline(_ value: String?) -> Underline {
        switch value {
        case "none": .none
        case "double", "wavyDouble": .double
        case "thick": .thick
        case "dotted", "dottedHeavy": .dotted
        case "dash", "dashedHeavy", "dashLong", "dashLongHeavy", "dotDash", "dashDotHeavy", "dotDotDash", "dashDotDotHeavy": .dashed
        case "wave", "wavyHeavy": .wavy
        default: .single
        }
    }
}

struct TabStop: Equatable {
    enum Alignment: Equatable {
        case left, center, right, decimal
        /// Removes an inherited stop at this position.
        case clear
    }

    enum Leader: Equatable {
        case none, dot, hyphen, underscore, middleDot
    }

    var position: CGFloat
    var alignment: Alignment
    var leader: Leader

    init(position: CGFloat, alignment: Alignment, leader: Leader = .none) {
        self.position = position
        self.alignment = alignment
        self.leader = leader
    }

    init?(xml: MarkupElement) {
        guard let position = Measure.twips(xml.attribute("pos")) else { return nil }
        self.position = position
        switch xml.attribute("val") {
        case "center": alignment = .center
        case "right", "end": alignment = .right
        case "decimal": alignment = .decimal
        case "clear": alignment = .clear
        // "bar" draws a vertical line instead of aligning text; treating it as a left stop keeps the text in place.
        default: alignment = .left
        }
        switch xml.attribute("leader") {
        case "dot": leader = .dot
        case "hyphen": leader = .hyphen
        case "underscore", "heavy": leader = .underscore
        case "middleDot": leader = .middleDot
        default: leader = .none
        }
    }
}

struct ParagraphProperties: Equatable {
    enum Alignment: Equatable {
        case left, center, right, justified
    }

    enum LineSpacing: Equatable {
        /// A multiple of single spacing.
        case auto(CGFloat)
        case exact(CGFloat)
        case atLeast(CGFloat)
    }

    var styleID: String?
    var alignment: Alignment?
    var indentLeft: CGFloat?
    var indentRight: CGFloat?
    /// Positive for a first-line indent, negative for a hanging one.
    var indentFirstLine: CGFloat?
    var spacingBefore: CGFloat?
    var spacingAfter: CGFloat?
    var lineSpacing: LineSpacing?
    /// No spacing between paragraphs of the same style.
    var contextualSpacing: Bool?
    var pageBreakBefore: Bool?
    /// Keep on the same page as the next paragraph, as headings do.
    var keepWithNext: Bool?
    /// Don't leave a single line of the paragraph alone at the bottom or top of a page.
    var widowControl: Bool?
    var numberingID: String?
    var numberingLevel: Int?
    /// In inheritance order; later stops replace or clear earlier ones at the same position.
    var tabs: [TabStop] = []

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        styleID = xml.value(of: "pStyle")

        switch xml.value(of: "jc") {
        case "center": alignment = .center
        case "right", "end": alignment = .right
        case "both", "distribute", "lowKashida", "mediumKashida", "highKashida", "thaiDistribute": alignment = .justified
        case "left", "start": alignment = .left
        default: break
        }

        if let indent = xml.child("ind") {
            indentLeft = Measure.twips(indent.attribute("left") ?? indent.attribute("start"))
            indentRight = Measure.twips(indent.attribute("right") ?? indent.attribute("end"))
            if let hanging = Measure.twips(indent.attribute("hanging")) {
                indentFirstLine = -hanging
            } else {
                indentFirstLine = Measure.twips(indent.attribute("firstLine"))
            }
        }

        if let spacing = xml.child("spacing") {
            // Automatic spacing is what Word uses for HTML-like documents: 14 pt.
            func isAuto(_ name: String) -> Bool { spacing.attribute(name).map(MarkupElement.isOn) ?? false }
            spacingBefore = isAuto("beforeAutospacing") ? 14 : Measure.twips(spacing.attribute("before"))
            spacingAfter = isAuto("afterAutospacing") ? 14 : Measure.twips(spacing.attribute("after"))
            if let line = spacing.attribute("line").flatMap(Double.init) {
                switch spacing.attribute("lineRule") {
                case "exact": lineSpacing = .exact(CGFloat(line) / 20)
                case "atLeast": lineSpacing = .atLeast(CGFloat(line) / 20)
                default: lineSpacing = .auto(CGFloat(line) / 240)
                }
            }
        }

        contextualSpacing = xml.flag("contextualSpacing")
        pageBreakBefore = xml.flag("pageBreakBefore")
        keepWithNext = xml.flag("keepNext")
        widowControl = xml.flag("widowControl")

        if let numbering = xml.child("numPr") {
            numberingID = numbering.value(of: "numId")
            numberingLevel = numbering.value(of: "ilvl").flatMap(Int.init)
        }
        tabs = xml.child("tabs")?.children("tab").compactMap(TabStop.init(xml:)) ?? []
    }

    mutating func apply(_ other: ParagraphProperties) {
        styleID = other.styleID ?? styleID
        alignment = other.alignment ?? alignment
        indentLeft = other.indentLeft ?? indentLeft
        indentRight = other.indentRight ?? indentRight
        indentFirstLine = other.indentFirstLine ?? indentFirstLine
        spacingBefore = other.spacingBefore ?? spacingBefore
        spacingAfter = other.spacingAfter ?? spacingAfter
        lineSpacing = other.lineSpacing ?? lineSpacing
        contextualSpacing = other.contextualSpacing ?? contextualSpacing
        pageBreakBefore = other.pageBreakBefore ?? pageBreakBefore
        keepWithNext = other.keepWithNext ?? keepWithNext
        widowControl = other.widowControl ?? widowControl
        numberingID = other.numberingID ?? numberingID
        numberingLevel = other.numberingLevel ?? numberingLevel
        tabs += other.tabs
    }

    /// Effective tab stops, sorted by position.
    var resolvedTabs: [TabStop] {
        var stops: [TabStop] = []
        for tab in tabs {
            stops.removeAll { abs($0.position - tab.position) < 0.5 }
            if tab.alignment != .clear {
                stops.append(tab)
            }
        }
        return stops.sorted { $0.position < $1.position }
    }
}

// MARK: Tables

struct Border: Equatable {
    var width: CGFloat
    var color: RGBColor

    /// `nil` for "none"/"nil", which hide an inherited border.
    init?(xml: MarkupElement) {
        guard let style = xml.attribute("val"), style != "none", style != "nil" else { return nil }
        // Word draws hairline borders even for size 0, and double lines take up three widths.
        let width = max(Measure.eighthPoints(xml.attribute("sz")) ?? 0.5, 0.25)
        self.width = style == "double" ? width * 3 : width
        color = RGBColor(hex: xml.attribute("color")) ?? .black
    }
}

/// An edge is `nil` when not set, `.some(nil)` when explicitly hidden.
struct Borders: Equatable {
    var top: Border??
    var left: Border??
    var bottom: Border??
    var right: Border??
    var insideHorizontal: Border??
    var insideVertical: Border??

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        func edge(_ names: String...) -> Border?? {
            guard let element = names.lazy.compactMap({ xml.child($0) }).first else { return nil }
            return .some(Border(xml: element))
        }
        top = edge("top")
        left = edge("left", "start")
        bottom = edge("bottom")
        right = edge("right", "end")
        insideHorizontal = edge("insideH")
        insideVertical = edge("insideV")
    }

    mutating func apply(_ other: Borders) {
        top = other.top ?? top
        left = other.left ?? left
        bottom = other.bottom ?? bottom
        right = other.right ?? right
        insideHorizontal = other.insideHorizontal ?? insideHorizontal
        insideVertical = other.insideVertical ?? insideVertical
    }
}

struct CellMargins: Equatable {
    var top: CGFloat?
    var left: CGFloat?
    var bottom: CGFloat?
    var right: CGFloat?

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        func margin(_ names: String...) -> CGFloat? {
            names.lazy.compactMap { xml.child($0) }.first.flatMap { Measure.twips($0.attribute("w")) }
        }
        top = margin("top")
        left = margin("left", "start")
        bottom = margin("bottom")
        right = margin("right", "end")
    }

    mutating func apply(_ other: CellMargins) {
        top = other.top ?? top
        left = other.left ?? left
        bottom = other.bottom ?? bottom
        right = other.right ?? right
    }
}

enum TableWidth: Equatable {
    case points(CGFloat)
    /// Fraction of the available width, 0...1.
    case fraction(CGFloat)
    case auto

    init?(xml: MarkupElement?) {
        guard let xml else { return nil }
        let value = xml.attribute("w") ?? "0"
        switch xml.attribute("type") {
        case "pct":
            // Either fiftieths of a percent or an explicit "50%".
            if value.hasSuffix("%") {
                guard let percent = Double(value.dropLast()) else { return nil }
                self = .fraction(CGFloat(percent) / 100)
            } else {
                guard let fiftieths = Double(value) else { return nil }
                self = .fraction(CGFloat(fiftieths) / 5000)
            }
        case "auto", "nil":
            self = .auto
        default:
            guard let points = Measure.twips(value), points > 0 else { return nil }
            self = .points(points)
        }
    }
}

struct TableProperties: Equatable {
    enum Alignment: Equatable {
        case left, center, right
    }

    /// Which conditional formats of the table style apply (`w:tblLook`).
    struct Look: Equatable {
        var firstRow = true
        var lastRow = false
        var firstColumn = true
        var lastColumn = false
        var horizontalBands = true
        var verticalBands = false

        init() {}

        init(xml: MarkupElement) {
            if let hex = xml.attribute("val"), let bits = Int(hex, radix: 16) {
                firstRow = bits & 0x0020 != 0
                lastRow = bits & 0x0040 != 0
                firstColumn = bits & 0x0080 != 0
                lastColumn = bits & 0x0100 != 0
                horizontalBands = bits & 0x0200 == 0
                verticalBands = bits & 0x0400 == 0
            }
            func flag(_ name: String) -> Bool? { xml.attribute(name).map { MarkupElement.isOn($0) } }
            firstRow = flag("firstRow") ?? firstRow
            lastRow = flag("lastRow") ?? lastRow
            firstColumn = flag("firstColumn") ?? firstColumn
            lastColumn = flag("lastColumn") ?? lastColumn
            horizontalBands = flag("noHBand").map(!) ?? horizontalBands
            verticalBands = flag("noVBand").map(!) ?? verticalBands
        }
    }

    var styleID: String?
    var width: TableWidth?
    var alignment: Alignment?
    var indent: CGFloat?
    var borders = Borders()
    var cellMargins = CellMargins()
    var look: Look?

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        styleID = xml.value(of: "tblStyle")
        width = TableWidth(xml: xml.child("tblW"))
        switch xml.value(of: "jc") {
        case "center": alignment = .center
        case "right", "end": alignment = .right
        case "left", "start": alignment = .left
        default: break
        }
        indent = Measure.twips(xml.child("tblInd")?.attribute("w"))
        borders = Borders(xml: xml.child("tblBorders"))
        cellMargins = CellMargins(xml: xml.child("tblCellMar"))
        look = xml.child("tblLook").map(Look.init(xml:))
    }

    mutating func apply(_ other: TableProperties) {
        styleID = other.styleID ?? styleID
        width = other.width ?? width
        alignment = other.alignment ?? alignment
        indent = other.indent ?? indent
        borders.apply(other.borders)
        cellMargins.apply(other.cellMargins)
        look = other.look ?? look
    }
}

struct CellProperties: Equatable {
    enum VerticalMerge: Equatable {
        case restart
        case `continue`
    }

    enum VerticalAlignment: Equatable {
        case top, center, bottom
    }

    var width: TableWidth?
    var gridSpan: Int?
    var verticalMerge: VerticalMerge?
    var borders = Borders()
    var shading: Fill?
    var verticalAlignment: VerticalAlignment?
    var margins = CellMargins()

    init() {}

    init(xml: MarkupElement?) {
        guard let xml else { return }
        width = TableWidth(xml: xml.child("tcW"))
        gridSpan = xml.value(of: "gridSpan").flatMap(Int.init)
        if let merge = xml.child("vMerge") {
            verticalMerge = merge.attribute("val") == "restart" ? .restart : .continue
        }
        borders = Borders(xml: xml.child("tcBorders"))
        shading = Fill(shading: xml.child("shd"))
        switch xml.value(of: "vAlign") {
        case "center": verticalAlignment = .center
        case "bottom": verticalAlignment = .bottom
        case "top": verticalAlignment = .top
        default: break
        }
        margins = CellMargins(xml: xml.child("tcMar"))
    }

    mutating func apply(_ other: CellProperties) {
        width = other.width ?? width
        gridSpan = other.gridSpan ?? gridSpan
        verticalMerge = other.verticalMerge ?? verticalMerge
        borders.apply(other.borders)
        shading = other.shading ?? shading
        verticalAlignment = other.verticalAlignment ?? verticalAlignment
        margins.apply(other.margins)
    }
}
