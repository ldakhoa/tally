// make-icon.swift
//
// Renders Tally's *Paws & Cream* kawaii Japanese storybook app icon:
// Fluffy Golden Retriever puppy & chubby mochi Munchkin kitten snuggled cheek-to-cheek
// over a luminous butter-gold coin & fresh matcha sprout on warm peach-cream watercolor paper.
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

// Delicate warm cocoa ink (lighter & softer than pure black, per docs/DESIGN_SYSTEM.md)
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

/// Ultra-kawaii sparkling boba eyes with warm lower iris glow + twin catchlights!
func drawBobaEyes(_ ctx: CGContext, lx: CGFloat, rx: CGFloat, y: CGFloat, rxEye: CGFloat, ryEye: CGFloat, irisGlowHex: UInt32) {
    for cx in [lx, rx] {
        let eyePath = ellipsePath(cx, y, rxEye, ryEye)
        // Rich dark espresso base
        fillLinear(ctx, path: eyePath, colors: [rgb(0x3B231B), rgb(0x523327)], start: P(cx, y - ryEye), end: P(cx, y + ryEye))
        // Soft warm glowing lower crescent inside eye (makes eyes feel alive & glossy!)
        ctx.saveGState()
        ctx.addPath(eyePath)
        ctx.clip()
        fillRadial(ctx, center: P(cx, y + ryEye * 0.62), radius: rxEye * 0.92, hex: irisGlowHex, alpha: 0.72)
        ctx.restoreGState()
        // Big bright upper-left catchlight
        ctx.setFillColor(rgb(0xFFFFFF, 0.96))
        ctx.fillEllipse(in: CGRect(x: cx - rxEye * 0.52, y: y - ryEye * 0.56, width: rxEye * 0.64, height: ryEye * 0.56))
        // Tiny dreamy lower-right sparkle dot
        ctx.setFillColor(rgb(0xFFFFFF, 0.88))
        ctx.fillEllipse(in: CGRect(x: cx + rxEye * 0.20, y: y + ryEye * 0.24, width: rxEye * 0.26, height: ryEye * 0.24))
    }
}

/// Soft rosy watercolor cheeks with delicate Japanese chibi blush marks (///) like chibi_wife.png
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
    // Soft dreamy pastel watercolor blooms
    fillRadial(ctx, center: P(150, 150), radius: 520, hex: 0xFFD0C0, alpha: 0.44)
    fillRadial(ctx, center: P(880, 170), radius: 480, hex: 0xFFEAC2, alpha: 0.40)
    fillRadial(ctx, center: P(860, 880), radius: 560, hex: 0xCBEEDB, alpha: 0.42)
    fillRadial(ctx, center: P(150, 870), radius: 480, hex: 0xFFD5DF, alpha: 0.36)
    // Luminous milk-white storybook halo behind the pets
    fillRadial(ctx, center: P(512, 515), radius: 485, hex: 0xFFFFFF, alpha: 0.68)

    // Subtle PawPrintBackdrop
    drawPawPrint(ctx, at: P(134, 148), size: 70, angleDeg: -22, alpha: 0.085)
    drawPawPrint(ctx, at: P(892, 162), size: 64, angleDeg: 24, alpha: 0.08)
    drawPawPrint(ctx, at: P(124, 864), size: 62, angleDeg: 18, alpha: 0.075)
    drawPawPrint(ctx, at: P(894, 848), size: 68, angleDeg: -18, alpha: 0.08)

    // Soft watercolor speckles + cold-press paper grain
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

// MARK: - Luminous Gold Coin & Matcha Sprout (inspired by icon_budget.png)

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

func drawGoldCoin(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x6B4423, 0.22))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let outer = ellipsePath(center.x, center.y, r, r)
    fillLinear(ctx, path: outer,
               colors: [rgb(0xFFF4B8), rgb(0xFFDA68), rgb(0xF3AF42)],
               start: P(center.x - r * 0.6, center.y - r),
               end: P(center.x + r * 0.6, center.y + r),
               locations: [0.0, 0.55, 1.0])

    ctx.saveGState()
    ctx.addPath(outer)
    ctx.clip()
    let sheen = CGMutablePath()
    sheen.move(to: P(center.x - r * 0.9, center.y - r * 0.15))
    sheen.addLine(to: P(center.x + r * 0.15, center.y - r * 1.08))
    sheen.addLine(to: P(center.x + r * 0.62, center.y - r * 0.78))
    sheen.addLine(to: P(center.x - r * 0.42, center.y + r * 0.18))
    sheen.closeSubpath()
    ctx.addPath(sheen)
    ctx.setFillColor(rgb(0xFFFFFF, 0.44))
    ctx.fillPath()
    fillRadial(ctx, center: P(center.x, center.y + r * 0.72), radius: r * 0.85, hex: 0xD97D1E, alpha: 0.26)
    ctx.restoreGState()

    // Inner coin rim
    let inner = ellipsePath(center.x, center.y, r * 0.78, r * 0.78)
    strokeCocoa(ctx, path: inner, width: lineW * 0.52, color: rgb(0xC98524, 0.65))

    // Delicate embossed tally 5-mark (softer & cleaner)
    let tally = CGMutablePath()
    let span = r * 0.42
    let topY = center.y - r * 0.27
    let botY = center.y + r * 0.27
    for i in 0..<4 {
        let x = center.x - span * 0.75 + CGFloat(i) * (span * 0.5)
        tally.move(to: P(x, topY))
        tally.addLine(to: P(x, botY))
    }
    let slash = CGMutablePath()
    slash.move(to: P(center.x - span * 0.96, botY - r * 0.05))
    slash.addLine(to: P(center.x + span * 0.96, topY + r * 0.05))
    strokeCocoa(ctx, path: tally, width: lineW * 0.92, color: rgb(0xB36E1E, 0.78))
    strokeCocoa(ctx, path: slash, width: lineW * 1.02, color: rgb(0xE66D5A, 0.92))

    strokeCocoa(ctx, path: outer, width: lineW)

    // Cute glossy jelly highlight
    ctx.saveGState()
    ctx.translateBy(x: center.x - r * 0.48, y: center.y - r * 0.50)
    ctx.rotate(by: -38 * .pi / 180)
    ctx.setFillColor(rgb(0xFFFFFF, 0.82))
    ctx.fillEllipse(in: CGRect(x: -r * 0.16, y: -r * 0.06, width: r * 0.32, height: r * 0.12))
    ctx.restoreGState()

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: - Kawaii Chubby Mochi Golden Retriever Puppy

func drawKawaiiGolden(_ ctx: CGContext, at origin: CGPoint, scale s: CGFloat, tiltDeg: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: tiltDeg * .pi / 180)
    ctx.scaleBy(x: s, y: s)
    let lw = lineW / s

    // Fluffy feathered golden tail wagging behind left
    let tail = CGMutablePath()
    tail.move(to: P(-130, 148))
    tail.addCurve(to: P(-204, 72), control1: P(-186, 152), control2: P(-218, 112))
    tail.addCurve(to: P(-174, 34), control1: P(-200, 44), control2: P(-188, 32))
    tail.addCurve(to: P(-138, 82), control1: P(-154, 38), control2: P(-152, 60))
    tail.addCurve(to: P(-130, 148), control1: P(-128, 102), control2: P(-124, 128))
    tail.closeSubpath()
    fillLinear(ctx, path: tail, colors: [rgb(0xFFF0C8), rgb(0xEBB364)], start: P(-198, 36), end: P(-132, 146))
    strokeCocoa(ctx, path: tail, width: lw)

    // ONE UNIFIED SQUISHY CHUBBY MOCHI-DUMPLING SILHOUETTE (no skinny neck!)
    // Plump cheeks melt right into a big round squishy golden belly!
    let mochi = CGMutablePath()
    mochi.move(to: P(-22, -122))
    // Cute soft golden baby curl on top
    mochi.addQuadCurve(to: P(2, -146), control: P(-12, -144))
    mochi.addQuadCurve(to: P(14, -126), control: P(14, -140))
    mochi.addQuadCurve(to: P(34, -136), control: P(26, -138))
    mochi.addQuadCurve(to: P(40, -118), control: P(44, -126))
    // Wide squishy right cheek bulging softly into chubby right belly
    mochi.addCurve(to: P(148, 8), control1: P(112, -108), control2: P(144, -56))
    mochi.addCurve(to: P(162, 114), control1: P(162, 46), control2: P(170, 78))
    mochi.addCurve(to: P(0, 212), control1: P(150, 186), control2: P(88, 214))
    // Wide squishy left belly & cheek
    mochi.addCurve(to: P(-162, 114), control1: P(-88, 214), control2: P(-150, 186))
    mochi.addCurve(to: P(-148, 8), control1: P(-170, 78), control2: P(-162, 46))
    mochi.addCurve(to: P(-22, -122), control1: P(-144, -58), control2: P(-98, -118))
    mochi.closeSubpath()

    // Warm creamy-butter Golden watercolor coat
    fillLinear(ctx, path: mochi, colors: [rgb(0xFFF2CC), rgb(0xF8CF88), rgb(0xE9AE5D)], start: P(0, -144), end: P(0, 212), locations: [0.0, 0.55, 1.0])

    ctx.saveGState()
    ctx.addPath(mochi)
    ctx.clip()
    // Luminous watercolor crown highlight
    fillRadial(ctx, center: P(-28, -82), radius: 118, hex: 0xFFFFFF, alpha: 0.48)
    // Soft creamy muzzle pillow
    fillRadial(ctx, center: P(0, 44), radius: 88, hex: 0xFFFBF0, alpha: 0.72)
    // Big round creamy chubby tummy cloud!
    let belly = ellipsePath(0, 154, 108, 76)
    fillLinear(ctx, path: belly, colors: [rgb(0xFFFDF5), rgb(0xFCE8C2)], start: P(0, 86), end: P(0, 224))
    // Soft warm watercolor bottom shading
    fillRadial(ctx, center: P(0, 222), radius: 135, hex: 0xC98240, alpha: 0.16)
    ctx.restoreGState()

    // Coral-peach ribbon collar resting cozily across the chunky chubby neck-roll!
    let collar = CGMutablePath()
    collar.move(to: P(-96, 98))
    collar.addQuadCurve(to: P(96, 98), control: P(0, 132))
    ctx.saveGState()
    ctx.addPath(collar)
    ctx.setLineWidth(22)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    let collarPath = ctx.path!
    ctx.restoreGState()
    fillLinear(ctx, path: collarPath, colors: [rgb(0xF69684), rgb(0xE06956)], start: P(0, 88), end: P(0, 132))
    strokeCocoa(ctx, path: collarPath, width: lw * 0.76)

    // Outer cocoa outline over the whole chubby mochi silhouette
    strokeCocoa(ctx, path: mochi, width: lw)

    // Tiny adorable stubby chubby golden back foot peeking at bottom-left!
    let stubbyL = ellipsePath(-96, 198, 30, 20)
    fillLinear(ctx, path: stubbyL, colors: [rgb(0xFCE2A8), rgb(0xE8AC5B)], start: P(-96, 178), end: P(-96, 218))
    strokeCocoa(ctx, path: stubbyL, width: lw * 0.88)
    ctx.setFillColor(rgb(0xD98D68, 0.55))
    ctx.fillEllipse(in: CGRect(x: -104, y: 196, width: 16, height: 10))
    ctx.fillEllipse(in: CGRect(x: -110, y: 190, width: 5.5, height: 5.5))
    ctx.fillEllipse(in: CGRect(x: -99, y: 187, width: 5.5, height: 5.5))
    ctx.fillEllipse(in: CGRect(x: -88, y: 190, width: 5.5, height: 5.5))

    // Velvety wavy floppy Golden Retriever ears draping over the chubby cheeks!
    for side: CGFloat in [-1, 1] {
        let ear = CGMutablePath()
        ear.move(to: P(side * 96, -90))
        ear.addCurve(to: P(side * 172, 12), control1: P(side * 152, -80), control2: P(side * 180, -32))
        ear.addCurve(to: P(side * 154, 76), control1: P(side * 178, 46), control2: P(side * 172, 74))
        ear.addCurve(to: P(side * 116, 48), control1: P(side * 134, 80), control2: P(side * 120, 68))
        ear.addCurve(to: P(side * 112, -22), control1: P(side * 112, 22), control2: P(side * 114, 0))
        ear.addCurve(to: P(side * 96, -90), control1: P(side * 112, -54), control2: P(side * 108, -76))
        ear.closeSubpath()
        fillLinear(ctx, path: ear, colors: [rgb(0xF3BE71), rgb(0xDD9647)], start: P(side * 132, -86), end: P(side * 140, 76))
        ctx.saveGState()
        ctx.addPath(ear)
        ctx.clip()
        fillRadial(ctx, center: P(side * 136, -44), radius: 52, hex: 0xFFF2D2, alpha: 0.42)
        ctx.restoreGState()
        strokeCocoa(ctx, path: ear, width: lw)
    }

    // Tiny adorable curved puppy eyebrows
    let brows = CGMutablePath()
    brows.move(to: P(-68, -42))
    brows.addQuadCurve(to: P(-46, -46), control: P(-57, -52))
    brows.move(to: P(46, -46))
    brows.addQuadCurve(to: P(68, -42), control: P(57, -52))
    strokeCocoa(ctx, path: brows, width: lw * 0.55, color: rgb(0x9E6738, 0.72))

    // Kawaii blush cheeks with /// marks (set wide on those fat squishy cheeks!)
    drawKawaiiBlush(ctx, lx: -92, rx: 92, y: 36, radius: 40, hex: 0xF7989C)

    // BIG SPARKLING BOBA EYES
    drawBobaEyes(ctx, lx: -56, rx: 56, y: 6, rxEye: 23, ryEye: 25, irisGlowHex: 0xC97D45)

    // Tiny glossy heart-button cocoa nose
    let nose = roundedTriangle(P(-16, 22), P(16, 22), P(0, 38), radii: (7, 7, 8))
    ctx.addPath(nose)
    ctx.setFillColor(inkDeep)
    ctx.fillPath()
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fillEllipse(in: CGRect(x: -8, y: 23, width: 7.5, height: 4.5))

    // Sweet happy puppy tongue & ":3" smile
    let tongue = ellipsePath(0, 62, 12, 13)
    fillLinear(ctx, path: tongue, colors: [rgb(0xFFA8B0), rgb(0xEE7D8A)], start: P(0, 50), end: P(0, 76))
    strokeCocoa(ctx, path: tongue, width: lw * 0.62)

    let mouth = CGMutablePath()
    mouth.move(to: P(0, 38))
    mouth.addLine(to: P(0, 48))
    mouth.move(to: P(-25, 46))
    mouth.addQuadCurve(to: P(0, 48), control: P(-12, 64))
    mouth.addQuadCurve(to: P(25, 46), control: P(12, 64))
    strokeCocoa(ctx, path: mouth, width: lw * 0.76, color: inkDeep)

    // Tiny gleaming gold bell on collar
    let bell = ellipsePath(0, 124, 17, 17)
    fillLinear(ctx, path: bell, colors: [rgb(0xFFF3B2), rgb(0xF6BE4A)], start: P(-6, 108), end: P(8, 140))
    strokeCocoa(ctx, path: bell, width: lw * 0.75)

    ctx.restoreGState()
}

// MARK: - Kawaii Chubby Mochi Munchkin Kitten

func drawKawaiiMunchkin(_ ctx: CGContext, at origin: CGPoint, scale s: CGFloat, tiltDeg: CGFloat, lineW: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: tiltDeg * .pi / 180)
    ctx.scaleBy(x: s, y: s)
    let lw = lineW / s

    // Super fluffy bottle-brush Munchkin plume tail curling up on right
    let tail = CGMutablePath()
    tail.move(to: P(130, 152))
    tail.addCurve(to: P(210, 62), control1: P(192, 156), control2: P(222, 112))
    tail.addCurve(to: P(178, 18), control1: P(206, 30), control2: P(192, 16))
    tail.addCurve(to: P(150, 52), control1: P(160, 20), control2: P(148, 34))
    tail.addCurve(to: P(160, 110), control1: P(152, 74), control2: P(166, 92))
    tail.addCurve(to: P(130, 152), control1: P(154, 128), control2: P(142, 144))
    tail.closeSubpath()
    fillLinear(ctx, path: tail, colors: [rgb(0xFFFDF8), rgb(0xF4CA9F)], start: P(182, 20), end: P(162, 152))
    strokeCocoa(ctx, path: tail, width: lw)

    // Small, plush, wider-set rounded Munchkin ears (makes the mochi body look even chubbier!)
    let earL = roundedTriangle(P(-122, -36), P(-110, -132), P(-38, -94), radii: (18, 24, 18))
    let earR = roundedTriangle(P(38, -94), P(110, -132), P(122, -36), radii: (18, 24, 18))
    let innerL = roundedTriangle(P(-104, -52), P(-96, -108), P(-56, -88), radii: (10, 14, 10))
    let innerR = roundedTriangle(P(56, -88), P(96, -108), P(104, -52), radii: (10, 14, 10))

    fillLinear(ctx, path: earL, colors: [rgb(0xFFFFFF), rgb(0xFBEFE0)], start: P(0, -132), end: P(0, -36))
    fillLinear(ctx, path: innerL, colors: [rgb(0xFFD8DF), rgb(0xF6B0BC)], start: P(0, -108), end: P(0, -52))
    strokeCocoa(ctx, path: earL, width: lw)

    fillLinear(ctx, path: earR, colors: [rgb(0xF8CDA0), rgb(0xEBB37E)], start: P(0, -132), end: P(0, -36))
    fillLinear(ctx, path: innerR, colors: [rgb(0xFFD8DF), rgb(0xF6B0BC)], start: P(0, -108), end: P(0, -52))
    strokeCocoa(ctx, path: earR, width: lw)

    // ONE UNIFIED ULTRA-CHUBBY SQUISHY MOCHI-LOAF MUNCHKIN SILHOUETTE!
    // Fat marshmallow cheeks flow right into a wide plump pear-shaped loaf belly (zero skinny neck!)
    let mochi = CGMutablePath()
    mochi.move(to: P(0, -106))
    mochi.addCurve(to: P(150, 12), control1: P(98, -106), control2: P(146, -54))
    mochi.addCurve(to: P(166, 118), control1: P(166, 48), control2: P(176, 82))
    mochi.addCurve(to: P(0, 206), control1: P(154, 186), control2: P(90, 208))
    mochi.addCurve(to: P(-166, 118), control1: P(-90, 208), control2: P(-154, 186))
    mochi.addCurve(to: P(-150, 12), control1: P(-176, 82), control2: P(-166, 48))
    mochi.addCurve(to: P(0, -106), control1: P(-146, -54), control2: P(-98, -106))
    mochi.closeSubpath()

    fillLinear(ctx, path: mochi, colors: [rgb(0xFFFFFF), rgb(0xFFFBF5), rgb(0xF8E9DB)], start: P(0, -106), end: P(0, 206), locations: [0.0, 0.58, 1.0])

    // Soft apricot calico patch + caramel forehead stripes + warm belly shading
    ctx.saveGState()
    ctx.addPath(mochi)
    ctx.clip()
    let patch = ellipsePath(80, -70, 78, 54)
    fillLinear(ctx, path: patch, colors: [rgb(0xFAD2A7, 0.90), rgb(0xEEB782, 0.86)], start: P(30, -110), end: P(118, -26))
    // Cute soft caramel side-belly patch too (calico charm!)
    let hipPatch = ellipsePath(146, 126, 56, 48)
    fillLinear(ctx, path: hipPatch, colors: [rgb(0xFAD2A7, 0.72), rgb(0xEEB782, 0.68)], start: P(100, 90), end: P(175, 165))
    // Tiny cute soft caramel forehead stripes (|||)
    let stripes = CGMutablePath()
    stripes.move(to: P(-16, -100)); stripes.addLine(to: P(-14, -80))
    stripes.move(to: P(0, -104));   stripes.addLine(to: P(0, -78))
    stripes.move(to: P(16, -100));  stripes.addLine(to: P(14, -80))
    strokeCocoa(ctx, path: stripes, width: 7.5, color: rgb(0xEBB683, 0.52))
    fillRadial(ctx, center: P(0, 218), radius: 135, hex: 0xD9AC8A, alpha: 0.16)
    ctx.restoreGState()

    // Matcha-mint ribbon collar resting across the plump chubby mochi neck-roll!
    let collar = CGMutablePath()
    collar.move(to: P(-96, 98))
    collar.addQuadCurve(to: P(96, 98), control: P(0, 132))
    ctx.saveGState()
    ctx.addPath(collar)
    ctx.setLineWidth(21)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    let collarPath = ctx.path!
    ctx.restoreGState()
    fillLinear(ctx, path: collarPath, colors: [rgb(0x9BE0BF), rgb(0x6BB997)], start: P(0, 90), end: P(0, 132))
    strokeCocoa(ctx, path: collarPath, width: lw * 0.76)

    // Outer cocoa outline around the whole fat mochi loaf
    strokeCocoa(ctx, path: mochi, width: lw)

    // Iconic TINY stubby Munchkin bean foot peeking out of the fat round belly with pink toe beans!
    let stubby = ellipsePath(94, 194, 28, 19)
    fillLinear(ctx, path: stubby, colors: [rgb(0xFFFFFF), rgb(0xF7E6D3)], start: P(94, 175), end: P(94, 213))
    strokeCocoa(ctx, path: stubby, width: lw * 0.88)
    ctx.setFillColor(rgb(0xF7A6B2, 0.88))
    ctx.fillEllipse(in: CGRect(x: 86, y: 192, width: 16, height: 10.5))
    ctx.fillEllipse(in: CGRect(x: 79, y: 186, width: 5.8, height: 5.8))
    ctx.fillEllipse(in: CGRect(x: 91, y: 183, width: 5.8, height: 5.8))
    ctx.fillEllipse(in: CGRect(x: 103, y: 186, width: 5.8, height: 5.8))

    // Kawaii blush cheeks with /// marks (wide on those squishy fat cheeks!)
    drawKawaiiBlush(ctx, lx: -94, rx: 94, y: 38, radius: 40, hex: 0xF9A2AE)

    // BIG SPARKLING BOBA EYES
    drawBobaEyes(ctx, lx: -56, rx: 56, y: 10, rxEye: 23, ryEye: 25, irisGlowHex: 0xC98D6B)

    // Tiny pink strawberry nose + dainty ":3" mouth
    let nose = roundedTriangle(P(-12, 26), P(12, 26), P(0, 38), radii: (5, 5, 6))
    fillLinear(ctx, path: nose, colors: [rgb(0xFFB4BC), rgb(0xF08996)], start: P(0, 24), end: P(0, 38))
    strokeCocoa(ctx, path: nose, width: lw * 0.5)

    let mouth = CGMutablePath()
    mouth.move(to: P(0, 38))
    mouth.addLine(to: P(0, 48))
    mouth.move(to: P(-24, 46))
    mouth.addQuadCurve(to: P(0, 48), control: P(-12, 64))
    mouth.addQuadCurve(to: P(24, 46), control: P(12, 64))
    strokeCocoa(ctx, path: mouth, width: lw * 0.76, color: inkDeep)

    // Delicate short cocoa whiskers
    let whiskers = CGMutablePath()
    for side: CGFloat in [-1, 1] {
        whiskers.move(to: P(side * 112, 24))
        whiskers.addLine(to: P(side * 144, 18))
        whiskers.move(to: P(side * 114, 42))
        whiskers.addLine(to: P(side * 146, 48))
    }
    strokeCocoa(ctx, path: whiskers, width: lw * 0.58, color: rgb(0x876A5E, 0.72))

    // Tiny butter-gold bell on mint collar
    let bell = ellipsePath(0, 124, 16, 16)
    fillLinear(ctx, path: bell, colors: [rgb(0xFFF7C6), rgb(0xF6CB5F)], start: P(-6, 108), end: P(8, 140))
    strokeCocoa(ctx, path: bell, width: lw * 0.75)

    ctx.restoreGState()
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

    // Soft warm cocoa ambient shadow beneath the duo
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: rgb(0x6B4423, 0.20))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Extra-chubby mochi Golden Retriever puppy (left) & Munchkin kitten (right) snuggled cozy & close!
    drawKawaiiGolden(ctx, at: P(304, 466), scale: 1.14, tiltDeg: -4, lineW: 10.5)
    drawKawaiiMunchkin(ctx, at: P(720, 478), scale: 1.14, tiltDeg: 4, lineW: 10.5)

    // Fresh matcha sprout peeking gently above the gold coin
    drawSprout(ctx, base: P(512, 616), scale: 0.84, lineW: 9.5)

    // Compact gleaming butter-gold Tally coin so the two chubby mochi pets are the big stars!
    drawGoldCoin(ctx, center: P(512, 728), radius: 118, lineW: 10.5)

    // Tiny adorable stubby paws hugging the coin (tucked snugly against their chubby bellies!)
    drawPaw(ctx, at: P(392, 706), rx: 40, ry: 30, angleDeg: 14, topHex: 0xFFF1CA, botHex: 0xEEB86B, lineW: 9.8)
    drawPaw(ctx, at: P(632, 710), rx: 34, ry: 26, angleDeg: -14, topHex: 0xFFFFFF, botHex: 0xF8E7D4, lineW: 9.8)

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Soft floating coral-peach heart between their heads
    let heart = heartPath(center: P(512, 206), size: 112)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0xE67360, 0.28))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    fillLinear(ctx, path: heart, colors: [rgb(0xFFA89C), rgb(0xE6705E)], start: P(470, 156), end: P(550, 260))
    strokeCocoa(ctx, path: heart, width: 9.5)
    ctx.setFillColor(rgb(0xFFFFFF, 0.70))
    ctx.fillEllipse(in: CGRect(x: 472, y: 178, width: 20, height: 12))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Storybook sparkles
    drawSparkle(ctx, at: P(182, 224), radius: 22, color: rgb(0xF6BF58, 0.90))
    drawSparkle(ctx, at: P(846, 232), radius: 20, color: rgb(0x8AD6AE, 0.92))
    drawSparkle(ctx, at: P(838, 796), radius: 16, color: rgb(0xF6BF58, 0.82))

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
let defaultOut = repoRoot.appendingPathComponent("Tally/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let target = outPath.map { URL(fileURLWithPath: $0) } ?? defaultOut
try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

writePNG(render(), to: target)
print("Wrote kawaii Paws & Cream icon to \(target.path)")
