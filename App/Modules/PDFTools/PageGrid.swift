import OrbitKit
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails of the pages in a scrolling grid. A click leaves a page out or brings it back; with `reorders`,
/// pages can be dragged into a new order. Keyboard: arrows move the focus, Space toggles, Delete leaves out.
struct PageGrid: View {
    @Binding var arrangement: PageArrangement
    let thumbnails: PDFThumbnailLoader
    var reorders = true

    @FocusState private var isFocused: Bool
    @State private var focusedID: PageArrangement.Item.ID?
    @State private var draggedID: PageArrangement.Item.ID?
    @State private var columnCount = 1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.cellWidth), spacing: Layout.spacing)], spacing: 16) {
                    ForEach(arrangement.items) { item in
                        cell(for: item)
                    }
                }
                .padding(Layout.padding)
            }
            .onGeometryChange(for: Int.self) { geometry in
                // As many columns as `.adaptive(minimum:)` fits.
                max(1, Int((geometry.size.width - 2 * Layout.padding + Layout.spacing) / (Layout.cellWidth + Layout.spacing)))
            } action: { columnCount = $0 }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space, .delete, .deleteForward]) { press in
                handle(press.key, proxy: proxy)
            }
            .onAppear { isFocused = true }
        }
    }

    private func cell(for item: PageArrangement.Item) -> some View {
        PageCell(item: item, thumbnails: thumbnails, isFocused: isFocused && focusedID == item.id)
            .onTapGesture {
                focusedID = item.id
                isFocused = true
                arrangement.toggle(item.id)
            }
            .accessibilityAction { arrangement.toggle(item.id) }
            .id(item.id)
            .modifier(Reordering(isEnabled: reorders, item: item.id, draggedID: $draggedID) { dragged, target in
                withAnimation(.snappy) { arrangement.move(dragged, to: target) }
            })
    }

    private func handle(_ key: KeyEquivalent, proxy: ScrollViewProxy) -> KeyPress.Result {
        let items = arrangement.items
        guard !items.isEmpty else { return .ignored }
        let current = focusedID.flatMap { id in items.firstIndex { $0.id == id } }

        let step: Int
        switch key {
        case .leftArrow: step = -1
        case .rightArrow: step = 1
        case .upArrow: step = -columnCount
        case .downArrow: step = columnCount
        case .space:
            guard let current else { return .ignored }
            arrangement.toggle(items[current].id)
            return .handled
        default: // Delete
            guard let current else { return .ignored }
            arrangement.setIncluded(false, for: items[current].id)
            return .handled
        }
        let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? 0
        focusedID = items[next].id
        proxy.scrollTo(items[next].id)
        return .handled
    }
}

private enum Layout {
    static let cellWidth: CGFloat = 112
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
}

private struct PageCell: View {
    let item: PageArrangement.Item
    let thumbnails: PDFThumbnailLoader
    let isFocused: Bool

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
                .frame(width: 100, height: 130)
                .opacity(item.isIncluded ? 1 : 0.3)
                .overlay(alignment: .bottomTrailing) {
                    if !item.isIncluded {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .secondary)
                            .font(.title3)
                            .offset(x: 4, y: 4)
                    }
                }
                .padding(5)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .opacity(isFocused ? 1 : 0)
                }
            Text(verbatim: "\(item.page.index + 1) · \(documentName)")
                .font(.caption)
                .foregroundStyle(item.isIncluded ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: Layout.cellWidth)
        .contentShape(Rectangle())
        .onAppear(perform: load)
        .onDisappear {
            thumbnails.cancelThumbnail(for: item.page)
            // A lazy grid keeps the views it has shown; dropping the image leaves memory to the loader's cache.
            image = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(item.page.index + 1), \(documentName)"))
        .accessibilityValue(item.isIncluded ? Text("Included") : Text("Left out"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(.quaternary)
                .aspectRatio(0.77, contentMode: .fit)
        }
    }

    private var documentName: String {
        item.page.document.deletingPathExtension().lastPathComponent
    }

    private func load() {
        if let cached = thumbnails.cachedThumbnail(for: item.page) {
            image = cached
            return
        }
        thumbnails.requestThumbnail(for: item.page) { image = $0 }
    }
}

/// Live reordering: a dragged page takes the place of the one under the pointer.
private struct Reordering: ViewModifier {
    let isEnabled: Bool
    let item: PageArrangement.Item.ID
    @Binding var draggedID: PageArrangement.Item.ID?
    let move: (PageArrangement.Item.ID, PageArrangement.Item.ID) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrag {
                    draggedID = item
                    return NSItemProvider(object: String(item) as NSString)
                }
                .onDrop(of: [.text], delegate: DropDelegate(target: item, draggedID: $draggedID, move: move))
        } else {
            content
        }
    }

    private struct DropDelegate: SwiftUI.DropDelegate {
        let target: PageArrangement.Item.ID
        @Binding var draggedID: PageArrangement.Item.ID?
        let move: (PageArrangement.Item.ID, PageArrangement.Item.ID) -> Void

        func dropEntered(info: DropInfo) {
            guard let draggedID, draggedID != target else { return }
            move(draggedID, target)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggedID = nil
            return true
        }
    }
}
