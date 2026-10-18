import AppKit
import ImageIO

extension DocumentBuilder {
    // MARK: DrawingML

    func appendDrawing(_ element: MarkupElement, properties: RunProperties, to content: inout ParagraphContent, story: Story, context: BlockContext) {
        guard let frame = element.child("inline", in: .wp) ?? element.child("anchor", in: .wp),
              let extent = frame.child("extent", in: .wp),
              let width = Measure.emu(extent.attribute("cx", in: .none)),
              let height = Measure.emu(extent.attribute("cy", in: .none)),
              width > 0, height > 0,
              let graphic = frame.child("graphic", in: .a)?.child("graphicData", in: .a)
        else { return }

        let isFloating = frame.is("anchor", in: .wp) && frame.child("wrapNone", in: .wp) != nil
        if isFloating {
            let size = CGSize(width: width, height: height)
            guard let drawing = makeDrawing(graphic, size: size, story: story), !drawing.isUnsupported else { return }
            content.floating.append(FloatingDrawing(
                drawing: drawing,
                horizontal: Self.axis(frame.child("positionH", in: .wp)),
                vertical: Self.axis(frame.child("positionV", in: .wp)),
                isBehindText: MarkupElement.isOn(frame.attribute("behindDoc", in: .none) ?? "0")
            ))
        } else {
            // Pictures that wrap text are placed in the line where they're anchored.
            let size = fitted(CGSize(width: width, height: height), width: context.width)
            let drawing = makeDrawing(graphic, size: size, story: story) ?? Drawing(size: size, content: .unsupported)
            content.text.append(drawing.attachment(attributes: styler.attributes(for: properties, text: "")))
        }
    }

    private func makeDrawing(_ graphic: MarkupElement, size: CGSize, story: Story) -> Drawing? {
        if let picture = graphic.child("pic", in: .picture) {
            let fill = picture.child("blipFill", in: .picture)
            guard let blip = fill?.child("blip", in: .a), let id = blip.attribute("embed", in: .r) else { return nil }
            return Drawing(size: size, content: image(id, story: story, size: size, crop: fill?.child("srcRect", in: .a)))
        }
        if let shape = graphic.child("wsp", in: .wordShape) {
            return makeShape(shape, size: size, story: story)
        }
        // Groups, charts and SmartArt keep their space.
        return Drawing(size: size, content: .unsupported)
    }

    private func makeShape(_ shape: MarkupElement, size: CGSize, story: Story) -> Drawing? {
        let shapeProperties = shape.child("spPr", in: .wordShape)
        let geometry = shapeProperties?.child("prstGeom", in: .a)?.attribute("prst", in: .none) ?? "rect"
        let style = shape.child("style", in: .wordShape)
        let fill = shapeFill(shapeProperties, style: style)
        let outline = shapeOutline(shapeProperties, style: style)

        var insets = NSEdgeInsets(top: 3.6, left: 7.2, bottom: 3.6, right: 7.2)
        if let body = shape.child("bodyPr", in: .wordShape) {
            insets.left = Measure.emu(body.attribute("lIns", in: .none)) ?? insets.left
            insets.top = Measure.emu(body.attribute("tIns", in: .none)) ?? insets.top
            insets.right = Measure.emu(body.attribute("rIns", in: .none)) ?? insets.right
            insets.bottom = Measure.emu(body.attribute("bIns", in: .none)) ?? insets.bottom
        }

        let boxContent = shape.child("txbx", in: .wordShape)?.child("txbxContent")
        // A text box keeps its text whatever its shape. A shape without text is drawn only
        // when it's a visible rectangle: other geometries would need paths of their own.
        if boxContent == nil, !["rect", "roundRect"].contains(geometry) || (fill == nil && outline == nil) {
            return nil
        }
        let text = boxContent.map { buildStory($0.children, story: story, width: max(size.width - insets.left - insets.right, 1)) }
        return Drawing(size: size, content: .text(text ?? NSAttributedString(), insets: insets), fill: fill, outline: outline)
    }

    private func shapeFill(_ properties: MarkupElement?, style: MarkupElement?) -> RGBColor? {
        if let properties {
            if properties.child("noFill", in: .a) != nil { return nil }
            if let solid = properties.child("solidFill", in: .a) { return drawingColor(solid) }
        }
        guard let reference = style?.child("fillRef", in: .a), reference.attribute("idx", in: .none) != "0" else { return nil }
        return drawingColor(reference)
    }

    private func shapeOutline(_ properties: MarkupElement?, style: MarkupElement?) -> Drawing.Outline? {
        let line = properties?.child("ln", in: .a)
        if line?.child("noFill", in: .a) != nil { return nil }
        let width = Measure.emu(line?.attribute("w", in: .none)) ?? 0.75
        if let solid = line?.child("solidFill", in: .a), let color = drawingColor(solid) {
            return Drawing.Outline(color: color, width: width)
        }
        guard let reference = style?.child("lnRef", in: .a), reference.attribute("idx", in: .none) != "0",
              let color = drawingColor(reference)
        else { return nil }
        return Drawing.Outline(color: color, width: width)
    }

    /// The color inside a DrawingML fill or style reference.
    private func drawingColor(_ element: MarkupElement) -> RGBColor? {
        if let rgb = element.child("srgbClr", in: .a) {
            return RGBColor(hex: rgb.attribute("val", in: .none))
        }
        if let scheme = element.child("schemeClr", in: .a)?.attribute("val", in: .none) {
            return theme.color(named: scheme)
        }
        if let system = element.child("sysClr", in: .a) {
            return RGBColor(hex: system.attribute("lastClr", in: .none))
        }
        return nil
    }

    private static func axis(_ position: MarkupElement?) -> FloatingDrawing.Axis {
        let origin: FloatingDrawing.Origin = switch position?.attribute("relativeFrom", in: .none) {
        case "page", "leftMargin", "topMargin", "rightMargin", "bottomMargin": .page
        case "paragraph", "line": .paragraph
        default: .margin
        }
        if let offset = Measure.emu(position?.child("posOffset", in: .wp)?.text) {
            return .init(origin: origin, placement: .offset(offset))
        }
        let placement: FloatingDrawing.Placement = switch position?.child("align", in: .wp)?.text {
        case "center": .center
        case "right", "bottom", "outside": .trailing
        default: .leading
        }
        return .init(origin: origin, placement: placement)
    }

    // MARK: VML

    /// Legacy drawings: OLE object previews (such as equations), old text boxes and pictures.
    func appendVML(_ element: MarkupElement, properties: RunProperties, to content: inout ParagraphContent, story: Story, context: BlockContext) {
        let shapeNames = ["shape", "rect", "roundrect", "oval", "image"]
        guard let shape = element.children.first(where: { $0.namespace == .vml && shapeNames.contains($0.name) }) else { return }
        let style = VMLStyle(shape.attribute("style", in: .none) ?? "")

        var size = style.size
        if size == nil, let width = Measure.twips(element.attribute("dxaOrig")), let height = Measure.twips(element.attribute("dyaOrig")) {
            size = CGSize(width: width, height: height)
        }
        guard let size, size.width > 0, size.height > 0 else { return }

        let drawing: Drawing
        if let id = shape.child("imagedata", in: .vml)?.attribute("id", in: .r) {
            drawing = Drawing(size: size, content: image(id, story: story, size: size, crop: nil))
        } else if let box = shape.child("textbox", in: .vml)?.child("txbxContent") {
            let insets = NSEdgeInsets(top: 3.6, left: 7.2, bottom: 3.6, right: 7.2)
            let text = buildStory(box.children, story: story, width: max(size.width - insets.left - insets.right, 1))
            let fill = shape.attribute("filled", in: .none) == "f" ? nil : VMLStyle.color(shape.attribute("fillcolor", in: .none)) ?? .white
            let outline = shape.attribute("stroked", in: .none) == "f" ? nil : Drawing.Outline(
                color: VMLStyle.color(shape.attribute("strokecolor", in: .none)) ?? .black,
                width: shape.attribute("strokeweight", in: .none).flatMap(Measure.universal) ?? 0.75
            )
            drawing = Drawing(size: size, content: .text(text, insets: insets), fill: fill, outline: outline)
        } else {
            return
        }

        if style.isAbsolute {
            guard !drawing.isUnsupported else { return }
            content.floating.append(FloatingDrawing(
                drawing: drawing,
                horizontal: .init(origin: style.horizontalOrigin, placement: .offset(style.left)),
                vertical: .init(origin: style.verticalOrigin, placement: .offset(style.top)),
                isBehindText: style.isBehindText
            ))
        } else {
            let fittedSize = fitted(size, width: context.width)
            let inline = fittedSize == size ? drawing : Drawing(size: fittedSize, content: drawing.content, fill: drawing.fill, outline: drawing.outline)
            content.text.append(inline.attachment(attributes: styler.attributes(for: properties, text: "")))
        }
    }

    // MARK: Images

    /// Pictures are kept at most this sharp, as Word does when it saves a PDF (at 220 ppi by default).
    static let maxImageResolution: CGFloat = 300

    /// Decoded image of the relationship, cached: documents often repeat a logo in every header.
    /// - Parameter size: The size the picture is shown at, in points.
    private func image(_ relationshipID: String, story: Story, size: CGSize, crop: MarkupElement?) -> Drawing.Content {
        guard let relationship = story.relationships[relationshipID], !relationship.isExternal else { return .unsupported }
        let maxPixels = Int((max(size.width, size.height) / 72 * Self.maxImageResolution).rounded(.up))
        let key = "\(relationship.target)@\(maxPixels)"
        let content: Drawing.Content
        if let cached = images[key] {
            content = cached
        } else {
            content = Self.decodeImage((try? package.data(at: relationship.target)) ?? nil, maxPixels: maxPixels)
            images[key] = content
        }
        guard case .image(let image) = content, let crop else { return content }
        return .image(Self.crop(image, rect: crop))
    }

    private static func decodeImage(_ data: Data?, maxPixels: Int) -> Drawing.Content {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return .unsupported }
        // JPEG goes into the PDF as is, without decoding or recompressing; anything else is decoded and
        // stored losslessly, so oversized pictures are scaled down while reading, without decoding them in full.
        let isJPEG = (CGImageSourceGetType(source) as String?) == "public.jpeg"
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1),
            kCGImageSourceCreateThumbnailWithTransform: false,
        ]
        let image = isJPEG
            ? CGImageSourceCreateImageAtIndex(source, 0, nil)
            : CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return image.map(Drawing.Content.image) ?? .unsupported
    }

    /// `a:srcRect` gives the cropped amount on each side in thousandths of a percent.
    private static func crop(_ image: CGImage, rect: MarkupElement) -> CGImage {
        func fraction(_ name: String) -> CGFloat { CGFloat(Double(rect.attribute(name, in: .none) ?? "0") ?? 0) / 100_000 }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let cropped = CGRect(
            x: width * fraction("l"), y: height * fraction("t"),
            width: width * (1 - fraction("l") - fraction("r")), height: height * (1 - fraction("t") - fraction("b"))
        ).integral
        guard cropped.width >= 1, cropped.height >= 1, cropped != CGRect(x: 0, y: 0, width: width, height: height) else { return image }
        return image.cropping(to: cropped) ?? image
    }

    /// Scales a size down to fit the available width and the page's text height.
    func fitted(_ size: CGSize, width: CGFloat) -> CGSize {
        let scale = min(1, width / size.width, page.contentRect.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

extension Drawing {
    var isUnsupported: Bool {
        if case .unsupported = content { true } else { false }
    }
}

/// The CSS-like `style` attribute of VML shapes.
private struct VMLStyle {
    private var values: [String: String] = [:]

    init(_ style: String) {
        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                values[parts[0].lowercased()] = parts[1]
            }
        }
    }

    var size: CGSize? {
        guard let width = length("width"), let height = length("height") else { return nil }
        return CGSize(width: width, height: height)
    }

    var isAbsolute: Bool { values["position"] == "absolute" }
    var left: CGFloat { length("margin-left") ?? length("left") ?? 0 }
    var top: CGFloat { length("margin-top") ?? length("top") ?? 0 }
    var isBehindText: Bool { (values["z-index"].flatMap(Int.init) ?? 0) < 0 }

    var horizontalOrigin: FloatingDrawing.Origin {
        switch values["mso-position-horizontal-relative"] {
        case "page": .page
        default: .margin
        }
    }

    var verticalOrigin: FloatingDrawing.Origin {
        switch values["mso-position-vertical-relative"] {
        case "page": .page
        case "margin": .margin
        default: .paragraph
        }
    }

    /// Lengths without a unit are pixels at 96 dpi, 0.75 pt each.
    private func length(_ name: String) -> CGFloat? {
        guard let value = values[name] else { return nil }
        if let number = Double(value) { return CGFloat(number) * 0.75 }
        return Measure.universal(value)
    }

    /// "#1F4E79", "#fff" or a few named colors.
    static func color(_ value: String?) -> RGBColor? {
        guard var value = value?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        if let space = value.firstIndex(of: " ") {
            value = String(value[..<space])
        }
        let named = ["black": "000000", "white": "ffffff", "red": "ff0000", "green": "008000", "blue": "0000ff", "yellow": "ffff00", "gray": "808080"]
        if let hex = named[value] { return RGBColor(hex: hex) }
        guard value.hasPrefix("#") else { return nil }
        var hex = String(value.dropFirst())
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        return RGBColor(hex: hex)
    }
}
