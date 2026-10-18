import AppKit

/// A Word document translated into attributed text, ready to be paginated.
struct BuiltDocument {
    var body: NSAttributedString
    /// In document order; the first starts at index 0.
    var sections: [DocumentSection]
    /// Even pages have headers and footers of their own.
    var usesEvenPageHeaders: Bool
    var metadata: DocumentMetadata
}

struct PageSetup: Equatable {
    /// Word's defaults: US Letter with one-inch margins.
    var size = CGSize(width: 612, height: 792)
    var top: CGFloat = 72
    var bottom: CGFloat = 72
    var left: CGFloat = 72
    var right: CGFloat = 72
    /// Distance from the top edge of the page to the top of the header.
    var header: CGFloat = 36
    /// Distance from the bottom edge of the page to the bottom of the footer.
    var footer: CGFloat = 36

    /// The area for body text, in page coordinates with the origin at the top left.
    var contentRect: CGRect {
        CGRect(x: left, y: top, width: max(size.width - left - right, 72), height: max(size.height - top - bottom, 72))
    }
}

struct HeaderFooterSet {
    var standard: NSAttributedString?
    var first: NSAttributedString?
    var even: NSAttributedString?

    /// A section without its own header or footer of some kind continues the previous section's one.
    func inheriting(from previous: HeaderFooterSet) -> HeaderFooterSet {
        HeaderFooterSet(standard: standard ?? previous.standard, first: first ?? previous.first, even: even ?? previous.even)
    }
}

struct DocumentSection {
    /// Index of the section's first character in the body.
    var startIndex: Int
    var page = PageSetup()
    var headers = HeaderFooterSet()
    var footers = HeaderFooterSet()
    /// The first page has its own header and footer.
    var hasTitlePage = false
    var pageNumberStart: Int?
    var pageNumberFormat = NumberFormat.decimal
}

// MARK: Attributes

extension NSAttributedString.Key {
    /// `Drawing` of an attachment character.
    static let docxDrawing = NSAttributedString.Key("dev.orbit.docx.drawing")
    /// `[FloatingDrawing]` anchored to a paragraph; set on its first character.
    static let docxFloatingDrawings = NSAttributedString.Key("dev.orbit.docx.floatingDrawings")
    /// `TabLeaders` of a paragraph.
    static let docxTabLeaders = NSAttributedString.Key("dev.orbit.docx.tabLeaders")
    /// `FieldPlaceholder` over text the renderer replaces once pages are known.
    static let docxField = NSAttributedString.Key("dev.orbit.docx.field")
    /// `[String]`: names of the bookmarks that start at the character.
    static let docxBookmarks = NSAttributedString.Key("dev.orbit.docx.bookmarks")
    /// `String`: a link to a bookmark in the document.
    static let docxInternalLink = NSAttributedString.Key("dev.orbit.docx.internalLink")
    /// `Bool`, set on a whole paragraph that should stay on the same page as the next one.
    static let docxKeepWithNext = NSAttributedString.Key("dev.orbit.docx.keepWithNext")
    /// `Bool`, set on a whole paragraph none of whose lines may stay alone at the bottom or top of a page.
    static let docxWidowControl = NSAttributedString.Key("dev.orbit.docx.widowControl")
    /// `PageBreak`, set on the form feed of a page break paragraph.
    static let docxPageBreak = NSAttributedString.Key("dev.orbit.docx.pageBreak")
}

/// A picture, text box or shape. Drawn by the layout manager in the frame TextKit gives it.
final class Drawing {
    enum Content {
        case image(CGImage)
        case text(NSAttributedString, insets: NSEdgeInsets)
        /// A picture in a format macOS can't decode (EMF, WMF). It keeps its space so the layout holds.
        case unsupported
    }

    struct Outline {
        var color: RGBColor
        var width: CGFloat
    }

    let size: CGSize
    let content: Content
    let fill: RGBColor?
    let outline: Outline?

    init(size: CGSize, content: Content, fill: RGBColor? = nil, outline: Outline? = nil) {
        self.size = size
        self.content = content
        self.fill = fill
        self.outline = outline
    }

    /// An attachment character that reserves the drawing's space in the text.
    func attachment(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        // TextKit sizes the attachment by its image; an empty one of the right size draws nothing.
        attachment.image = NSImage(size: size)
        attachment.bounds = CGRect(origin: .zero, size: size)
        let string = NSMutableAttributedString(attachment: attachment)
        string.addAttributes(attributes, range: NSRange(location: 0, length: string.length))
        string.addAttribute(.docxDrawing, value: self, range: NSRange(location: 0, length: string.length))
        return string
    }
}

/// A drawing positioned on the page independently of the text flow ("In Front of Text", "Behind Text").
struct FloatingDrawing {
    enum Origin {
        case page, margin, paragraph
    }

    enum Placement {
        case offset(CGFloat)
        case leading, center, trailing
    }

    struct Axis {
        var origin: Origin
        var placement: Placement
    }

    let drawing: Drawing
    let horizontal: Axis
    let vertical: Axis
    let isBehindText: Bool
}

/// Why a page break paragraph is there.
enum PageBreak {
    /// A manual page break, or a paragraph that starts a page.
    case page
    /// A section that starts on a new page.
    case section
}

/// Text whose value depends on pagination, such as a page number.
enum FieldPlaceholder {
    case page
    case pageCount
    case sectionPageCount
    /// The number of the page a bookmark is on, as in a table of contents.
    case pageReference(String)
}

/// Leaders of a paragraph's tab stops, which TextKit doesn't draw itself.
struct TabLeaders {
    let stops: [(position: CGFloat, leader: TabStop.Leader)]

    /// The leader of the stop a tab starting at `x` advances to.
    func leader(forTabStartingAt x: CGFloat) -> TabStop.Leader {
        stops.first { $0.position > x + 0.5 }?.leader ?? .none
    }
}
