import Foundation

/// Converts Word documents to PDF from the Finder context menu, on the Mac itself.
public struct WordToPDFModule: OrbitModule {
    public static let id: ModuleID = "wordToPDF"

    public init() {}

    public var id: ModuleID { Self.id }
    public var title: LocalizedStringResource { "Word to PDF" }
    public var summary: LocalizedStringResource { "Convert Word documents to PDF right from the Finder context menu, without Microsoft Word." }
    public var symbolName: String { "doc.richtext" }
    public var tint: ModuleTint { .red }
}

extension WordToPDFModule: FinderMenuProviding {
    public func finderMenuItems(store: SettingsStore, selection: [URL]) -> [FinderMenuItem] {
        // Offered only when every selected item is a Word document, like Finder's own Quick Actions.
        guard !selection.isEmpty, selection.allSatisfy(WordToPDFConverter.canConvert) else { return [] }
        return [FinderMenuItem(title: "Convert to PDF", icon: .fileType("pdf")) { context in
            .reveal(try WordToPDFConverter.convert(context.selectedItems.filter(WordToPDFConverter.canConvert)))
        }]
    }
}
