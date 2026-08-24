// Renders the MetWho app icon to PNG.
//   swift tools/makeicon.swift <out.png> [size]
//
// The mark: a black squircle card on white, a white ribbon tab hanging off its
// top edge, and two people below it. A card you file someone into — which is
// what the app is.

import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let S = CommandLine.arguments.count > 2 ? CGFloat(Int(CommandLine.arguments[2]) ?? 1024) : 1024

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// iOS masks the icon itself, so the artwork is a full square of white.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

/// An Apple-style continuous corner, not a circular arc.
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = radius * 1.28   // continuous-curvature control offset
    let (x, y, w, h) = (r.minX, r.minY, r.width, r.height)
    p.move(to: CGPoint(x: x + radius, y: y))
    p.addLine(to: CGPoint(x: x + w - radius, y: y))
    p.addCurve(to: CGPoint(x: x + w, y: y + radius),
               control1: CGPoint(x: x + w - radius + k * 0.55, y: y),
               control2: CGPoint(x: x + w, y: y + radius - k * 0.55))
    p.addLine(to: CGPoint(x: x + w, y: y + h - radius))
    p.addCurve(to: CGPoint(x: x + w - radius, y: y + h),
               control1: CGPoint(x: x + w, y: y + h - radius + k * 0.55),
               control2: CGPoint(x: x + w - radius + k * 0.55, y: y + h))
    p.addLine(to: CGPoint(x: x + radius, y: y + h))
    p.addCurve(to: CGPoint(x: x, y: y + h - radius),
               control1: CGPoint(x: x + radius - k * 0.55, y: y + h),
               control2: CGPoint(x: x, y: y + h - radius + k * 0.55))
    p.addLine(to: CGPoint(x: x, y: y + radius))
    p.addCurve(to: CGPoint(x: x + radius, y: y),
               control1: CGPoint(x: x, y: y + radius - k * 0.55),
               control2: CGPoint(x: x + radius - k * 0.55, y: y))
    p.closeSubpath()
    return p
}

// ── the black card ────────────────────────────────────────────────────────
let cardW = S * 0.615
let card = CGRect(x: (S - cardW) / 2, y: (S - cardW) / 2 - S * 0.012, width: cardW, height: cardW)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.045,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.16))
ctx.addPath(squircle(card, cardW * 0.245))
ctx.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.055, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// ── the ribbon tab ────────────────────────────────────────────────────────
// It hangs from the top edge and is notched at the bottom, like a bookmark.
let ribW = cardW * 0.195
let ribH = cardW * 0.235
let ribX = card.midX - ribW / 2
let ribTop = card.maxY
let notch = ribH * 0.30

let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: ribX, y: ribTop))
ribbon.addLine(to: CGPoint(x: ribX, y: ribTop - ribH))
ribbon.addLine(to: CGPoint(x: card.midX, y: ribTop - ribH + notch))
ribbon.addLine(to: CGPoint(x: ribX + ribW, y: ribTop - ribH))
ribbon.addLine(to: CGPoint(x: ribX + ribW, y: ribTop))
ribbon.closeSubpath()
ctx.addPath(ribbon)
ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
ctx.fillPath()

// ── the two people ────────────────────────────────────────────────────────
// Drawn rather than borrowed from SF Symbols so the proportions are ours: the
// front figure is larger and overlaps the one behind.
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let dim = CGColor(red: 0.86, green: 0.86, blue: 0.86, alpha: 1)

func head(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

/// A shoulder: a dome with a flat base and softly rounded bottom corners.
func shoulders(_ cx: CGFloat, _ baseY: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    let r = w / 2
    let corner = w * 0.12
    p.move(to: CGPoint(x: cx - r, y: baseY + corner))
    p.addArc(center: CGPoint(x: cx, y: baseY + h - r), radius: r,
             startAngle: .pi, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: cx + r, y: baseY + corner))
    p.addQuadCurve(to: CGPoint(x: cx + r - corner, y: baseY), control: CGPoint(x: cx + r, y: baseY))
    p.addLine(to: CGPoint(x: cx - r + corner, y: baseY))
    p.addQuadCurve(to: CGPoint(x: cx - r, y: baseY + corner), control: CGPoint(x: cx - r, y: baseY))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

let baseY = card.minY + cardW * 0.175
let backCX = card.midX + cardW * 0.155
let frontCX = card.midX - cardW * 0.115

// the figure behind, slightly dimmed so the overlap reads
head(backCX, card.midY + cardW * 0.075, cardW * 0.093, white)
shoulders(backCX, baseY, cardW * 0.335, cardW * 0.225, dim)

// the figure in front
head(frontCX, card.midY + cardW * 0.105, cardW * 0.112, white)
shoulders(frontCX, baseY, cardW * 0.395, cardW * 0.265, white)

guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) at \(Int(S))×\(Int(S))")
