import AppKit

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

// Background: deep indigo, lighter top-left.
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(0x4C6EF5), c(0x2B1F6B)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Keycap: a white top face sitting on a darker base, like a real key.
let w: CGFloat = 600, h: CGFloat = 600, r: CGFloat = 132
let x = (S - w) / 2, y = (S - h) / 2 + 30
cg.setShadow(offset: CGSize(width: 0, height: -40), blur: 70, color: c(0x0B0726, 0.55))
cg.addPath(CGPath(roundedRect: CGRect(x: x, y: y - 46, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
cg.setFillColor(c(0xB9C3F7)); cg.fillPath()
cg.setShadow(offset: .zero, blur: 0, color: nil)
let face = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
cg.addPath(face); cg.clip()
let faceGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(0xFFFFFF), c(0xEEF1FF)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(faceGrad, start: CGPoint(x: 0, y: y + h), end: CGPoint(x: 0, y: y), options: [])
cg.resetClip()

func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, center: CGPoint, fontName: String? = nil) {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let font = fontName.flatMap { NSFont(name: $0, size: size) } ?? rounded
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    let line = CTLineCreateWithAttributedString(str)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    cg.textPosition = CGPoint(x: center.x - b.midX, y: center.y - b.midY)
    CTLineDraw(line, cg)
}
// The letter, centered; 紡 (tsumu, to spin thread: the Tsumu of TsumuKey) in
// red as the corner hint, where the keyboard's keys show their symbol.
draw("a", size: 420, weight: .bold, color: c(0x2B1F6B), center: CGPoint(x: S / 2, y: y + h / 2 - 10))
draw("紡", size: 140, weight: .bold, color: c(0xC8102E), center: CGPoint(x: x + w - 118, y: y + h - 118),
     fontName: "HiraginoSans-W6")

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
