import Foundation

/// Merges and splits PDF files from the Finder context menu.
public struct PDFToolsModule: OrbitModule {
    public static let id: ModuleID = "pdfTools"

    public init() {}

    public var id: ModuleID { Self.id }
    public var title: LocalizedStringResource { "PDF Tools" }
    public var summary: LocalizedStringResource { "Merge and split PDF files right from the Finder context menu." }
    public var symbolName: String { "doc.on.doc" }
    public var tint: ModuleTint { .orange }
}

extension PDFToolsModule: FinderMenuProviding {
    public func finderMenuItems(store: SettingsStore, selection: [URL]) -> [FinderMenuItem] {
        guard !selection.isEmpty, selection.allSatisfy(PDFTools.isPDF) else { return [] }
        if selection.count == 1 {
            return [FinderMenuItem(title: "Split PDF", icon: .symbol("arrow.triangle.branch"), isLongRunning: true) { context in
                guard let source = context.selectedItems.first(where: PDFTools.isPDF) else { throw PDFTools.Failure.tooFewDocuments }
                return .reveal([try PDFTools.split(source)])
            }]
        }
        return [FinderMenuItem(title: "Merge PDFs", icon: .symbol("arrow.triangle.merge"), isLongRunning: true) { context in
            .reveal([try PDFTools.merge(context.selectedItems.filter(PDFTools.isPDF))])
        }]
    }
}
