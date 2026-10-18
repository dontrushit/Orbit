import Foundation

/// Characters of Windows symbol fonts, which Word stores as codes of the font's own encoding
/// (often shifted into the private use area, U+F0xx).
enum SymbolFonts {
    /// What to draw for `text` set in `font`: Unicode text and the font to draw it in (`nil` keeps the run's font).
    static func resolve(_ text: String, font: String?) -> (text: String, font: String?) {
        guard let font else { return (text, nil) }
        switch font.lowercased() {
        case "symbol":
            // The macOS Symbol font is Unicode-encoded, so Word's codes are translated to Unicode.
            let mapped = text.unicodeScalars.map { scalar -> String in
                symbolCharacter(code: Int(scalar.value)) ?? String(scalar)
            }
            return (mapped.joined(), nil)
        case "wingdings", "wingdings 2", "wingdings 3", "webdings":
            // The macOS versions of these fonts keep Microsoft's private-use encoding.
            let shifted = text.unicodeScalars.map { scalar -> Character in
                let value = scalar.value < 0x100 ? scalar.value | 0xF000 : scalar.value
                return Character(UnicodeScalar(value) ?? scalar)
            }
            return (String(shifted), font)
        default:
            return (text, font)
        }
    }

    /// The Unicode character for a code of the Symbol font, with or without the U+F000 shift.
    static func symbolCharacter(code: Int) -> String? {
        let code = code & 0xFF
        switch code {
        case 0x20...0x7E: return String(lowTable[code - 0x20])
        case 0xA1...0xFE:
            let character = highTable[code - 0xA1]
            return character == "\u{0}" ? nil : String(character)
        default: return nil
        }
    }

    /// Codes 0x20…0x7E.
    static let lowTable = Array(" !∀#∃%&∋()∗+,−./0123456789:;<=>?≅ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ[∴]⊥_‾αβχδεφγηιϕκλμνοπθρστυϖωξψζ{|}∼")
    /// Codes 0xA1…0xFE; 0xF0 is unassigned.
    static let highTable = Array("ϒ′≤⁄∞ƒ♣♦♥♠↔←↑→↓°±″≥×∝∂•÷≠≡≈…⏐⎯↵ℵℑℜ℘⊗⊕∅∩∪⊃⊇⊄⊂⊆∈∉∠∇®©™∏√⋅¬∧∨⇔⇐⇑⇒⇓◊〈®©™∑⎛⎜⎝⎡⎢⎣⎧⎨⎩⎪\u{0}〉∫⌠⎮⌡⎞⎟⎠⎤⎥⎦⎫⎬⎭")
}
