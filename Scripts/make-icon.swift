#!/usr/bin/env swift
// Renders Orbit's app icon into App/Assets.xcassets/AppIcon.appiconset.
// Usage: swift Scripts/make-icon.swift (from the repository root)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let outputFolder = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// The macOS icon shape: a superellipse, which is closer to Apple's continuous corners than a rounded rect.
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0..<steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / exponent), c)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / exponent), s)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func drawIcon(in context: CGContext) {
    // Apple's grid: an 824 pt shape centered on the 1024 pt canvas, with a soft drop shadow.
    let shapeRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: shapeRect)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x000000, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(color(0x2F6BEA))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(0x3FA2FF), color(0x5A4FE0)]),
        start: CGPoint(x: shapeRect.midX, y: shapeRect.maxY),
        end: CGPoint(x: shapeRect.midX, y: shapeRect.minY),
        options: []
    )

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let orbitTilt: CGFloat = -0.42
    let orbitSize = CGSize(width: 640, height: 230)
    let orbitWidth: CGFloat = 34

    /// The whole ring goes behind the planet; the front (lower) half is drawn again on top of it.
    /// Opaque, so the overlapping halves don't show seams.
    func strokeOrbit(frontOnly: Bool) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: orbitTilt)
        if frontOnly {
            context.clip(to: CGRect(x: -canvas, y: -canvas, width: 2 * canvas, height: canvas))
        }
        context.addEllipse(in: CGRect(x: -orbitSize.width / 2, y: -orbitSize.height / 2, width: orbitSize.width, height: orbitSize.height))
        context.setLineWidth(orbitWidth)
        context.setStrokeColor(color(0xF7F9FF))
        context.strokePath()
        context.restoreGState()
    }

    strokeOrbit(frontOnly: false)

    // Planet, with a gap cut out along the front of the orbit so the orbit reads as passing in front of it.
    let planetRadius: CGFloat = 168
    let planetRect = CGRect(x: center.x - planetRadius, y: center.y - planetRadius, width: 2 * planetRadius, height: 2 * planetRadius)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.saveGState()
    context.addEllipse(in: planetRect)
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(0xFFFFFF), color(0xD5E0FF)]),
        start: CGPoint(x: planetRect.minX, y: planetRect.maxY),
        end: CGPoint(x: planetRect.maxX, y: planetRect.minY),
        options: []
    )
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: orbitTilt)
    context.clip(to: CGRect(x: -canvas, y: -canvas, width: 2 * canvas, height: canvas))
    context.addEllipse(in: CGRect(x: -orbitSize.width / 2, y: -orbitSize.height / 2, width: orbitSize.width, height: orbitSize.height))
    context.setLineWidth(orbitWidth + 36)
    context.setBlendMode(.clear)
    context.strokePath()
    context.restoreGState()
    context.endTransparencyLayer()

    strokeOrbit(frontOnly: true)

    // Satellite on the front of the orbit.
    let satelliteAngle: CGFloat = 1.72 * .pi
    let local = CGPoint(x: orbitSize.width / 2 * cos(satelliteAngle), y: orbitSize.height / 2 * sin(satelliteAngle))
    let satellite = local.applying(CGAffineTransform(rotationAngle: orbitTilt)).applying(CGAffineTransform(translationX: center.x, y: center.y))
    let satelliteRadius: CGFloat = 46
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0x1B1F6B, alpha: 0.35))
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: satellite.x - satelliteRadius, y: satellite.y - satelliteRadius, width: 2 * satelliteRadius, height: 2 * satelliteRadius))

    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Can't write \(url.path)") }
}

try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(render(pixels: points * scale), to: outputFolder.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputFolder.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) images to \(outputFolder.path)")
