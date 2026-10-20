// Draws the app icon from the site's mark (web/icon-maskable.svg): two interlocked links,
// paper and safety orange on ink, full bleed. Writes the light, dark and tinted variants.
//
//     swiftc -o /tmp/make-app-icon ios/tools/make-app-icon.swift && /tmp/make-app-icon
import AppKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "ios/Chainmates/Assets.xcassets/AppIcon.appiconset")
let px = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func draw(background: CGColor?, first: CGColor, second: CGColor, name: String) {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 40
    if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px)) }
    // SVG space: y down. Flip, then the maskable transform translate(4.8 4.8) scale(.76).
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: s, y: -s)
    ctx.translateBy(x: 4.8, y: 4.8); ctx.scaleBy(x: 0.76, y: 0.76)
    ctx.translateBy(x: 20, y: 20); ctx.rotate(by: -32 * .pi / 180); ctx.translateBy(x: -20, y: -20)
    ctx.setLineWidth(4.2)
    let a = CGPath(roundedRect: CGRect(x: 4, y: 12, width: 20, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil)
    let b = CGPath(roundedRect: CGRect(x: 16, y: 12, width: 20, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.setStrokeColor(first); ctx.addPath(a); ctx.strokePath()
    ctx.setStrokeColor(second); ctx.addPath(b); ctx.strokePath()
    ctx.saveGState(); ctx.clip(to: CGRect(x: 12, y: 20, width: 16, height: 14))
    ctx.setStrokeColor(first); ctx.addPath(a); ctx.strokePath(); ctx.restoreGState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote", name)
}

draw(background: color(0x1A1917), first: color(0xF6F3EC), second: color(0xE8590C), name: "icon-1024.png")
draw(background: nil, first: color(0xEDE9E0), second: color(0xFF7A3D), name: "icon-1024-dark.png")
draw(background: nil, first: color(0xFFFFFF), second: color(0xFFFFFF, 0.62), name: "icon-1024-tinted.png")
