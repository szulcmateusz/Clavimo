// Renders Clavimo's app icon and menu bar glyphs from vector geometry.
//
// Usage: swift scripts/render-icon.swift <output-dir>
// Produces:
//   AppIcon.icns                       app icon, all sizes
//   AppIcon-1024.png                   preview of the full icon
//   MenuBarIcon.pdf                    template glyph, active
//   MenuBarIcon-paused.pdf             template glyph, paused (dimmed)
//   MenuBarIcon-attention.pdf          template glyph with a badge
//
// The mark: a keycap and a mouse outline linked like two chain links,
// keyboard and mouse working as one.

import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

enum Brand {
    static let tileTop = color(0x2B2752)
    static let tileBottom = color(0x0D0B1F)
    static let keycapLight = color(0xB9A9FF)
    static let keycapShade = color(0x8C76F2)
    static let mintLight = color(0x8AF3E3)
    static let mintDeep = color(0x3FD8C4)
}

// Geometry in a 1024 x 1024 canvas, y pointing up. Centerlines of the
// two rings; the stroke width is applied when drawing.
enum Mark {
    static let ringWidth: CGFloat = 58
    static let keycap = CGRect(x: 262, y: 254, width: 318, height: 286)
    static let keycapRadius: CGFloat = 70
    static let mouse = CGRect(x: 496, y: 400, width: 257, height: 370)
    static let wheel = CGRect(x: 606, y: 624, width: 38, height: 100)
    /// Where the keycap passes over the mouse; elsewhere the mouse is on top.
    static let keycapOverMouse = CGPoint(x: 580, y: 408)

    static var keycapPath: CGPath {
        CGPath(roundedRect: keycap, cornerWidth: keycapRadius, cornerHeight: keycapRadius, transform: nil)
    }

    static var mousePath: CGPath {
        CGPath(roundedRect: mouse, cornerWidth: mouse.width / 2, cornerHeight: mouse.width / 2, transform: nil)
    }

    static var wheelPath: CGPath {
        CGPath(roundedRect: wheel, cornerWidth: wheel.width / 2, cornerHeight: wheel.width / 2, transform: nil)
    }
}

func gradientFill(_ ctx: CGContext, clip path: CGPath, top: CGColor, bottom: CGColor, from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: srgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func strokedPath(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func drawKeycapRing(_ ctx: CGContext, shadow: Bool = true) {
    let ring = strokedPath(Mark.keycapPath, width: Mark.ringWidth)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x0B0640, 0.45))
        ctx.addPath(ring)
        ctx.setFillColor(Brand.keycapShade)
        ctx.fillPath()
        ctx.restoreGState()
    }
    gradientFill(ctx, clip: ring, top: Brand.keycapLight, bottom: Brand.keycapShade,
                 from: CGPoint(x: 0, y: Mark.keycap.maxY + 30), to: CGPoint(x: 0, y: Mark.keycap.minY - 30))
}

func drawMouseRing(_ ctx: CGContext) {
    let ring = strokedPath(Mark.mousePath, width: Mark.ringWidth)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x0B0640, 0.45))
    ctx.addPath(ring)
    ctx.setFillColor(Brand.mintDeep)
    ctx.fillPath()
    ctx.restoreGState()
    gradientFill(ctx, clip: ring, top: Brand.mintLight, bottom: Brand.mintDeep,
                 from: CGPoint(x: 0, y: Mark.mouse.maxY + 30), to: CGPoint(x: 0, y: Mark.mouse.minY - 30))
    gradientFill(ctx, clip: Mark.wheelPath, top: Brand.mintLight, bottom: Brand.mintDeep,
                 from: CGPoint(x: 0, y: Mark.wheel.maxY), to: CGPoint(x: 0, y: Mark.wheel.minY))
}

func drawIcon(_ ctx: CGContext) {
    // Tile on the standard macOS icon grid: 824 x 824 centered.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(Brand.tileBottom)
    ctx.fillPath()
    ctx.restoreGState()
    gradientFill(ctx, clip: tilePath, top: Brand.tileTop, bottom: Brand.tileBottom,
                 from: CGPoint(x: 220, y: 924), to: CGPoint(x: 800, y: 100))
    // Soft top highlight for depth.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let glow = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 900), endRadius: 620, options: [])
    ctx.restoreGState()

    // The rings: mouse over keycap, except at one crossing where the keycap
    // passes over, so the two links read as interlocked.
    drawKeycapRing(ctx)
    drawMouseRing(ctx)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: Mark.keycapOverMouse.x - 64, y: Mark.keycapOverMouse.y - 64, width: 128, height: 128))
    ctx.clip()
    // No shadow here: a shadow clipped to the crossing would show its edge.
    drawKeycapRing(ctx, shadow: false)
    ctx.restoreGState()
}

/// Monochrome glyph for the menu bar: the same geometry built as one
/// filled shape, with small gaps instead of shading at the crossings.
/// Boolean path operations are used because PDF has no clear blend mode.
func glyphPath(badge: Bool) -> CGPath {
    let width: CGFloat = 62
    let gap: CGFloat = 34
    let keycapRing = strokedPath(Mark.keycapPath, width: width)
    let mouseRing = strokedPath(Mark.mousePath, width: width)
    let keycapHalo = strokedPath(Mark.keycapPath, width: width + 2 * gap)
    let mouseHalo = strokedPath(Mark.mousePath, width: width + 2 * gap)
    let crossing = CGPath(ellipseIn: CGRect(x: Mark.keycapOverMouse.x - 90, y: Mark.keycapOverMouse.y - 90, width: 180, height: 180), transform: nil)
    // The mouse passes over the keycap everywhere except at the crossing.
    let keycap = keycapRing.subtracting(mouseHalo.subtracting(crossing))
    let mouse = mouseRing.subtracting(keycapHalo.intersection(crossing))
    var glyph = keycap.union(mouse).union(Mark.wheelPath)
    if badge {
        let dot = CGRect(x: 650, y: 230, width: 150, height: 150)
        glyph = glyph.subtracting(CGPath(ellipseIn: dot.insetBy(dx: -36, dy: -36), transform: nil))
            .union(CGPath(ellipseIn: dot, transform: nil))
    }
    return glyph
}

func drawGlyph(_ ctx: CGContext, alpha: CGFloat, badge: Bool) {
    // Center the mark (x 233...800, y 225...799) in a 640 x 640 box.
    ctx.translateBy(x: -197, y: -192)
    ctx.addPath(glyphPath(badge: badge))
    ctx.setFillColor(CGColor(gray: 0, alpha: alpha))
    ctx.fillPath()
}

func bitmap(_ size: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

// App icon.
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(bitmap(points * scale, drawIcon), to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try writePNG(bitmap(1024, drawIcon), to: output.appendingPathComponent("AppIcon-1024.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

// Menu bar glyphs as vector PDFs (18 x 18 pt).
for (name, alpha, badge) in [("MenuBarIcon", 1.0, false), ("MenuBarIcon-paused", 0.4, false), ("MenuBarIcon-attention", 1.0, true)] {
    var box = CGRect(x: 0, y: 0, width: 18, height: 18)
    let url = output.appendingPathComponent("\(name).pdf") as CFURL
    let pdf = CGContext(url, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    pdf.scaleBy(x: 18 / 640, y: 18 / 640)
    drawGlyph(pdf, alpha: CGFloat(alpha), badge: badge)
    pdf.endPDFPage()
    pdf.closePDF()
}
print("Rendered icons to \(output.path)")
