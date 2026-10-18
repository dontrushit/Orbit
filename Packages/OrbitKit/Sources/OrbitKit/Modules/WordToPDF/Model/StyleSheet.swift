import Foundation

/// Styles of a document (styles.xml), resolved along their `basedOn` chains.
final class StyleSheet {
    struct ParagraphStyle {
        var paragraph = ParagraphProperties()
        var run = RunProperties()
    }

    /// Parts of a table that a table style can format differently.
    enum TableRegion: String, CaseIterable {
        // In order of increasing priority, as Word applies them.
        case band1Vert, band2Vert, band1Horz, band2Horz, firstCol, lastCol, firstRow, lastRow, nwCell, neCell, swCell, seCell
    }

    struct TableFormatting {
        var cell = CellProperties()
        var paragraph = ParagraphProperties()
        var run = RunProperties()

        mutating func apply(_ other: TableFormatting) {
            cell.apply(other.cell)
            paragraph.apply(other.paragraph)
            run.apply(other.run)
        }
    }

    struct TableStyle {
        var table = TableProperties()
        var whole = TableFormatting()
        var regions: [TableRegion: TableFormatting] = [:]
    }

    let defaultRun: RunProperties
    let defaultParagraph: ParagraphProperties
    var defaultParagraphStyleID: String? { defaultStyleIDs["paragraph"] }

    private var elements: [String: MarkupElement] = [:]
    private var defaultStyleIDs: [String: String] = [:]
    private var paragraphCache: [String: ParagraphStyle] = [:]
    private var characterCache: [String: RunProperties] = [:]
    private var tableCache: [String: TableStyle] = [:]

    init(xml: MarkupElement?) {
        let defaults = xml?.child("docDefaults")
        var run = RunProperties()
        // What Word assumes when even the document defaults don't say.
        run.size = 10
        run.asciiFont = .named("Times New Roman")
        run.otherFont = .named("Times New Roman")
        run.apply(RunProperties(xml: defaults?.child("rPrDefault")?.child("rPr")))
        defaultRun = run
        defaultParagraph = ParagraphProperties(xml: defaults?.child("pPrDefault")?.child("pPr"))

        for style in xml?.children("style") ?? [] {
            guard let id = style.attribute("styleId") else { continue }
            let type = style.attribute("type") ?? "paragraph"
            elements[Self.key(type, id)] = style
            if MarkupElement.isOn(style.attribute("default") ?? "0") {
                defaultStyleIDs[type] = id
            }
        }
    }

    /// The name of a style, such as "Hyperlink"; IDs are localized ("af6") in documents made by non-English Word.
    func name(ofStyle id: String) -> String? {
        let style = elements[Self.key("character", id)] ?? elements[Self.key("paragraph", id)]
        return style?.value(of: "name")
    }

    /// The paragraph style, or the default one when `id` is `nil` or unknown.
    func paragraphStyle(_ id: String?) -> ParagraphStyle {
        let id = id.flatMap { elements[Self.key("paragraph", $0)] != nil ? $0 : nil } ?? defaultStyleIDs["paragraph"]
        guard let id else { return ParagraphStyle() }
        return resolve(id, type: "paragraph", cache: \.paragraphCache, empty: ParagraphStyle()) { style, element in
            style.paragraph.apply(ParagraphProperties(xml: element.child("pPr")))
            style.run.apply(RunProperties(xml: element.child("rPr")))
        }
    }

    func characterStyle(_ id: String) -> RunProperties {
        resolve(id, type: "character", cache: \.characterCache, empty: RunProperties()) { run, element in
            var properties = RunProperties(xml: element.child("rPr"))
            // A style refers to itself by `rStyle` only in malformed files; never inherit through it.
            properties.characterStyleID = nil
            run.apply(properties)
        }
    }

    /// The table style, or the default one (which sets the usual cell margins) when `id` is `nil` or unknown.
    func tableStyle(_ id: String?) -> TableStyle {
        let id = id.flatMap { elements[Self.key("table", $0)] != nil ? $0 : nil } ?? defaultStyleIDs["table"]
        guard let id else { return TableStyle() }
        return resolve(id, type: "table", cache: \.tableCache, empty: TableStyle()) { style, element in
            style.table.apply(TableProperties(xml: element.child("tblPr")))
            style.whole.apply(Self.formatting(element))
            for conditional in element.children("tblStylePr") {
                guard let region = conditional.attribute("type") else { continue }
                if region == "wholeTable" {
                    style.whole.apply(Self.formatting(conditional))
                } else if let region = TableRegion(rawValue: region) {
                    style.regions[region, default: TableFormatting()].apply(Self.formatting(conditional))
                }
            }
        }
    }

    // MARK: Resolution

    private static func key(_ type: String, _ id: String) -> String {
        "\(type):\(id)"
    }

    private static func formatting(_ element: MarkupElement) -> TableFormatting {
        TableFormatting(
            cell: CellProperties(xml: element.child("tcPr")),
            paragraph: ParagraphProperties(xml: element.child("pPr")),
            run: RunProperties(xml: element.child("rPr"))
        )
    }

    /// Applies the style's ancestors first, then the style itself. Cycles in `basedOn` are cut.
    private func resolve<Value>(
        _ id: String, type: String,
        cache: ReferenceWritableKeyPath<StyleSheet, [String: Value]>,
        empty: Value,
        apply: (inout Value, MarkupElement) -> Void
    ) -> Value {
        if let cached = self[keyPath: cache][id] { return cached }

        var chain: [MarkupElement] = []
        var visited: Set<String> = []
        var next: String? = id
        while let current = next, visited.insert(current).inserted, let element = elements[Self.key(type, current)] {
            chain.append(element)
            next = element.value(of: "basedOn")
        }

        var value = empty
        for element in chain.reversed() {
            apply(&value, element)
        }
        self[keyPath: cache][id] = value
        return value
    }
}
