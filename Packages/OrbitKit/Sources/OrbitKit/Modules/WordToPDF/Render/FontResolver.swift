import AppKit
import CoreText

/// Finds installed fonts for the families a document names, substituting similar ones for missing families.
final class FontResolver {
    struct Resolved {
        let font: NSFont
        /// The family has no bold or italic face, so the renderer imitates it.
        let needsSyntheticBold: Bool
        let needsSyntheticItalic: Bool
    }

    private struct Key: Hashable {
        let family: String
        let size: CGFloat
        let bold: Bool
        let italic: Bool
    }

    private let fontTable: FontTable
    private var families: [String: String] = [:]
    private var fonts: [Key: Resolved] = [:]

    init(fontTable: FontTable) {
        self.fontTable = fontTable
    }

    func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> Resolved {
        let key = Key(family: installedFamily(for: family), size: size, bold: bold, italic: italic)
        if let font = fonts[key] { return font }
        let font = Self.makeFont(key)
        fonts[key] = font
        return font
    }

    /// The family itself if it's installed, otherwise the closest available one.
    func installedFamily(for family: String) -> String {
        if let installed = families[family] { return installed }
        let installed = InstalledFonts.contains(family) ? family : substitute(for: family)
        families[family] = installed
        return installed
    }

    private func substitute(for family: String) -> String {
        if let known = Self.knownSubstitutes[family], InstalledFonts.contains(known) {
            return known
        }
        let kind = fontTable.kind(of: family) ?? Self.guessKind(of: family)
        switch kind {
        case .sansSerif: return "Arial"
        case .monospace: return "Menlo"
        case .serif: return "Times New Roman"
        }
    }

    private static let knownSubstitutes = [
        "Cambria Math": "STIX Two Math",
        "Consolas": "Menlo",
        "Segoe UI": "Helvetica Neue",
        "Segoe UI Symbol": "Apple Symbols",
    ]

    private static func guessKind(of family: String) -> FontTable.Kind {
        let name = family.lowercased()
        if ["mono", "courier", "consol", "code"].contains(where: name.contains) { return .monospace }
        if ["sans", "arial", "calibri", "aptos", "segoe", "helvet", "verdana", "tahoma", "gothic", "grotesk"].contains(where: name.contains) {
            return .sansSerif
        }
        return .serif
    }

    private static func makeFont(_ key: Key) -> Resolved {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: key.family] as CFDictionary)
        let regular = CTFontCreateWithFontDescriptor(descriptor, key.size, nil)

        var traits: CTFontSymbolicTraits = []
        if key.bold { traits.insert(.traitBold) }
        if key.italic { traits.insert(.traitItalic) }
        let mask: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        // Prefer the exact face, then whichever of the two traits exists.
        let font = CTFontCreateCopyWithSymbolicTraits(regular, key.size, nil, traits, mask)
            ?? (key.bold ? CTFontCreateCopyWithSymbolicTraits(regular, key.size, nil, .traitBold, mask) : nil)
            ?? (key.italic ? CTFontCreateCopyWithSymbolicTraits(regular, key.size, nil, .traitItalic, mask) : nil)
            ?? regular

        let actual = CTFontGetSymbolicTraits(font)
        return Resolved(
            font: font as NSFont,
            needsSyntheticBold: key.bold && !actual.contains(.traitBold),
            needsSyntheticItalic: key.italic && !actual.contains(.traitItalic)
        )
    }
}

/// Font families available to this process. Office for Mac keeps Calibri, Cambria and other
/// Windows fonts inside its app bundles; they're registered for this process only, and only
/// when a document needs a family that isn't installed system-wide.
private enum InstalledFonts {
    // Static properties are initialized lazily and thread-safely.
    static let system = availableFamilies()
    static let withOffice: Set<String> = {
        registerOfficeFonts()
        return availableFamilies()
    }()

    static func contains(_ family: String) -> Bool {
        system.contains(family) || withOffice.contains(family)
    }

    private static func availableFamilies() -> Set<String> {
        Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
    }

    private static func registerOfficeFonts() {
        let apps = ["Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint", "Microsoft Outlook"]
        let fileManager = FileManager.default
        guard let folder = apps.lazy
            .map({ URL(fileURLWithPath: "/Applications/\($0).app/Contents/Resources/DFonts", isDirectory: true) })
            .first(where: { fileManager.fileExists(atPath: $0.path) }),
            let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }

        for file in files where ["ttf", "ttc", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
