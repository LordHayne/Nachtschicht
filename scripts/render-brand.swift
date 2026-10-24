// Draws Nightforge's brand images: the N mark (brushed metal with a blue light seam), the app icon,
// the README banner and the DMG window background. Run: swift scripts/render-brand.swift
// Writes Resources/AppIcon.png (1024 px, used by build.sh), docs/images/{banner,mark}.png and
// Resources/dmg/background{,@2x}.png (used by scripts/dmg-settings.py).

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let seamBlue = NSColor(srgbRed: 0.18, green: 0.48, blue: 1.0, alpha: 1)

/// The three pieces of the N in a 332 × 440 box (origin top left), from the original design.
let pieces: [[CGPoint]] = [
    // diagonal slab, with the upper half of the left stem
    [CGPoint(x: 0, y: 0), CGPoint(x: 332, y: 308), CGPoint(x: 332, y: 440), CGPoint(x: 49, y: 170), CGPoint(x: 0, y: 128)],
    // lower part of the left stem
    [CGPoint(x: 0, y: 170), CGPoint(x: 82, y: 236), CGPoint(x: 82, y: 338), CGPoint(x: 0, y: 432)],
    // right stem
    [CGPoint(x: 249, y: 100), CGPoint(x: 332, y: 24), CGPoint(x: 332, y: 280), CGPoint(x: 249, y: 204)],
]
/// The light seam runs along the slab's lower edge.
let seam = (CGPoint(x: 49, y: 170), CGPoint(x: 332, y: 440))
let glyphSize = CGSize(width: 332, height: 440)

/// Same streaks on every run, so re-rendering doesn't change images that didn't change.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {  // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func render(size: CGSize, to url: URL, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    // Top-left origin, like the coordinates above.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

func path(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

/// The N with its top left corner at `origin`, `scale` × the design size.
func drawMark(_ context: CGContext, origin: CGPoint, scale: CGFloat) {
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.scaleBy(x: scale, y: scale)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    for (index, points) in pieces.enumerated() {
        let shape = path(points)
        // Drop shadow for depth.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: NSColor.black.withAlphaComponent(0.7).cgColor)
        context.addPath(shape)
        context.setFillColor(NSColor(white: 0.35, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()

        // Brushed metal: a cool diagonal gradient plus fine streaks.
        context.saveGState()
        context.addPath(shape)
        context.clip()
        let metal = CGGradient(colorsSpace: colorSpace, colors: [
            NSColor(srgbRed: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor,
            NSColor(srgbRed: 0.55, green: 0.58, blue: 0.63, alpha: 1).cgColor,
            NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 0.55, 1])!
        let box = shape.boundingBox
        context.drawLinearGradient(metal, start: CGPoint(x: box.minX, y: box.minY - (index == 0 ? 0 : 60)),
                                   end: CGPoint(x: box.maxX, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        var generator = SeededGenerator(seed: UInt64(index) + 1)
        for _ in 0..<260 {
            let y = CGFloat.random(in: -440...880, using: &generator)
            context.setStrokeColor(NSColor(white: Bool.random(using: &generator) ? 1 : 0, alpha: CGFloat.random(in: 0.02...0.07, using: &generator)).cgColor)
            context.setLineWidth(CGFloat.random(in: 0.5...1.6, using: &generator))
            context.move(to: CGPoint(x: -40, y: y))
            context.addLine(to: CGPoint(x: 372, y: y + 345))
            context.strokePath()
        }
        context.restoreGState()

        // Bevel: light top edge, dark outline.
        context.addPath(shape)
        context.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor)
        context.setLineWidth(2)
        context.strokePath()
    }

    // The light seam: a wide blue glow, then a bright core.
    context.setLineCap(.round)
    for (width, alpha, blur) in [(14.0, 0.35, 40.0), (6.0, 0.8, 18.0), (2.2, 1.0, 6.0)] {
        context.saveGState()
        context.setShadow(offset: .zero, blur: blur, color: seamBlue.cgColor)
        context.setStrokeColor(seamBlue.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(width)
        context.move(to: seam.0)
        context.addLine(to: seam.1)
        context.strokePath()
        context.restoreGState()
    }
    context.setStrokeColor(NSColor(srgbRed: 0.75, green: 0.87, blue: 1, alpha: 0.95).cgColor)
    context.setLineWidth(1.1)
    context.move(to: seam.0)
    context.addLine(to: seam.1)
    context.strokePath()
    context.restoreGState()
}

func nightBackground(_ context: CGContext, in rect: CGRect) {
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1).cgColor,
        NSColor(srgbRed: 0.025, green: 0.03, blue: 0.045, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    // A faint blue haze behind the mark.
    let haze = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        seamBlue.withAlphaComponent(0.16).cgColor, seamBlue.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(haze, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                               endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: min(rect.width, rect.height) * 0.55, options: [])
}

// App icon: macOS grid, 824 px rounded square inside a 1024 px canvas.
render(size: CGSize(width: 1024, height: 1024), to: root.appendingPathComponent("Resources/AppIcon.png")) { context in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(shape)
    context.clip()
    nightBackground(context, in: tile)
    context.restoreGState()
    context.addPath(shape)
    context.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    context.setLineWidth(3)
    context.strokePath()
    let scale: CGFloat = 520 / glyphSize.height
    drawMark(context, origin: CGPoint(x: 512 - glyphSize.width * scale / 2, y: 512 - glyphSize.height * scale / 2), scale: scale)
}

// Transparent mark for the README.
render(size: CGSize(width: 480, height: 600), to: root.appendingPathComponent("docs/images/mark.png")) { context in
    drawMark(context, origin: CGPoint(x: 74, y: 80), scale: 1)
}

// README banner: mark, wordmark and tagline on the night background.
render(size: CGSize(width: 1600, height: 720), to: root.appendingPathComponent("docs/images/banner.png")) { context in
    nightBackground(context, in: CGRect(x: 0, y: 0, width: 1600, height: 720))
    let scale: CGFloat = 0.78
    drawMark(context, origin: CGPoint(x: 800 - glyphSize.width * scale / 2, y: 70), scale: scale)

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, kern: CGFloat, color: NSColor, centerY: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight, width: .expanded)
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .kern: kern, .foregroundColor: color])
        let bounds = attributed.size()
        context.saveGState()
        // Text draws in AppKit's flipped-back space.
        context.textMatrix = .identity
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        attributed.draw(at: CGPoint(x: 800 - (bounds.width - kern) / 2, y: centerY - bounds.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
    text("NIGHTFORGE", size: 74, weight: .light, kern: 22, color: NSColor(white: 0.9, alpha: 1), centerY: 525)
    text("EVERY GAME. ONE PLACE.", size: 22, weight: .regular, kern: 9,
         color: NSColor(srgbRed: 0.55, green: 0.66, blue: 0.86, alpha: 1), centerY: 610)
}

/// Centred text in a top-left-origin context, wrapped to `width`.
func drawText(_ context: CGContext, _ string: String, font: NSFont, kern: CGFloat = 0, color: NSColor,
              centerX: CGFloat, top: CGFloat, width: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributed = NSAttributedString(string: string, attributes: [
        .font: font, .kern: kern, .foregroundColor: color, .paragraphStyle: style,
    ])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    attributed.draw(with: CGRect(x: centerX - width / 2, y: top, width: width, height: 200),
                    options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

// DMG window: app on the left, Applications on the right (positions in scripts/dmg-settings.py),
// an arrow in the logo's light between them. Finder writes the icon names itself, in black or
// white depending on the Mac's appearance, so they sit on mid-grey tags that work for both.
let dmgSize = CGSize(width: 660, height: 420)
let dmgIcons = (app: CGPoint(x: 170, y: 190), applications: CGPoint(x: 490, y: 190))
for scale in [1, 2] as [CGFloat] {
    let name = scale == 1 ? "background.png" : "background@2x.png"
    render(size: CGSize(width: dmgSize.width * scale, height: dmgSize.height * scale),
           to: root.appendingPathComponent("Resources/dmg/\(name)")) { context in
        context.scaleBy(x: scale, y: scale)
        nightBackground(context, in: CGRect(origin: .zero, size: dmgSize))

        drawText(context, "NIGHTFORGE", font: NSFont.systemFont(ofSize: 17, weight: .light, width: .expanded),
                 kern: 7, color: NSColor(white: 0.88, alpha: 1), centerX: 330, top: 34, width: 400)

        // Name tags behind Finder's labels.
        for center in [dmgIcons.app, dmgIcons.applications] {
            let tag = CGRect(x: center.x - 70, y: center.y + 72, width: 140, height: 24)
            context.addPath(CGPath(roundedRect: tag, cornerWidth: 12, cornerHeight: 12, transform: nil))
            context.setFillColor(NSColor(srgbRed: 0.50, green: 0.53, blue: 0.60, alpha: 0.92).cgColor)
            context.fillPath()
        }

        // Arrow: glowing seam with a chevron head.
        let from = CGPoint(x: dmgIcons.app.x + 92, y: dmgIcons.app.y)
        let to = CGPoint(x: dmgIcons.applications.x - 92, y: dmgIcons.applications.y)
        let arrow = CGMutablePath()
        arrow.move(to: from)
        arrow.addLine(to: to)
        arrow.move(to: CGPoint(x: to.x - 14, y: to.y - 12))
        arrow.addLine(to: to)
        arrow.addLine(to: CGPoint(x: to.x - 14, y: to.y + 12))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (width, alpha, blur) in [(8.0, 0.35, 22.0), (3.0, 0.85, 8.0)] {
            context.saveGState()
            context.setShadow(offset: .zero, blur: blur, color: seamBlue.cgColor)
            context.setStrokeColor(seamBlue.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width)
            context.addPath(arrow)
            context.strokePath()
            context.restoreGState()
        }
        context.setStrokeColor(NSColor(srgbRed: 0.78, green: 0.88, blue: 1, alpha: 1).cgColor)
        context.setLineWidth(1.4)
        context.addPath(arrow)
        context.strokePath()

        drawText(context, "Drag Nightforge into Applications",
                 font: NSFont.systemFont(ofSize: 15, weight: .medium), color: NSColor(white: 0.92, alpha: 1),
                 centerX: 330, top: 318, width: 560)
        drawText(context, "First start: if macOS can't verify the app, open\nSystem Settings › Privacy & Security and click Open Anyway.",
                 font: NSFont.systemFont(ofSize: 11.5), color: NSColor(srgbRed: 0.60, green: 0.66, blue: 0.78, alpha: 1),
                 centerX: 330, top: 348, width: 520)
    }
}
