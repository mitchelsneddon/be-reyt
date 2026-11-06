#!/usr/bin/env swift  // Generates the app icon PNGs (1024x1024, opaque, full-bleed; iOS masks the corners): "the page", a tilted page with three lines and a gold dot.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
// The drawing is defined in a 100x100 SVG-style space (y down) and scaled to the bitmap.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(name: String, background: UInt32, page: UInt32, dot: UInt32) throws {
    guard
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("no context") }
    ctx.setFillColor(color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // SVG space: y down, 100 units across. The flip keeps rotation the same sense as SVG's rotate().
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: CGFloat(size) / 100, y: CGFloat(size) / 100)

    // rotate(-6 50 50)
    ctx.translateBy(x: 50, y: 50)
    ctx.rotate(by: -6 * .pi / 180)
    ctx.translateBy(x: -50, y: -50)

    ctx.setFillColor(color(page))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 27, y: 19, width: 46, height: 62), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
    ctx.fillPath()

    ctx.setStrokeColor(color(background))
    ctx.setLineWidth(3.2)
    ctx.setLineCap(.round)
    for (a, b) in [((35, 35), (65, 35)), ((35, 45), (65, 45)), ((35, 55), (53, 55))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
        ctx.move(to: CGPoint(x: a.0, y: a.1))
        ctx.addLine(to: CGPoint(x: b.0, y: b.1))
        ctx.strokePath()
    }

    ctx.setFillColor(color(dot))
    ctx.fillEllipse(in: CGRect(x: 60 - 3.8, y: 55 - 3.8, width: 7.6, height: 7.6))

    let url = outDir.appending(path: name)
    guard let image = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("no destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
}

try render(name: "AppIcon.png", background: 0x0D1522, page: 0xFBF8F1, dot: 0xD9A54A)
try render(name: "AppIcon-Dark.png", background: 0x07090D, page: 0xE9E3D6, dot: 0xD9A54A)
try render(name: "AppIcon-Tinted.png", background: 0x1C1C1E, page: 0xE6E6E6, dot: 0x7A7A7A)
