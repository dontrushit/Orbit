import CoreGraphics
import Foundation
import PDFKit
import Testing

enum PDFFixture {
    /// Writes a PDF whose pages are as wide as `widths`, so tests can tell pages apart by size.
    @discardableResult
    static func write(to url: URL, widths: [CGFloat], password: String? = nil) throws -> URL {
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        let context = try #require(CGContext(url as CFURL, mediaBox: nil, info as CFDictionary))
        for width in widths {
            var box = CGRect(x: 0, y: 0, width: width, height: 100)
            context.beginPage(mediaBox: &box)
            context.fill(box.insetBy(dx: 10, dy: 10))
            context.endPage()
        }
        context.closePDF()
        return url
    }

    static func pageWidths(_ url: URL) throws -> [CGFloat] {
        let document = try #require(PDFDocument(url: url))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .mediaBox).width }
    }
}
