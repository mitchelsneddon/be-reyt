#!/usr/bin/env swift  // Generates the app icon PNGs (1024x1024, opaque): a sun-over-horizon line glyph.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
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

func render(name: String, background: UInt32, glyph: UInt32) throws {
    guard
        let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("no context") }
    ctx.setFillColor(color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setStrokeColor(color(glyph))
    ctx.setLineWidth(52)
    ctx.setLineCap(.round)
    let cx = CGFloat(size) / 2
    let horizon: CGFloat = 342  // y up from the bottom
    let radius: CGFloat = 170
    // horizon line
    ctx.move(to: CGPoint(x: cx - 290, y: horizon))
    ctx.addLine(to: CGPoint(x: cx + 290, y: horizon))
    ctx.strokePath()
    // half circle above it
    ctx.addArc(center: CGPoint(x: cx, y: horizon), radius: radius, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()
    // three short rays
    for degrees in [90.0, 45.0, 135.0] {
        let a = degrees * .pi / 180
        let r0 = radius + 80
        let r1 = radius + 170
        ctx.move(to: CGPoint(x: cx + cos(a) * r0, y: horizon + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: cx + cos(a) * r1, y: horizon + sin(a) * r1))
        ctx.strokePath()
    }
    let url = outDir.appending(path: name)
    guard let image = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("no destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
}

try render(name: "AppIcon.png", background: 0xFAF7F2, glyph: 0xB8613F)
try render(name: "AppIcon-Dark.png", background: 0x161514, glyph: 0xE08A6A)
// Tinted: iOS applies the tint to a greyscale image, so white glyph on black.
try render(name: "AppIcon-Tinted.png", background: 0x000000, glyph: 0xFFFFFF)
