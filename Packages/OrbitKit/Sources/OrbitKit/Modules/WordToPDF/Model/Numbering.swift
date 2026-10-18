import Foundation

enum NumberFormat: Equatable {
    case decimal, decimalZero, upperRoman, lowerRoman, upperLetter, lowerLetter, russianUpper, russianLower, bullet, none

    init(_ value: String?) {
        switch value {
        case "decimalZero": self = .decimalZero
        case "upperRoman": self = .upperRoman
        case "lowerRoman": self = .lowerRoman
        case "upperLetter": self = .upperLetter
        case "lowerLetter": self = .lowerLetter
        case "russianUpper": self = .russianUpper
        case "russianLower": self = .russianLower
        case "bullet": self = .bullet
        case "none": self = .none
        // Rarer formats (ordinal words, CJK numerals, …) fall back to plain numbers.
        default: self = .decimal
        }
    }

    func format(_ number: Int) -> String {
        switch self {
        case .decimal, .bullet: String(number)
        case .decimalZero: number >= 0 && number < 10 ? "0\(number)" : String(number)
        case .upperRoman: Self.roman(number)
        case .lowerRoman: Self.roman(number).lowercased()
        case .upperLetter: Self.letters(number, alphabet: Self.latin)
        case .lowerLetter: Self.letters(number, alphabet: Self.latin).lowercased()
        case .russianUpper: Self.letters(number, alphabet: Self.russian)
        case .russianLower: Self.letters(number, alphabet: Self.russian).lowercased()
        case .none: ""
        }
    }

    private static let latin = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Word skips Ё, Й, Ъ, Ы and Ь in lettered lists.
    private static let russian = Array("АБВГДЕЖЗИКЛМНОПРСТУФХЦЧШЩЭЮЯ")

    /// Word's style: A…Z, then AA…ZZ, then AAA…
    private static func letters(_ number: Int, alphabet: [Character]) -> String {
        guard number > 0 else { return String(number) }
        let letter = alphabet[(number - 1) % alphabet.count]
        return String(repeating: letter, count: (number - 1) / alphabet.count + 1)
    }

    private static func roman(_ number: Int) -> String {
        guard number > 0, number < 4000 else { return String(number) }
        let numerals: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
            (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var remainder = number
        var result = ""
        for (value, numeral) in numerals {
            while remainder >= value {
                result += numeral
                remainder -= value
            }
        }
        return result
    }
}

/// List definitions from numbering.xml.
struct NumberingDefinitions {
    struct Level {
        enum Suffix {
            case tab, space, nothing
        }

        var start = 1
        var format = NumberFormat.decimal
        /// Template such as "%1.%2." where %n is the counter of level n.
        var text = ""
        var suffix = Suffix.tab
        /// Legal numbering shows all levels as decimal numbers: "1.1.1" instead of "I.a.i".
        var isLegal = false
        var paragraph = ParagraphProperties()
        var run = RunProperties()

        init() {}

        init(xml: MarkupElement) {
            start = xml.value(of: "start").flatMap(Int.init) ?? 1
            format = NumberFormat(xml.value(of: "numFmt"))
            text = xml.value(of: "lvlText") ?? ""
            switch xml.value(of: "suff") {
            case "space": suffix = .space
            case "nothing": suffix = .nothing
            default: suffix = .tab
            }
            isLegal = xml.flag("isLgl") ?? false
            paragraph = ParagraphProperties(xml: xml.child("pPr"))
            run = RunProperties(xml: xml.child("rPr"))
        }
    }

    private struct Instance {
        var abstractID: String
        var startOverrides: [Int: Int] = [:]
        var levelOverrides: [Int: Level] = [:]
    }

    private var abstracts: [String: [Int: Level]] = [:]
    private var instances: [String: Instance] = [:]

    /// - Parameter numberingStyleList: The list (`numId`) that a numbering style points to,
    ///   for definitions that only link to such a style.
    init(xml: MarkupElement?, numberingStyleList: (String) -> String? = { _ in nil }) {
        guard let xml else { return }

        var styleLinks: [String: String] = [:]
        for abstract in xml.children("abstractNum") {
            guard let id = abstract.attribute("abstractNumId") else { continue }
            var levels: [Int: Level] = [:]
            for level in abstract.children("lvl") {
                guard let index = level.attribute("ilvl").flatMap(Int.init) else { continue }
                levels[index] = Level(xml: level)
            }
            abstracts[id] = levels
            if levels.isEmpty, let style = abstract.value(of: "numStyleLink") {
                styleLinks[id] = style
            }
        }

        for num in xml.children("num") {
            guard let id = num.attribute("numId"), let abstractID = num.value(of: "abstractNumId") else { continue }
            var instance = Instance(abstractID: abstractID)
            for override in num.children("lvlOverride") {
                guard let index = override.attribute("ilvl").flatMap(Int.init) else { continue }
                if let start = override.value(of: "startOverride").flatMap(Int.init) {
                    instance.startOverrides[index] = start
                }
                if let level = override.child("lvl") {
                    instance.levelOverrides[index] = Level(xml: level)
                }
            }
            instances[id] = instance
        }

        // A definition that links to a numbering style takes its levels from the list that style uses.
        for (id, style) in styleLinks {
            if let listID = numberingStyleList(style), let target = instances[listID], let levels = abstracts[target.abstractID], !levels.isEmpty {
                abstracts[id] = levels
            }
        }
    }

    func level(_ index: Int, of listID: String) -> Level? {
        guard let instance = instances[listID] else { return nil }
        var level = instance.levelOverrides[index] ?? abstracts[instance.abstractID]?[index]
        if let start = instance.startOverrides[index] {
            level?.start = start
        }
        return level
    }

    /// Paragraphs of lists sharing a definition continue each other's numbering,
    /// unless the list restarts it with a start override.
    fileprivate func counterKey(for listID: String) -> String? {
        guard let instance = instances[listID] else { return nil }
        return instance.startOverrides.isEmpty ? "abstract:\(instance.abstractID)" : "list:\(listID)"
    }
}

/// Numbers list paragraphs in document order.
struct NumberingCounter {
    private let definitions: NumberingDefinitions
    private var counters: [String: [Int: Int]] = [:]

    init(definitions: NumberingDefinitions) {
        self.definitions = definitions
    }

    /// Advances the counter of the level and returns the label of the paragraph, such as "2.1." or "•".
    mutating func nextLabel(list listID: String, level index: Int) -> String? {
        guard let level = definitions.level(index, of: listID), let key = definitions.counterKey(for: listID) else { return nil }

        // A new item restarts the numbering of the levels below it.
        var values = (counters[key] ?? [:]).filter { $0.key < index }
        values[index] = (counters[key]?[index] ?? level.start - 1) + 1
        counters[key] = values

        if level.format == .bullet {
            return level.text
        }
        var label = level.text
        for placeholder in 0...8 where label.contains("%\(placeholder + 1)") {
            let referenced = definitions.level(placeholder, of: listID)
            let value = values[placeholder] ?? referenced?.start ?? 1
            let format = level.isLegal && placeholder < index ? .decimal : referenced?.format ?? .decimal
            label = label.replacingOccurrences(of: "%\(placeholder + 1)", with: format.format(value))
        }
        return label
    }
}
