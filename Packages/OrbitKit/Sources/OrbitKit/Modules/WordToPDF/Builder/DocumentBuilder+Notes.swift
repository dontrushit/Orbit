import AppKit

/// Footnotes and endnotes referenced in the text, numbered in reference order.
struct NoteCollector {
    enum Kind: CaseIterable {
        case footnote, endnote

        var elementName: String {
            switch self {
            case .footnote: "footnote"
            case .endnote: "endnote"
            }
        }

        /// Word numbers footnotes 1, 2, 3 and endnotes i, ii, iii by default.
        var format: NumberFormat {
            switch self {
            case .footnote: .decimal
            case .endnote: .lowerRoman
            }
        }
    }

    struct Reference {
        let kind: Kind
        let id: String
        let label: String
    }

    var footnotes: MarkupElement?
    var endnotes: MarkupElement?
    var footnotesPath: String?
    var endnotesPath: String?
    private(set) var references: [Reference] = []
    /// Label of the note being built, shown where its text has `w:footnoteRef`.
    var currentLabel: String?

    /// Numbers a reference and returns its label, or `nil` if the document has no such note.
    mutating func reference(_ kind: Kind, id: String) -> String? {
        guard note(kind, id: id) != nil else { return nil }
        let label = kind.format.format(references.filter { $0.kind == kind }.count + 1)
        references.append(Reference(kind: kind, id: id, label: label))
        return label
    }

    func note(_ kind: Kind, id: String) -> MarkupElement? {
        let part = kind == .footnote ? footnotes : endnotes
        return part?.children(kind.elementName).first { $0.attribute("id") == id }
    }

    func path(_ kind: Kind) -> String? {
        kind == .footnote ? footnotesPath : endnotesPath
    }
}

extension DocumentBuilder {
    /// Notes go after the body, below a short rule: footnotes first, then endnotes.
    func appendNotes(to output: NSMutableAttributedString) {
        guard !notes.references.isEmpty else { return }
        output.append(Self.noteSeparator())

        for kind in NoteCollector.Kind.allCases {
            guard let path = notes.path(kind) else { continue }
            let story = Story(path: path, relationships: (try? package.relationships(of: path)) ?? .empty, hasLivePageFields: false)
            for reference in notes.references where reference.kind == kind {
                guard let note = notes.note(kind, id: reference.id) else { continue }
                notes.currentLabel = reference.label
                appendBlocks(note.children, to: output, story: story, context: BlockContext(width: page.contentRect.width))
            }
        }
        notes.currentLabel = nil
    }

    /// An empty paragraph whose box has only a top border: a rule a third of the text width.
    private static func noteSeparator() -> NSAttributedString {
        let rule = NSTextBlock()
        rule.setValue(33, type: .percentageValueType, for: .width)
        rule.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .minY)
        rule.setBorderColor(.black, for: .minY)
        rule.setWidth(12, type: .absoluteValueType, for: .margin, edge: .minY)

        let style = NSMutableParagraphStyle()
        style.textBlocks = [rule]
        return NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4), .paragraphStyle: style])
    }
}
