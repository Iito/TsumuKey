import AppKit

// TsumuKey app icon (紡ぐ, "to spin thread", + key): a keycap whose letter
// "t" runs off the key and becomes thread.
// usage: swift Tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
let S: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let indigo = c(0x2B1F6B), coral = c(0xFF5A4E)

// Background: blue to deep indigo.
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(0x4C6EF5), c(0x2B1F6B)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Keycap: cream face on a darker base.
let key = CGRect(x: 176, y: 318, width: 540, height: 520), radius: CGFloat = 124
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -30), blur: 56, color: c(0x0B0726, 0.5))
cg.addPath(CGPath(roundedRect: key.offsetBy(dx: 0, dy: -38), cornerWidth: radius, cornerHeight: radius, transform: nil))
cg.setFillColor(c(0xD9CCB8)); cg.fillPath()
cg.restoreGState()
let face = CGPath(roundedRect: key, cornerWidth: radius, cornerHeight: radius, transform: nil)
cg.addPath(face); cg.setFillColor(c(0xFFF8EE)); cg.fillPath()

func stroke(_ p: CGPath, _ color: CGColor, _ w: CGFloat) {
    cg.addPath(p); cg.setStrokeColor(color); cg.setLineWidth(w); cg.setLineCap(.round); cg.setLineJoin(.round); cg.strokePath()
}
let w: CGFloat = 66
// The "t": stem down, a rounded foot, then on to the right as one line that
// leaves the key, makes one loop and drifts off the corner.
let t = CGMutablePath()
t.move(to: CGPoint(x: 400, y: 730))
t.addLine(to: CGPoint(x: 400, y: 500))
t.addCurve(to: CGPoint(x: 530, y: 418), control1: CGPoint(x: 400, y: 440), control2: CGPoint(x: 460, y: 410))
t.addCurve(to: CGPoint(x: 868, y: 468), control1: CGPoint(x: 660, y: 432), control2: CGPoint(x: 790, y: 468))
// One round loop (radius 92 around 868,560), then off past the corner.
let r: CGFloat = 92, k: CGFloat = 0.5523 * 92, cx: CGFloat = 868, cy: CGFloat = 560
t.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + k, y: cy - r), control2: CGPoint(x: cx + r, y: cy - k))
t.addCurve(to: CGPoint(x: cx, y: cy + r), control1: CGPoint(x: cx + r, y: cy + k), control2: CGPoint(x: cx + k, y: cy + r))
t.addCurve(to: CGPoint(x: cx - r, y: cy), control1: CGPoint(x: cx - k, y: cy + r), control2: CGPoint(x: cx - r, y: cy + k))
t.addCurve(to: CGPoint(x: 1070, y: 300), control1: CGPoint(x: cx - r, y: 450), control2: CGPoint(x: 980, y: 380))
let bar = CGMutablePath()
bar.move(to: CGPoint(x: 310, y: 640)); bar.addLine(to: CGPoint(x: 500, y: 640))
stroke(t, indigo, w); stroke(bar, indigo, w)
// Outside the key the ink is thread.
cg.saveGState()
cg.addRect(CGRect(x: 0, y: 0, width: S, height: S)); cg.addPath(face)
cg.clip(using: .evenOdd)
stroke(t, coral, w)
cg.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
