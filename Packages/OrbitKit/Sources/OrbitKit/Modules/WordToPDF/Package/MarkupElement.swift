import Foundation

/// XML namespaces the converter reads. Transitional and Strict OOXML URIs map to the same case,
/// and elements are matched by namespace, never by prefix: editors are free to choose prefixes.
enum MarkupNamespace: Hashable {
    /// WordprocessingML, the `w:` namespace.
    case w
    /// Relationship references, the `r:` namespace.
    case r
    /// DrawingML.
    case a
    /// DrawingML placement in a document, `wp:`.
    case wp
    case picture
    /// Word shapes and text boxes, `wps:`.
    case wordShape
    case wordGroup
    case markupCompatibility
    /// Office Math, `m:`.
    case math
    case vml
    case packageRelationships
    case coreProperties
    case dublinCore
    /// Unprefixed attributes, such as DrawingML's `cx`.
    case none
    case other

    init(uri: String?) {
        guard let uri, !uri.isEmpty else {
            self = .none
            return
        }
        self = Self.byURI[uri] ?? .other
    }

    private static let byURI: [String: MarkupNamespace] = [
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main": .w,
        "http://purl.oclc.org/ooxml/wordprocessingml/main": .w,
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships": .r,
        "http://purl.oclc.org/ooxml/officeDocument/relationships": .r,
        "http://schemas.openxmlformats.org/drawingml/2006/main": .a,
        "http://purl.oclc.org/ooxml/drawingml/main": .a,
        "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing": .wp,
        "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing": .wp,
        "http://schemas.openxmlformats.org/drawingml/2006/picture": .picture,
        "http://purl.oclc.org/ooxml/drawingml/picture": .picture,
        "http://schemas.microsoft.com/office/word/2010/wordprocessingShape": .wordShape,
        "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup": .wordGroup,
        "http://schemas.openxmlformats.org/markup-compatibility/2006": .markupCompatibility,
        "http://schemas.openxmlformats.org/officeDocument/2006/math": .math,
        "http://purl.oclc.org/ooxml/officeDocument/math": .math,
        "urn:schemas-microsoft-com:vml": .vml,
        "http://schemas.openxmlformats.org/package/2006/relationships": .packageRelationships,
        "http://schemas.openxmlformats.org/package/2006/metadata/core-properties": .coreProperties,
        "http://purl.org/dc/elements/1.1/": .dublinCore,
    ]
}

/// An element of a parsed XML part. Immutable once parsing is done.
final class MarkupElement {
    struct AttributeName: Hashable {
        let namespace: MarkupNamespace
        let name: String
    }

    let namespace: MarkupNamespace
    let name: String
    fileprivate(set) var attributes: [AttributeName: String] = [:]
    fileprivate(set) var children: [MarkupElement] = []
    /// Character data directly inside the element. OOXML keeps text only in leaf elements such as `w:t`.
    fileprivate(set) var text = ""

    fileprivate init(namespace: MarkupNamespace, name: String) {
        self.namespace = namespace
        self.name = name
    }

    func `is`(_ name: String, in namespace: MarkupNamespace = .w) -> Bool {
        self.name == name && self.namespace == namespace
    }

    func child(_ name: String, in namespace: MarkupNamespace = .w) -> MarkupElement? {
        children.first { $0.is(name, in: namespace) }
    }

    func children(_ name: String, in namespace: MarkupNamespace = .w) -> [MarkupElement] {
        children.filter { $0.is(name, in: namespace) }
    }

    func attribute(_ name: String, in namespace: MarkupNamespace = .w) -> String? {
        attributes[AttributeName(namespace: namespace, name: name)]
    }

    /// `w:val` of the child: the shape of most WordprocessingML properties.
    func value(of childName: String) -> String? {
        child(childName)?.attribute("val")
    }

    /// An on/off property: present without a value means on. `nil` when the child is absent.
    func flag(_ childName: String) -> Bool? {
        guard let child = child(childName) else { return nil }
        return Self.isOn(child.attribute("val"))
    }

    static func isOn(_ value: String?) -> Bool {
        guard let value else { return true }
        return !["0", "false", "off"].contains(value)
    }
}

enum MarkupParser {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ data: Data) throws -> MarkupElement {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        let builder = TreeBuilder()
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw Failure(description: parser.parserError.map(String.init(describing:)) ?? "empty document")
        }
        return root
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    private(set) var root: MarkupElement?
    private var stack: [MarkupElement] = []
    /// Prefix → URIs in scope; XMLParser resolves element namespaces but leaves attribute names prefixed.
    private var prefixes: [String: [String]] = [:]

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        prefixes[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        prefixes[prefix]?.removeLast()
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        let element = MarkupElement(namespace: MarkupNamespace(uri: namespaceURI), name: elementName)
        for (qualifiedName, value) in attributes {
            let parts = qualifiedName.split(separator: ":", maxSplits: 1).map(String.init)
            let name: MarkupElement.AttributeName
            if parts.count == 2 {
                guard parts[0] != "xmlns" else { continue }
                name = .init(namespace: MarkupNamespace(uri: prefixes[parts[0]]?.last), name: parts[1])
            } else {
                guard qualifiedName != "xmlns" else { continue }
                name = .init(namespace: .none, name: qualifiedName)
            }
            element.attributes[name] = value
        }

        if let parent = stack.last {
            parent.children.append(element)
        } else {
            root = element
        }
        stack.append(element)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }
}
