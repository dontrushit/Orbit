import CoreGraphics
import Foundation
import os

/// Renders small page images for the page windows, one at a time on a background queue, and keeps
/// a bounded number of them, so a document with hundreds of pages costs no more than a screenful.
///
/// Rendering may block on CoreText, so it runs in a dispatch queue rather than in Swift concurrency.
public final class PDFThumbnailLoader: @unchecked Sendable {
    /// The longer side of a thumbnail, in pixels.
    public let maxPixelSize: Int

    private let queue = DispatchQueue(label: "dev.orbit.PDFTools.thumbnails", qos: .userInitiated)
    private let cache = NSCache<NSString, CGImage>()
    /// Pages still wanted on screen; a request for a page scrolled away before its turn is skipped.
    private let wanted = OSAllocatedUnfairLock(initialState: Set<PDFTools.PageReference>())
    /// Touched only on `queue`.
    private var documents: [URL: CGPDFDocument] = [:]
    private var pagesRendered = 0
    /// A CGPDFDocument keeps every page it has parsed, about 7 KB each; reopening documents now and then
    /// keeps a long scroll through thousands of pages from growing memory without bound.
    private static let pagesPerOpening = 200

    public init(maxPixelSize: Int, cacheLimit: Int = 16 << 20) {
        self.maxPixelSize = maxPixelSize
        cache.totalCostLimit = cacheLimit
    }

    public func cachedThumbnail(for page: PDFTools.PageReference) -> CGImage? {
        cache.object(forKey: Self.key(for: page))
    }

    /// Calls `completion` on the main queue with the image, or `nil` if the page can't be drawn.
    /// Not called if the request is cancelled before the page's turn.
    public func requestThumbnail(for page: PDFTools.PageReference, completion: @escaping @MainActor @Sendable (CGImage?) -> Void) {
        wanted.withLock { _ = $0.insert(page) }
        queue.async { [self] in
            guard wanted.withLock({ $0.remove(page) != nil }) else { return }
            let image = cachedThumbnail(for: page) ?? render(page)
            DispatchQueue.main.async { completion(image) }
        }
    }

    public func cancelThumbnail(for page: PDFTools.PageReference) {
        wanted.withLock { _ = $0.remove(page) }
    }

    private func render(_ reference: PDFTools.PageReference) -> CGImage? {
        autoreleasepool {
            guard let document = document(at: reference.document),
                  let page = document.page(at: reference.index + 1), // CGPDFDocument counts pages from 1
                  let image = Self.render(page, maxPixelSize: maxPixelSize)
            else { return nil }
            cache.setObject(image, forKey: Self.key(for: reference), cost: image.bytesPerRow * image.height)
            pagesRendered += 1
            if pagesRendered.isMultiple(of: Self.pagesPerOpening) {
                documents.removeAll()
            }
            return image
        }
    }

    private func document(at url: URL) -> CGPDFDocument? {
        if let document = documents[url] { return document }
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        if !document.isUnlocked { _ = document.unlockWithPassword("") }
        documents[url] = document
        return document
    }

    private static func key(for page: PDFTools.PageReference) -> NSString {
        "\(page.index) \(page.document.path)" as NSString
    }

    /// The page on white, scaled so that its longer side is `maxPixelSize`, turned as the page asks.
    static func render(_ page: CGPDFPage, maxPixelSize: Int) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let rotation = (page.rotationAngle % 360 + 360) % 360
        let size = rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = CGFloat(maxPixelSize) / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        // /Rotate turns the page clockwise. `getDrawingTransform` would do this too, but never scales up.
        switch rotation {
        case 90:
            context.translateBy(x: 0, y: size.height)
            context.rotate(by: -.pi / 2)
        case 180:
            context.translateBy(x: size.width, y: size.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: size.width, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
