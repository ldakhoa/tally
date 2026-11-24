// make-icon.swift
//
// Renders Tally's *Paws & Cream* kawaii Japanese storybook app icon:
// A plump coral-peach Japanese kiss-lock coin pouch (gamaguchi) with a chubby
// Golden Retriever puppy & Munchkin kitten peeking joyfully over the brass rim.
//
// Usage:
//   swift tools/make-icon.swift [--out path/to/AppIcon.png]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Color & Gradient Helpers

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func makeGradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// Warm cocoa ink (lighter & softer than pure black, per docs/DESIGN_SYSTEM.md)
let inkCocoa = rgb(0x5A3E33)
let inkDeep  = rgb(0x452D24)
let stretchOpts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

// MARK: - Drawing Primitives

func fillLinear(_ ctx: CGContext, path: CGPath, colors: [CGColor], start: CGPoint, end: CGPoint, locations: [CGFloat]? = nil) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(makeGradient(colors, locations), start: start, end: end, options: stretchOpts)
    ctx.restoreGState()
}

func fillRadial(_ ctx: CGContext, center: CGPoint, radius: CGFloat, hex: UInt32, alpha: CGFloat) {
    ctx.drawRadialGradient(
        makeGradient([rgb(hex, alpha), rgb(hex, 0)]),
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: []
    )
}

func strokeCocoa(_ ctx: CGContext, path: CGPath, width: CGFloat, color: CGColor = inkCocoa) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func ellipsePath(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
}

func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radii: (CGFloat, CGFloat, CGFloat)) -> CGPath {
    let p = CGMutablePath()
    p.move(to: P((a.x + b.x) / 2, (a.y + b.y) / 2))
    p.addArc(tangent1End: b, tangent2End: c, radius: radii.1)
    p.addArc(tangent1End: c, tangent2End: a, radius: radii.2)
    p.addArc(tangent1End: a, tangent2End: b, radius: radii.0)
    p.closeSubpath()
    return p
}

func heartPath(center: CGPoint, size s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let x = center.x, y = center.y
    p.move(to: P(x, y + s * 0.46))
    p.addCurve(to: P(x - s * 0.56, y - s * 0.08),
               control1: P(x - s * 0.14, y + s * 0.34),
               control2: P(x - s * 0.56, y + s * 0.16))
    p.addCurve(to: P(x, y - s * 0.24),
               control1: P(x - s * 0.56, y - s * 0.44),
               control2: P(x - s * 0.14, y - s * 0.50))
    p.addCurve(to: P(x + s * 0.56, y - s * 0.08),
               control1: P(x + s * 0.14, y - s * 0.50),
               control2: P(x + s * 0.56, y - s * 0.44))
    p.addCurve(to: P(x, y + s * 0.46),
               control1: P(x + s * 0.56, y + s * 0.16),
               control2: P(x + s * 0.14, y + s * 0.34))
    p.closeSubpath()
    return p
}

func drawPawPrint(_ ctx: CGContext, at c: CGPoint, size s: CGFloat, angleDeg: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angleDeg * .pi / 180)
    ctx.setFillColor(rgb(0xE67360, alpha))
    ctx.fillEllipse(in: CGRect(x: -s * 0.32, y: -s * 0.08, width: s * 0.64, height: s * 0.52))
    let toes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (-0.36, -0.26, 0.14, 0.18),
        (-0.13, -0.40, 0.14, 0.19),
        ( 0.13, -0.40, 0.14, 0.19),
        ( 0.36, -0.26, 0.14, 0.18),
    ]
    for (tx, ty, rx, ry) in toes {
        ctx.fillEllipse(in: CGRect(x: (tx - rx) * s, y: (ty - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
    }
    ctx.restoreGState()
}

func drawSparkle(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    p.move(to: P(c.x, c.y - r))
    p.addQuadCurve(to: P(c.x + r, c.y), control: P(c.x + r * 0.18, c.y - r * 0.18))
    p.addQuadCurve(to: P(c.x, c.y + r), control: P(c.x + r * 0.18, c.y + r * 0.18))
    p.addQuadCurve(to: P(c.x - r, c.y), control: P(c.x - r * 0.18, c.y + r * 0.18))
    p.addQuadCurve(to: P(c.x, c.y - r), control: P(c.x - r * 0.18, c.y - r * 0.18))
    p.closeSubpath()
    ctx.saveGState()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func drawBobaEyes(_ ctx: CGContext, lx: CGFloat, rx: CGFloat, y: CGFloat, rxEye: CGFloat, ryEye: CGFloat, irisGlowHex: UInt32) {
    for cx in [lx, rx] {
        let eyePath = ellipsePath(cx, y, rxEye, ryEye)
        fillLinear(ctx, path: eyePath, colors: [rgb(0x3B231B), rgb(0x523327)], start: P(cx, y - ryEye), end: P(cx, y + ryEye))
        ctx.saveGState()
        ctx.addPath(eyePath)
        ctx.clip()
        fillRadial(ctx, center: P(cx, y + ryEye * 0.62), radius: rxEye * 0.92, hex: irisGlowHex, alpha: 0.72)
        ctx.restoreGState()
        ctx.setFillColor(rgb(0xFFFFFF, 0.96))
        ctx.fillEllipse(in: CGRect(x: cx - rxEye * 0.52, y: y - ryEye * 0.56, width: rxEye * 0.64, height: ryEye * 0.56))
        ctx.setFillColor(rgb(0xFFFFFF, 0.88))
        ctx.fillEllipse(in: CGRect(x: cx + rxEye * 0.20, y: y + ryEye * 0.24, width: rxEye * 0.26, height: ryEye * 0.24))
    }
}

func drawKawaiiBlush(_ ctx: CGContext, lx: CGFloat, rx: CGFloat, y: CGFloat, radius: CGFloat, hex: UInt32) {
    for cx in [lx, rx] {
        fillRadial(ctx, center: P(cx, y), radius: radius, hex: hex, alpha: 0.68)
        let lines = CGMutablePath()
        for offset: CGFloat in [-9, 0, 9] {
            lines.move(to: P(cx + offset - 3, y + 6))
            lines.addLine(to: P(cx + offset + 3, y - 6))
        }
        strokeCocoa(ctx, path: lines, width: 2.6, color: rgb(0xE87A82, 0.55))
    }
}

// MARK: - Background (Paws & Cream Storybook Watercolor Paper)

func drawBackground(_ ctx: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.drawLinearGradient(
        makeGradient([rgb(0xFFE7D6), rgb(0xFFF3E6), rgb(0xFFF9F2)], [0.0, 0.50, 1.0]),
        start: P(0, 0), end: P(1024, 1024), options: []
    )
    ctx.saveGState()
    ctx.clip(to: canvas)
    fillRadial(ctx, center: P(150, 150), radius: 520, hex: 0xFFD0C0, alpha: 0.44)
    fillRadial(ctx, center: P(880, 170), radius: 480, hex: 0xFFEAC2, alpha: 0.40)
    fillRadial(ctx, center: P(860, 880), radius: 560, hex: 0xCBEEDB, alpha: 0.42)
    fillRadial(ctx, center: P(150, 870), radius: 480, hex: 0xFFD5DF, alpha: 0.36)
    fillRadial(ctx, center: P(512, 515), radius: 495, hex: 0xFFFFFF, alpha: 0.68)

    drawPawPrint(ctx, at: P(134, 148), size: 70, angleDeg: -22, alpha: 0.085)
    drawPawPrint(ctx, at: P(892, 162), size: 64, angleDeg: 24, alpha: 0.08)
    drawPawPrint(ctx, at: P(124, 864), size: 62, angleDeg: 18, alpha: 0.075)
    drawPawPrint(ctx, at: P(894, 848), size: 68, angleDeg: -18, alpha: 0.08)

    var seed: UInt64 = 0x54414C4C593230
    func nextRand() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFF) / 65535.0
    }
    for _ in 0..<240 {
        let x = nextRand() * 1024
        let y = nextRand() * 1024
        let r = 1.6 + nextRand() * 5.2
        ctx.setFillColor(nextRand() > 0.45 ? rgb(0xE09C7E, 0.055) : rgb(0x8AD6AE, 0.05))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    for _ in 0..<1800 {
        let x = nextRand() * 1024
        let y = nextRand() * 1024
        let r = 0.7 + nextRand() * 1.4
        ctx.setFillColor(nextRand() > 0.5 ? rgb(0x6B4423, 0.022) : rgb(0xFFFFFF, 0.045))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
    ctx.restoreGState()
}

// MARK: - Matcha Sprout & Mini Gold Coin

func drawSprout(_ ctx: CGContext, base: CGPoint, scale s: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: base.x, y: base.y)
    ctx.scaleBy(x: s, y: s)
    let lw = lineW / s

    let stem = CGMutablePath()
    stem.move(to: P(0, 0))
    stem.addQuadCurve(to: P(3, -46), control: P(-4, -24))
    strokeCocoa(ctx, path: stem, width: lw)

    let leafL = CGMutablePath()
    leafL.move(to: P(2, -42))
    leafL.addCurve(to: P(-64, -88), control1: P(-20, -48), control2: P(-52, -62))
    leafL.addCurve(to: P(2, -42), control1: P(-46, -106), control2: P(-10, -82))
    leafL.closeSubpath()
    fillLinear(ctx, path: leafL, colors: [rgb(0xD3F7DE), rgb(0x74C998)], start: P(-64, -94), end: P(0, -40))
    strokeCocoa(ctx, path: leafL, width: lw * 0.9)

    let leafR = CGMutablePath()
    leafR.move(to: P(3, -44))
    leafR.addCurve(to: P(70, -82), control1: P(26, -50), control2: P(58, -60))
    leafR.addCurve(to: P(3, -44), control1: P(54, -104), control2: P(16, -84))
    leafR.closeSubpath()
    fillLinear(ctx, path: leafR, colors: [rgb(0xDDFBE5), rgb(0x6DC392)], start: P(70, -94), end: P(2, -42))
    strokeCocoa(ctx, path: leafR, width: lw * 0.9)

    ctx.setFillColor(rgb(0xFFFFFF, 0.65))
    ctx.fillEllipse(in: CGRect(x: -42, y: -83, width: 13, height: 6.5))
    ctx.fillEllipse(in: CGRect(x: 32, y: -78, width: 14, height: 6.5))
    ctx.restoreGState()
}

func drawCoinSproutCharm(_ ctx: CGContext, hinge: CGPoint, lineW: CGFloat) {
    ctx.saveGState()

    // Tiny brass jump ring attached to the right hinge of the gamaguchi frame
    let ringCenter = P(hinge.x + 16, hinge.y + 22)
    let ring = ellipsePath(ringCenter.x, ringCenter.y, 15, 15)
    strokeCocoa(ctx, path: ring, width: 8.5, color: rgb(0xE8AE44))
    strokeCocoa(ctx, path: ring, width: 4.0, color: rgb(0xFFF3B8))

    // Cute matcha sprout tucked cleanly atop the dangling coin (angled slightly outward)
    let coinCenter = P(hinge.x + 36, hinge.y + 102)
    let r: CGFloat = 52
    ctx.saveGState()
    ctx.translateBy(x: coinCenter.x + 10, y: coinCenter.y - r + 6)
    ctx.rotate(by: 18 * .pi / 180)
    drawSprout(ctx, base: P(0, 0), scale: 0.46, lineW: 7.5)
    ctx.restoreGState()

    // Gleaming butter-gold coin charm
    let outer = ellipsePath(coinCenter.x, coinCenter.y, r, r)
    fillLinear(ctx, path: outer,
               colors: [rgb(0xFFF4B8), rgb(0xFFDA68), rgb(0xF3AF42)],
               start: P(coinCenter.x - r * 0.6, coinCenter.y - r),
               end: P(coinCenter.x + r * 0.6, coinCenter.y + r),
               locations: [0.0, 0.55, 1.0])
    let inner = ellipsePath(coinCenter.x, coinCenter.y, r * 0.72, r * 0.72)
    strokeCocoa(ctx, path: inner, width: 4.5, color: rgb(0xC98524, 0.65))

    // Tiny embossed heart inside coin charm
    let miniHeart = heartPath(center: P(coinCenter.x, coinCenter.y + 2), size: 36)
    fillLinear(ctx, path: miniHeart, colors: [rgb(0xFFA89C), rgb(0xE6705E)], start: P(coinCenter.x, coinCenter.y - 14), end: P(coinCenter.x, coinCenter.y + 18))
    strokeCocoa(ctx, path: miniHeart, width: 4.0, color: rgb(0xA65224, 0.78))

    strokeCocoa(ctx, path: outer, width: lineW * 0.85)

    // Glossy jelly highlight
    ctx.saveGState()
    ctx.translateBy(x: coinCenter.x - r * 0.44, y: coinCenter.y - r * 0.46)
    ctx.rotate(by: -38 * .pi / 180)
    ctx.setFillColor(rgb(0xFFFFFF, 0.84))
    ctx.fillEllipse(in: CGRect(x: -r * 0.18, y: -r * 0.07, width: r * 0.36, height: r * 0.14))
    ctx.restoreGState()

    ctx.restoreGState()
}

// MARK: - Peeking Chubby Golden Retriever Puppy

func drawPeekingGolden(_ ctx: CGContext, at origin: CGPoint, scale s: CGFloat, tiltDeg: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: tiltDeg * .pi / 180)
    ctx.scaleBy(x: s, y: s)
    let lw = lineW / s

    // Plump soft shoulders tucked down inside the open purse
    let torso = CGPath(roundedRect: CGRect(x: -118, y: 66, width: 236, height: 118), cornerWidth: 58, cornerHeight: 58, transform: nil)
    fillLinear(ctx, path: torso, colors: [rgb(0xF8CF88), rgb(0xE9AE5D)], start: P(0, 66), end: P(0, 184))
    ctx.saveGState()
    ctx.addPath(torso)
    ctx.clip()
    let chest = ellipsePath(0, 134, 72, 54)
    fillLinear(ctx, path: chest, colors: [rgb(0xFFFBF0), rgb(0xFCE8C2)], start: P(0, 86), end: P(0, 184))
    ctx.restoreGState()
    strokeCocoa(ctx, path: torso, width: lw)

    // Squishy round Golden puppy head with fluffy baby top curl
    let head = CGMutablePath()
    head.move(to: P(-22, -124))
    head.addQuadCurve(to: P(2, -148), control: P(-12, -146))
    head.addQuadCurve(to: P(14, -128), control: P(14, -142))
    head.addQuadCurve(to: P(34, -138), control: P(26, -140))
    head.addQuadCurve(to: P(40, -120), control: P(44, -128))
    head.addCurve(to: P(144, 6), control1: P(110, -110), control2: P(142, -58))
    head.addCurve(to: P(134, 66), control1: P(154, 34), control2: P(148, 52))
    head.addCurve(to: P(0, 114), control1: P(104, 102), control2: P(58, 114))
    head.addCurve(to: P(-134, 66), control1: P(-58, 114), control2: P(-104, 102))
    head.addCurve(to: P(-144, 6), control1: P(-148, 52), control2: P(-154, 34))
    head.addCurve(to: P(-22, -124), control1: P(-142, -60), control2: P(-96, -120))
    head.closeSubpath()

    fillLinear(ctx, path: head, colors: [rgb(0xFFF2CC), rgb(0xF8CF88), rgb(0xEBB160)], start: P(0, -144), end: P(0, 114), locations: [0.0, 0.56, 1.0])

    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip()
    fillRadial(ctx, center: P(-28, -84), radius: 115, hex: 0xFFFFFF, alpha: 0.48)
    fillRadial(ctx, center: P(0, 50), radius: 86, hex: 0xFFFBF0, alpha: 0.76)
    fillRadial(ctx, center: P(0, 128), radius: 102, hex: 0xC98240, alpha: 0.16)
    ctx.restoreGState()

    strokeCocoa(ctx, path: head, width: lw)

    // Velvety wavy floppy Golden Retriever ears draping over the cheeks
    for side: CGFloat in [-1, 1] {
        let ear = CGMutablePath()
        ear.move(to: P(side * 96, -92))
        ear.addCurve(to: P(side * 172, 12), control1: P(side * 150, -82), control2: P(side * 178, -32))
        ear.addCurve(to: P(side * 154, 76), control1: P(side * 176, 46), control2: P(side * 170, 74))
        ear.addCurve(to: P(side * 116, 48), control1: P(side * 134, 80), control2: P(side * 120, 68))
        ear.addCurve(to: P(side * 112, -22), control1: P(side * 112, 22), control2: P(side * 114, 0))
        ear.addCurve(to: P(side * 96, -92), control1: P(side * 112, -54), control2: P(side * 108, -76))
        ear.closeSubpath()
        fillLinear(ctx, path: ear, colors: [rgb(0xF3BE71), rgb(0xDD9647)], start: P(side * 132, -88), end: P(side * 140, 76))
        ctx.saveGState()
        ctx.addPath(ear)
        ctx.clip()
        fillRadial(ctx, center: P(side * 134, -44), radius: 52, hex: 0xFFF2D2, alpha: 0.42)
        ctx.restoreGState()
        strokeCocoa(ctx, path: ear, width: lw)
    }

    // Sweet puppy eyebrows
    let brows = CGMutablePath()
    brows.move(to: P(-68, -40))
    brows.addQuadCurve(to: P(-46, -44), control: P(-57, -50))
    brows.move(to: P(46, -44))
    brows.addQuadCurve(to: P(68, -40), control: P(57, -50))
    strokeCocoa(ctx, path: brows, width: lw * 0.55, color: rgb(0x9E6738, 0.72))

    // Kawaii rosy blush cheeks
    drawKawaiiBlush(ctx, lx: -90, rx: 90, y: 38, radius: 40, hex: 0xF7989C)

    // Big sparkling boba eyes
    drawBobaEyes(ctx, lx: -55, rx: 55, y: 8, rxEye: 23, ryEye: 25, irisGlowHex: 0xC97D45)

    // Glossy heart-button cocoa nose
    let nose = roundedTriangle(P(-16, 24), P(16, 24), P(0, 40), radii: (7, 7, 8))
    ctx.addPath(nose)
    ctx.setFillColor(inkDeep)
    ctx.fillPath()
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fillEllipse(in: CGRect(x: -8, y: 25, width: 7.5, height: 4.5))

    // Happy pink tongue & ":3" smile
    let tongue = ellipsePath(0, 64, 12, 13)
    fillLinear(ctx, path: tongue, colors: [rgb(0xFFA8B0), rgb(0xEE7D8A)], start: P(0, 52), end: P(0, 78))
    strokeCocoa(ctx, path: tongue, width: lw * 0.62)

    let mouth = CGMutablePath()
    mouth.move(to: P(0, 40))
    mouth.addLine(to: P(0, 50))
    mouth.move(to: P(-25, 48))
    mouth.addQuadCurve(to: P(0, 50), control: P(-12, 66))
    mouth.addQuadCurve(to: P(25, 48), control: P(12, 66))
    strokeCocoa(ctx, path: mouth, width: lw * 0.76, color: inkDeep)

    ctx.restoreGState()
}

// MARK: - Peeking Chubby Munchkin Kitten

func drawPeekingMunchkin(_ ctx: CGContext, at origin: CGPoint, scale s: CGFloat, tiltDeg: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: tiltDeg * .pi / 180)
    ctx.scaleBy(x: s, y: s)
    let lw = lineW / s

    // Fluffy apricot-cream plume tail curling subtly behind right ear/cheek above the rim
    let tail = CGMutablePath()
    tail.move(to: P(108, 124))
    tail.addCurve(to: P(182, 42), control1: P(166, 124), control2: P(196, 86))
    tail.addCurve(to: P(150, 4), control1: P(178, 14), control2: P(164, 2))
    tail.addCurve(to: P(126, 36), control1: P(132, 6), control2: P(122, 20))
    tail.addCurve(to: P(134, 88), control1: P(128, 54), control2: P(140, 70))
    tail.addCurve(to: P(108, 124), control1: P(128, 106), control2: P(118, 118))
    tail.closeSubpath()
    fillLinear(ctx, path: tail, colors: [rgb(0xFFFDF8), rgb(0xF4CA9F)], start: P(156, 6), end: P(138, 124))
    strokeCocoa(ctx, path: tail, width: lw)

    // Plump shoulders tucked down inside the open purse
    let torso = CGPath(roundedRect: CGRect(x: -116, y: 70, width: 232, height: 114), cornerWidth: 57, cornerHeight: 57, transform: nil)
    fillLinear(ctx, path: torso, colors: [rgb(0xFFFFFF), rgb(0xF8E9DB)], start: P(0, 70), end: P(0, 184))
    strokeCocoa(ctx, path: torso, width: lw)

    // Small plush wider-set rounded Munchkin ears
    let earL = roundedTriangle(P(-122, -38), P(-110, -134), P(-38, -96), radii: (18, 24, 18))
    let earR = roundedTriangle(P(38, -96), P(110, -134), P(122, -38), radii: (18, 24, 18))
    let innerL = roundedTriangle(P(-104, -54), P(-96, -110), P(-56, -90), radii: (10, 14, 10))
    let innerR = roundedTriangle(P(56, -90), P(96, -110), P(104, -54), radii: (10, 14, 10))

    fillLinear(ctx, path: earL, colors: [rgb(0xFFFFFF), rgb(0xFBEFE0)], start: P(0, -134), end: P(0, -38))
    fillLinear(ctx, path: innerL, colors: [rgb(0xFFD8DF), rgb(0xF6B0BC)], start: P(0, -110), end: P(0, -54))
    strokeCocoa(ctx, path: earL, width: lw)

    fillLinear(ctx, path: earR, colors: [rgb(0xF8CDA0), rgb(0xEBB37E)], start: P(0, -134), end: P(0, -38))
    fillLinear(ctx, path: innerR, colors: [rgb(0xFFD8DF), rgb(0xF6B0BC)], start: P(0, -110), end: P(0, -54))
    strokeCocoa(ctx, path: earR, width: lw)

    // Squishy marshmallow-round Munchkin head
    let head = CGMutablePath()
    head.move(to: P(0, -110))
    head.addCurve(to: P(148, 8), control1: P(96, -110), control2: P(144, -58))
    head.addCurve(to: P(140, 66), control1: P(160, 34), control2: P(154, 52))
    head.addCurve(to: P(0, 112), control1: P(110, 102), control2: P(62, 112))
    head.addCurve(to: P(-140, 66), control1: P(-62, 112), control2: P(-110, 102))
    head.addCurve(to: P(-148, 8), control1: P(-154, 52), control2: P(-160, 34))
    head.addCurve(to: P(0, -110), control1: P(-144, -58), control2: P(-96, -110))
    head.closeSubpath()

    fillLinear(ctx, path: head, colors: [rgb(0xFFFFFF), rgb(0xFFFBF5), rgb(0xF8E9DB)], start: P(0, -110), end: P(0, 112), locations: [0.0, 0.58, 1.0])

    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip()
    let patch = ellipsePath(78, -72, 76, 54)
    fillLinear(ctx, path: patch, colors: [rgb(0xFAD2A7, 0.90), rgb(0xEEB782, 0.86)], start: P(30, -112), end: P(118, -28))
    let stripes = CGMutablePath()
    stripes.move(to: P(-16, -102)); stripes.addLine(to: P(-14, -82))
    stripes.move(to: P(0, -106));   stripes.addLine(to: P(0, -80))
    stripes.move(to: P(16, -102));  stripes.addLine(to: P(14, -82))
    strokeCocoa(ctx, path: stripes, width: 7.5, color: rgb(0xEBB683, 0.52))
    fillRadial(ctx, center: P(0, 126), radius: 112, hex: 0xD9AC8A, alpha: 0.16)
    ctx.restoreGState()

    strokeCocoa(ctx, path: head, width: lw)

    // Kawaii blush cheeks
    drawKawaiiBlush(ctx, lx: -90, rx: 90, y: 40, radius: 40, hex: 0xF9A2AE)

    // Big sparkling boba eyes
    drawBobaEyes(ctx, lx: -55, rx: 55, y: 12, rxEye: 23, ryEye: 25, irisGlowHex: 0xC98D6B)

    // Tiny pink strawberry nose + dainty ":3" mouth
    let nose = roundedTriangle(P(-12, 28), P(12, 28), P(0, 40), radii: (5, 5, 6))
    fillLinear(ctx, path: nose, colors: [rgb(0xFFB4BC), rgb(0xF08996)], start: P(0, 26), end: P(0, 40))
    strokeCocoa(ctx, path: nose, width: lw * 0.5)

    let mouth = CGMutablePath()
    mouth.move(to: P(0, 40))
    mouth.addLine(to: P(0, 50))
    mouth.move(to: P(-24, 48))
    mouth.addQuadCurve(to: P(0, 50), control: P(-12, 66))
    mouth.addQuadCurve(to: P(24, 48), control: P(12, 66))
    strokeCocoa(ctx, path: mouth, width: lw * 0.76, color: inkDeep)

    // Delicate short cocoa whiskers
    let whiskers = CGMutablePath()
    for side: CGFloat in [-1, 1] {
        whiskers.move(to: P(side * 108, 26))
        whiskers.addLine(to: P(side * 140, 20))
        whiskers.move(to: P(side * 110, 44))
        whiskers.addLine(to: P(side * 142, 50))
    }
    strokeCocoa(ctx, path: whiskers, width: lw * 0.58, color: rgb(0x876A5E, 0.72))

    ctx.restoreGState()
}

// MARK: - Gamaguchi Coin Purse (Back Arch, Plump Coral Body, Brass Clasp & Leather Patch)

func drawGamaguchiBack(_ ctx: CGContext, lineW: CGFloat) {
    // Open back brass arch & dark cozy pouch interior lining
    let interior = CGMutablePath()
    interior.move(to: P(228, 534))
    interior.addQuadCurve(to: P(796, 534), control: P(512, 424))
    interior.addQuadCurve(to: P(228, 534), control: P(512, 576))
    interior.closeSubpath()

    fillLinear(ctx, path: interior, colors: [rgb(0x9E463B), rgb(0x702B24)], start: P(512, 470), end: P(512, 560))

    // Back brass metal arch rim
    let backRim = CGMutablePath()
    backRim.move(to: P(228, 534))
    backRim.addQuadCurve(to: P(796, 534), control: P(512, 424))
    ctx.saveGState()
    ctx.addPath(backRim)
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    let rimPath = ctx.path!
    ctx.restoreGState()

    fillLinear(ctx, path: rimPath, colors: [rgb(0xF8D36D), rgb(0xD99634)], start: P(512, 466), end: P(512, 540))
    strokeCocoa(ctx, path: rimPath, width: lineW * 0.90)
}

func drawLeatherTallyPatch(_ ctx: CGContext, center: CGPoint, lineW: CGFloat) {
    let w: CGFloat = 264
    let h: CGFloat = 136
    let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    let badge = CGPath(roundedRect: rect, cornerWidth: 58, cornerHeight: 58, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: rgb(0x7A2B1F, 0.28))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    fillLinear(ctx, path: badge, colors: [rgb(0xFFFDF8), rgb(0xF8E8D4)], start: P(center.x, rect.minY), end: P(center.x, rect.maxY))
    strokeCocoa(ctx, path: badge, width: lineW * 0.84)

    // Delicate stitched cream-caramel inner border
    let stitchRect = rect.insetBy(dx: 14, dy: 14)
    let stitchPath = CGPath(roundedRect: stitchRect, cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.saveGState()
    ctx.addPath(stitchPath)
    ctx.setStrokeColor(rgb(0xC98D6B, 0.70))
    ctx.setLineWidth(4.5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [10, 10])
    ctx.strokePath()
    ctx.restoreGState()

    // Signature Tally 5-mark embossed on the leather patch!
    let tally = CGMutablePath()
    let span: CGFloat = 104
    let topY = center.y - 30
    let botY = center.y + 30
    for i in 0..<4 {
        let x = center.x - span * 0.56 + CGFloat(i) * (span * 0.37)
        tally.move(to: P(x, topY))
        tally.addLine(to: P(x, botY))
    }
    let slash = CGMutablePath()
    slash.move(to: P(center.x - span * 0.72, botY - 4))
    slash.addLine(to: P(center.x + span * 0.72, topY + 4))

    strokeCocoa(ctx, path: tally, width: 10.5, color: rgb(0x9E5E24, 0.85))
    strokeCocoa(ctx, path: slash, width: 11.5, color: rgb(0xE66D5A, 0.96))

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func drawGamaguchiFront(_ ctx: CGContext, lineW: CGFloat) {
    // Plump coral-peach gamaguchi pouch body (#F8A08B -> #E67360 -> #D25B49)
    let body = CGMutablePath()
    body.move(to: P(228, 534))
    body.addQuadCurve(to: P(796, 534), control: P(512, 574))
    body.addCurve(to: P(848, 728), control1: P(838, 598), control2: P(858, 668))
    body.addCurve(to: P(512, 896), control1: P(832, 842), control2: P(696, 896))
    body.addCurve(to: P(176, 728), control1: P(328, 896), control2: P(192, 842))
    body.addCurve(to: P(228, 534), control1: P(166, 668), control2: P(186, 598))
    body.closeSubpath()

    fillLinear(ctx, path: body,
               colors: [rgb(0xFAA591), rgb(0xEB7763), rgb(0xD45C4A)],
               start: P(512, 534), end: P(512, 896),
               locations: [0.0, 0.56, 1.0])

    // Soft fabric highlights, bottom shading, and gentle gather pleats from the brass frame
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    fillRadial(ctx, center: P(380, 610), radius: 290, hex: 0xFFD4C8, alpha: 0.44)
    fillRadial(ctx, center: P(512, 920), radius: 340, hex: 0x993528, alpha: 0.24)

    let pleats = CGMutablePath()
    pleats.move(to: P(292, 554)); pleats.addQuadCurve(to: P(264, 646), control: P(274, 596))
    pleats.move(to: P(388, 560)); pleats.addQuadCurve(to: P(372, 638), control: P(378, 598))
    pleats.move(to: P(636, 560)); pleats.addQuadCurve(to: P(652, 638), control: P(646, 598))
    pleats.move(to: P(732, 554)); pleats.addQuadCurve(to: P(760, 646), control: P(750, 596))
    strokeCocoa(ctx, path: pleats, width: 6.5, color: rgb(0xB84737, 0.28))
    ctx.restoreGState()

    strokeCocoa(ctx, path: body, width: lineW)

    // Stitched cream leather Tally patch centered on the pouch belly
    drawLeatherTallyPatch(ctx, center: P(512, 734), lineW: lineW)

    // Front gleaming gold/brass kiss-lock metal frame rim
    let frontRim = CGMutablePath()
    frontRim.move(to: P(228, 534))
    frontRim.addQuadCurve(to: P(796, 534), control: P(512, 574))
    ctx.saveGState()
    ctx.addPath(frontRim)
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    let frontRimPath = ctx.path!
    ctx.restoreGState()

    fillLinear(ctx, path: frontRimPath,
               colors: [rgb(0xFFF6C2), rgb(0xFFDA68), rgb(0xDE9B34)],
               start: P(512, 520), end: P(512, 568),
               locations: [0.0, 0.55, 1.0])
    strokeCocoa(ctx, path: frontRimPath, width: lineW * 0.92)

    // Glossy specular highlight streak along front brass frame
    let rimGloss = CGMutablePath()
    rimGloss.move(to: P(254, 531))
    rimGloss.addQuadCurve(to: P(474, 545), control: P(364, 541))
    strokeCocoa(ctx, path: rimGloss, width: 5.5, color: rgb(0xFFFFFF, 0.65))

    // Hinge pins on left & right corners of the brass frame
    for hx: CGFloat in [228, 796] {
        let pin = ellipsePath(hx, 534, 15, 15)
        fillLinear(ctx, path: pin, colors: [rgb(0xFFF7CA), rgb(0xE8A73B)], start: P(hx - 6, 520), end: P(hx + 6, 548))
        strokeCocoa(ctx, path: pin, width: lineW * 0.72)
    }

    // Two classic kissing gold clasp balls (● ●) at top-center of the front frame!
    for cx: CGFloat in [492, 532] {
        let bead = ellipsePath(cx, 528, 20, 20)
        fillLinear(ctx, path: bead,
                   colors: [rgb(0xFFF8CA), rgb(0xFFD864), rgb(0xDC962F)],
                   start: P(cx - 8, 508), end: P(cx + 8, 548),
                   locations: [0.0, 0.55, 1.0])
        strokeCocoa(ctx, path: bead, width: lineW * 0.82)
        ctx.setFillColor(rgb(0xFFFFFF, 0.85))
        ctx.fillEllipse(in: CGRect(x: cx - 9, y: 515, width: 9.5, height: 5.5))
    }
}

func drawPaw(_ ctx: CGContext, at c: CGPoint, rx: CGFloat, ry: CGFloat, angleDeg: CGFloat, topHex: UInt32, botHex: UInt32, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angleDeg * .pi / 180)
    let paw = ellipsePath(0, 0, rx, ry)
    fillLinear(ctx, path: paw, colors: [rgb(topHex), rgb(botHex)], start: P(0, -ry), end: P(0, ry))
    strokeCocoa(ctx, path: paw, width: lineW)
    let toes = CGMutablePath()
    toes.move(to: P(-rx * 0.28, ry * 0.34))
    toes.addLine(to: P(-rx * 0.28, ry * 0.84))
    toes.move(to: P(rx * 0.28, ry * 0.34))
    toes.addLine(to: P(rx * 0.28, ry * 0.84))
    strokeCocoa(ctx, path: toes, width: lineW * 0.56)
    ctx.restoreGState()
}

// MARK: - Main Composition

func render() -> CGImage {
    let S = 1024
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    ctx.translateBy(x: 0, y: CGFloat(S))
    ctx.scaleBy(x: 1, y: -1)

    drawBackground(ctx)

    // Unified soft warm cocoa ambient shadow around the whole gamaguchi + peeking pets
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: rgb(0x6B4423, 0.22))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 1. Open gamaguchi back arch & cozy interior lining
    drawGamaguchiBack(ctx, lineW: 10.0)

    // 2. Golden Retriever puppy (left) & Munchkin kitten (right) tucked inside, clipped cleanly above front pouch
    ctx.saveGState()
    let abovePouchClip = CGMutablePath()
    abovePouchClip.move(to: P(0, 0))
    abovePouchClip.addLine(to: P(1024, 0))
    abovePouchClip.addLine(to: P(1024, 540))
    abovePouchClip.addLine(to: P(796, 540))
    abovePouchClip.addQuadCurve(to: P(228, 540), control: P(512, 580))
    abovePouchClip.addLine(to: P(0, 540))
    abovePouchClip.closeSubpath()
    ctx.addPath(abovePouchClip)
    ctx.clip()

    drawPeekingGolden(ctx, at: P(362, 386), scale: 1.03, tiltDeg: -4, lineW: 10.0)
    drawPeekingMunchkin(ctx, at: P(662, 392), scale: 1.03, tiltDeg: 4, lineW: 10.0)
    ctx.restoreGState()

    // 3. Plump coral-peach gamaguchi front body, Tally leather patch, brass frame & kiss-lock beads
    drawGamaguchiFront(ctx, lineW: 10.0)

    // 4. Tiny coin + matcha sprout charm dangling from the right hinge
    drawCoinSproutCharm(ctx, hinge: P(796, 534), lineW: 10.0)

    // 5. Four tiny chubby paws hooked over the front brass rim!
    drawPaw(ctx, at: P(292, 540), rx: 32, ry: 24, angleDeg: 10, topHex: 0xFFF1CA, botHex: 0xEEB86B, lineW: 9.2)
    drawPaw(ctx, at: P(424, 550), rx: 32, ry: 24, angleDeg: -8, topHex: 0xFFF1CA, botHex: 0xEEB86B, lineW: 9.2)
    drawPaw(ctx, at: P(598, 550), rx: 28, ry: 22, angleDeg: 8, topHex: 0xFFFFFF, botHex: 0xF8E7D4, lineW: 9.2)
    drawPaw(ctx, at: P(732, 540), rx: 28, ry: 22, angleDeg: -10, topHex: 0xFFFFFF, botHex: 0xF8E7D4, lineW: 9.2)

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Floating cozy coral-peach heart above between their heads
    let heart = heartPath(center: P(512, 186), size: 98)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0xE67360, 0.28))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    fillLinear(ctx, path: heart, colors: [rgb(0xFFA89C), rgb(0xE6705E)], start: P(470, 142), end: P(550, 234))
    strokeCocoa(ctx, path: heart, width: 9.2)
    ctx.setFillColor(rgb(0xFFFFFF, 0.70))
    ctx.fillEllipse(in: CGRect(x: 478, y: 160, width: 18, height: 11))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Storybook sparkles
    drawSparkle(ctx, at: P(192, 232), radius: 20, color: rgb(0xF6BF58, 0.90))
    drawSparkle(ctx, at: P(838, 224), radius: 19, color: rgb(0x8AD6AE, 0.92))
    drawSparkle(ctx, at: P(178, 822), radius: 15, color: rgb(0xF6BF58, 0.80))

    return ctx.makeImage()!
}

func renderMacSquircle(from base: CGImage) -> CGImage {
    let S = 1024
    let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let inset: CGFloat = 100
    let box = CGRect(x: inset, y: inset, width: CGFloat(S) - inset * 2, height: CGFloat(S) - inset * 2)
    let cornerRadius: CGFloat = 185.4
    let clipPath = CGPath(roundedRect: box, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x452D24, 0.28))
    ctx.addPath(clipPath)
    ctx.setFillColor(rgb(0xFFF3E6, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.clip()
    ctx.draw(base, in: box)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clipPath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.45))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func downscale(_ image: CGImage, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Cannot write \(url.path)") }
}

var outPath: String?
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    if arg == "--out", let p = args.popFirst() {
        outPath = p
    }
}

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSetDir = repoRoot.appendingPathComponent("Tally/Assets.xcassets/AppIcon.appiconset")
let defaultOut = iconSetDir.appendingPathComponent("AppIcon.png")
let target = outPath.map { URL(fileURLWithPath: $0) } ?? defaultOut
try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

let baseIcon = render()
writePNG(baseIcon, to: target)
print("Wrote Gamaguchi Paws & Cream icon to \(target.path)")

if outPath == nil {
    let macFull = renderMacSquircle(from: baseIcon)
    for px in [16, 32, 64, 128, 256, 512, 1024] {
        let macOut = iconSetDir.appendingPathComponent("AppIcon-mac-\(px).png")
        let scaled = px == 1024 ? macFull : downscale(macFull, size: px)
        writePNG(scaled, to: macOut)
    }
    print("Wrote macOS icon variants in \(iconSetDir.path)")
}
