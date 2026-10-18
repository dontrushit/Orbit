import AppKit

extension DocumentBuilder {
    private struct Cell {
        let element: MarkupElement
        let properties: CellProperties
        let column: Int
        let span: Int
    }

    private struct Row {
        let cells: [Cell]
        /// Minimum height (`atLeast` and `exact` rules alike: TextKit can't clip a row).
        let height: CGFloat?
    }

    /// Word's default cell margins: 0.08" left and right, none above and below.
    private static let defaultCellMargins = (top: CGFloat(0), left: CGFloat(5.4), bottom: CGFloat(0), right: CGFloat(5.4))

    func appendTable(_ element: MarkupElement, to output: NSMutableAttributedString, story: Story, context: BlockContext) {
        let direct = TableProperties(xml: element.child("tblPr"))
        let style = styles.tableStyle(direct.styleID)
        var properties = style.table
        properties.apply(direct)
        let look = properties.look ?? TableProperties.Look()

        let rows = Self.rows(of: element)
        guard !rows.isEmpty else { return }
        let gridColumns = element.child("tblGrid")?.children("gridCol").count ?? 0
        let usedColumns = rows.map { $0.cells.last.map { $0.column + $0.span } ?? 0 }.max() ?? 0
        let columnCount = max(gridColumns, usedColumns, 1)
        let widths = columnWidths(element, properties: properties, columnCount: columnCount, available: context.width)
        let tableWidth = widths.reduce(0, +)

        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        var indent: CGFloat = switch properties.alignment {
        case .center: (context.width - tableWidth) / 2
        case .right: context.width - tableWidth
        case .left, nil: properties.indent ?? 0
        }
        // Word often shifts tables left by the cell margin so cell text lines up with body text; TextKit can't go into the margin.
        indent = min(max(indent, 0), max(context.width - tableWidth, 0))
        if indent > 0 {
            table.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX)
        }

        let rowSpans = Self.verticalSpans(rows)
        for (rowIndex, row) in rows.enumerated() {
            for cell in row.cells where cell.properties.verticalMerge != .continue {
                let rowSpan = rowSpans[rowIndex][cell.column] ?? 1
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: rowSpan, startingColumn: cell.column, columnSpan: cell.span)

                let region = TableRegionSelector(
                    row: rowIndex, rowSpan: rowSpan, rowCount: rows.count,
                    column: cell.column, columnSpan: cell.span, columnCount: columnCount, look: look
                )
                var formatting = style.whole
                for name in region.regions {
                    if let conditional = style.regions[name] {
                        formatting.apply(conditional)
                    }
                }
                var cellProperties = formatting.cell
                cellProperties.apply(cell.properties)

                let edges = borders(of: cellProperties, table: properties.borders, region: region)
                let margins = cellMargins(table: properties.cellMargins, cell: cellProperties.margins)
                configure(block, edges: edges, margins: margins, cell: cellProperties, minimumHeight: row.height)

                let spannedWidth = widths[cell.column..<min(cell.column + cell.span, widths.count)].reduce(0, +)
                let borderAllowance = ((edges.left?.width ?? 0) + (edges.right?.width ?? 0)) / 2
                let contentWidth = max(spannedWidth - margins.left - margins.right - borderAllowance, 1)
                block.setValue(contentWidth, type: .absoluteValueType, for: .width)

                let cellContext = BlockContext(blocks: context.blocks + [block], tableFormatting: formatting, width: contentWidth)
                let start = output.length
                appendBlocks(cell.element.children, to: output, story: story, context: cellContext)
                if output.length == start {
                    // Every cell needs a paragraph to exist in TextKit.
                    let style = styler.paragraphStyle(for: styles.defaultParagraph, blocks: cellContext.blocks)
                    var attributes = styler.attributes(for: styles.defaultRun, text: "")
                    attributes[.paragraphStyle] = style
                    output.append(NSAttributedString(string: "\n", attributes: attributes))
                }
            }
        }
    }

    // MARK: Structure

    private static func rows(of table: MarkupElement) -> [Row] {
        // Rows can be wrapped in content controls and custom XML.
        func rowElements(_ element: MarkupElement) -> [MarkupElement] {
            element.children.flatMap { child -> [MarkupElement] in
                if child.is("tr") { return [child] }
                if child.is("sdt") { return child.child("sdtContent").map(rowElements) ?? [] }
                if child.is("customXml") { return rowElements(child) }
                return []
            }
        }
        func cellElements(_ element: MarkupElement) -> [MarkupElement] {
            element.children.flatMap { child -> [MarkupElement] in
                if child.is("tc") { return [child] }
                if child.is("sdt") { return child.child("sdtContent").map(cellElements) ?? [] }
                if child.is("customXml") { return cellElements(child) }
                return []
            }
        }

        return rowElements(table).map { row in
            let rowProperties = row.child("trPr")
            var column = rowProperties?.value(of: "gridBefore").flatMap(Int.init) ?? 0
            let cells = cellElements(row).map { element in
                let properties = CellProperties(xml: element.child("tcPr"))
                let span = max(properties.gridSpan ?? 1, 1)
                defer { column += span }
                return Cell(element: element, properties: properties, column: column, span: span)
            }
            let height = Measure.twips(rowProperties?.child("trHeight")?.attribute("val"))
            return Row(cells: cells, height: height)
        }
    }

    /// For every row, the number of rows each vertically merged cell spans, keyed by its first column.
    private static func verticalSpans(_ rows: [Row]) -> [[Int: Int]] {
        rows.enumerated().map { index, row in
            var spans: [Int: Int] = [:]
            for cell in row.cells where cell.properties.verticalMerge == .restart {
                var span = 1
                while index + span < rows.count,
                      rows[index + span].cells.contains(where: { $0.column == cell.column && $0.properties.verticalMerge == .continue }) {
                    span += 1
                }
                spans[cell.column] = span
            }
            return spans
        }
    }

    /// Widths of the grid columns, scaled to the table's preferred width and to the space available.
    private func columnWidths(_ table: MarkupElement, properties: TableProperties, columnCount: Int, available: CGFloat) -> [CGFloat] {
        var widths = table.child("tblGrid")?.children("gridCol").compactMap { Measure.twips($0.attribute("w")) } ?? []
        let known = widths.filter { $0 > 0 }
        let fallback = known.isEmpty ? available / CGFloat(columnCount) : known.reduce(0, +) / CGFloat(known.count)
        widths = (0..<columnCount).map { index in index < widths.count && widths[index] > 0 ? widths[index] : fallback }

        let total = widths.reduce(0, +)
        let preferred: CGFloat? = switch properties.width {
        case .points(let points): points
        case .fraction(let fraction): available * fraction
        case .auto, nil: nil
        }
        var target = total
        if let preferred, abs(preferred - total) > 1 {
            target = preferred
        }
        target = min(target, available)
        guard total > 0, abs(target - total) > 0.01 else { return widths }
        return widths.map { $0 * target / total }
    }

    // MARK: Formatting

    private struct Edges {
        var top: Border?
        var left: Border?
        var bottom: Border?
        var right: Border?
    }

    /// A cell's own borders win; otherwise the table's outer borders apply at the edges and the inside ones between cells.
    private func borders(of cell: CellProperties, table: Borders, region: TableRegionSelector) -> Edges {
        func resolve(_ own: Border??, _ outer: Border??, _ inner: Border??, isOuter: Bool) -> Border? {
            if let own { return own }
            return (isOuter ? outer : inner) ?? nil
        }
        return Edges(
            top: resolve(cell.borders.top, table.top, table.insideHorizontal, isOuter: region.isFirstRow),
            left: resolve(cell.borders.left, table.left, table.insideVertical, isOuter: region.isFirstColumn),
            bottom: resolve(cell.borders.bottom, table.bottom, table.insideHorizontal, isOuter: region.isLastRow),
            right: resolve(cell.borders.right, table.right, table.insideVertical, isOuter: region.isLastColumn)
        )
    }

    private func cellMargins(table: CellMargins, cell: CellMargins) -> (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        var margins = table
        margins.apply(cell)
        let defaults = Self.defaultCellMargins
        return (margins.top ?? defaults.top, margins.left ?? defaults.left, margins.bottom ?? defaults.bottom, margins.right ?? defaults.right)
    }

    private func configure(
        _ block: NSTextTableBlock, edges: Edges, margins: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat),
        cell: CellProperties, minimumHeight: CGFloat?
    ) {
        let sides: [(NSRectEdge, Border?, CGFloat)] = [
            (.minY, edges.top, margins.top), (.minX, edges.left, margins.left),
            (.maxY, edges.bottom, margins.bottom), (.maxX, edges.right, margins.right),
        ]
        for (edge, border, padding) in sides {
            block.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
            if let border {
                block.setWidth(border.width, type: .absoluteValueType, for: .border, edge: edge)
                block.setBorderColor(border.color.nsColor, for: edge)
            }
        }
        if let fill = cell.shading?.color {
            block.backgroundColor = fill.nsColor
        }
        switch cell.verticalAlignment {
        case .center: block.verticalAlignment = .middleAlignment
        case .bottom: block.verticalAlignment = .bottomAlignment
        case .top, nil: block.verticalAlignment = .topAlignment
        }
        if let minimumHeight, minimumHeight > 0 {
            block.setValue(max(minimumHeight - margins.top - margins.bottom, 0), type: .absoluteValueType, for: .minimumHeight)
        }
    }
}

/// Which conditional formats of a table style apply to a cell.
struct TableRegionSelector {
    let row: Int
    let rowSpan: Int
    let rowCount: Int
    let column: Int
    let columnSpan: Int
    let columnCount: Int
    let look: TableProperties.Look

    var isFirstRow: Bool { row == 0 }
    var isLastRow: Bool { row + rowSpan >= rowCount }
    var isFirstColumn: Bool { column == 0 }
    var isLastColumn: Bool { column + columnSpan >= columnCount }

    /// In the order Word applies them, later ones winning.
    var regions: [StyleSheet.TableRegion] {
        var regions: [StyleSheet.TableRegion] = []
        let headerRow = look.firstRow && isFirstRow
        let footerRow = look.lastRow && isLastRow
        let headerColumn = look.firstColumn && isFirstColumn
        let footerColumn = look.lastColumn && isLastColumn

        // Bands don't count the header row and column.
        if look.verticalBands, !headerColumn, !footerColumn {
            regions.append((column - (look.firstColumn ? 1 : 0)) % 2 == 0 ? .band1Vert : .band2Vert)
        }
        if look.horizontalBands, !headerRow, !footerRow {
            regions.append((row - (look.firstRow ? 1 : 0)) % 2 == 0 ? .band1Horz : .band2Horz)
        }
        if headerColumn { regions.append(.firstCol) }
        if footerColumn { regions.append(.lastCol) }
        if headerRow { regions.append(.firstRow) }
        if footerRow { regions.append(.lastRow) }
        if headerRow, headerColumn { regions.append(.nwCell) }
        if headerRow, footerColumn { regions.append(.neCell) }
        if footerRow, headerColumn { regions.append(.swCell) }
        if footerRow, footerColumn { regions.append(.seCell) }
        return regions
    }
}
