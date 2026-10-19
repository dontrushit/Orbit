import Foundation

/// Pages of one or more documents in the order the user arranged them, each either kept or left out.
public struct PageArrangement: Equatable, Sendable {
    public struct Item: Identifiable, Hashable, Sendable {
        /// Stable while items move around.
        public let id: Int
        public let page: PDFTools.PageReference
        public var isIncluded = true
    }

    public private(set) var items: [Item]

    /// All pages of the documents, document after document.
    public init(documents: [PDFDocumentInfo]) {
        self.init(pages: documents.flatMap { document in
            (0..<document.pageCount).map { PDFTools.PageReference(document: document.url, index: $0) }
        })
    }

    public init(pages: [PDFTools.PageReference]) {
        items = pages.enumerated().map { Item(id: $0.offset, page: $0.element) }
    }

    public var includedPages: [PDFTools.PageReference] {
        items.filter(\.isIncluded).map(\.page)
    }

    public var includedCount: Int {
        items.lazy.filter(\.isIncluded).count
    }

    public mutating func toggle(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isIncluded.toggle()
    }

    public mutating func setIncluded(_ isIncluded: Bool, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isIncluded = isIncluded
    }

    public mutating func setAllIncluded(_ isIncluded: Bool) {
        for index in items.indices {
            items[index].isIncluded = isIncluded
        }
    }

    /// Puts the item where `target` is, shifting `target` toward the place the item came from,
    /// as when dragging a thumbnail over another one.
    public mutating func move(_ id: Item.ID, to target: Item.ID) {
        guard id != target,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target })
        else { return }
        items.insert(items.remove(at: from), at: to)
    }
}
