import AppKit

/// OOXML stores lengths in several units; the converter works in points.
enum Measure {
    /// Twentieths of a point: page geometry, indents, spacing.
    /// Also accepts the universal measures some editors write, such as "2.5cm" or "12pt".
    static func twips(_ value: String?) -> CGFloat? {
        guard let value else { return nil }
        if let number = Double(value) { return CGFloat(number) / 20 }
        return universal(value)
    }

    /// Font sizes.
    static func halfPoints(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value) else { return nil }
        return CGFloat(number) / 2
    }

    /// Border widths.
    static func eighthPoints(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value) else { return nil }
        return CGFloat(number) / 8
    }

    /// English Metric Units of DrawingML: 914 400 per inch.
    static func emu(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value) else { return nil }
        return CGFloat(number) / 12700
    }

    /// Lengths such as "12pt", "2.54cm", "1in", "5mm", "1pc" (also used in VML styles).
    static func universal(_ value: String) -> CGFloat? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let units: [(suffix: String, points: Double)] = [("pt", 1), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("in", 72), ("pc", 12), ("pi", 12), ("px", 0.75)]
        for unit in units where trimmed.hasSuffix(unit.suffix) {
            guard let number = Double(trimmed.dropLast(unit.suffix.count)) else { return nil }
            return CGFloat(number * unit.points)
        }
        return nil
    }
}

struct RGBColor: Equatable, Hashable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let white = RGBColor(red: 1, green: 1, blue: 1)

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "1F4E79"; `nil` for "auto" and anything malformed.
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }

    /// Colors of `w:highlight`, which are named rather than given in hex.
    init?(highlight name: String?) {
        let colors: [String: String] = [
            "yellow": "FFFF00", "green": "00FF00", "cyan": "00FFFF", "magenta": "FF00FF",
            "blue": "0000FF", "red": "FF0000", "darkBlue": "000080", "darkCyan": "008080",
            "darkGreen": "008000", "darkMagenta": "800080", "darkRed": "800000", "darkYellow": "808000",
            "darkGray": "808080", "lightGray": "C0C0C0", "black": "000000", "white": "FFFFFF",
        ]
        guard let name, let hex = colors[name] else { return nil }
        self.init(hex: hex)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
