#!/usr/bin/env swift  // Generates the app icon PNGs (1024x1024, opaque): the midnight "be reyt" wordmark with a gold dot.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
// Run from the repo root: the bundled font is resolved relative to the working directory.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let fontURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(path: "App/Resources/Fonts/PlayfairDisplay-MediumItalic.ttf")

guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
    let descriptor = descriptors.first
else { fatalError("could not load font at \(fontURL.path), run from the repo root") }
let font = CTFontCreateWithFontDescriptor(descriptor, 350, nil)

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(name: String, background: UInt32, text: UInt32, dot: UInt32) throws {
    guard
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("no context") }
    ctx.setFillColor(color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Coordinates are SVG-style (y down); CoreGraphics is y up, so flip each y.
    func word(_ string: String, baselineY: CGFloat) {
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(text),
            ])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: 512 - width / 2, y: CGFloat(size) - baselineY)
        CTLineDraw(line, ctx)
    }
    word("be", baselineY: 478)
    word("reyt", baselineY: 768)

    ctx.setFillColor(color(dot))
    ctx.fillEllipse(in: CGRect(x: 712 - 36, y: CGFloat(size) - 460 - 36, width: 72, height: 72))

    let url = outDir.appending(path: name)
    guard let image = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("no destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
}

try render(name: "AppIcon.png", background: 0x0D1522, text: 0xFFFFFF, dot: 0xD9A54A)
try render(name: "AppIcon-Dark.png", background: 0x07090D, text: 0xFFFFFF, dot: 0xD9A54A)
try render(name: "AppIcon-Tinted.png", background: 0x1C1C1E, text: 0xE6E6E6, dot: 0xA8A8A8)
