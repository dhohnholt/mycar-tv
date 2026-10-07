// Renders the 1024×1024 app icon. Run: swift scripts/make_icon.swift <output.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let colors = [NSColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1).cgColor,
              NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
// Screen
let screen = CGRect(x: 172, y: 300, width: 680, height: 440)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 70, cornerHeight: 70, transform: nil))
ctx.fillPath()
// Play triangle
ctx.setFillColor(NSColor(red: 0.15, green: 0.30, blue: 0.75, alpha: 1).cgColor)
ctx.move(to: CGPoint(x: 445, y: 400)); ctx.addLine(to: CGPoint(x: 445, y: 640)); ctx.addLine(to: CGPoint(x: 640, y: 520)); ctx.closePath(); ctx.fillPath()
// Stand
ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: 210, width: 200, height: 50), cornerWidth: 25, cornerHeight: 25, transform: nil))
ctx.fillPath()
image.unlockFocus()
let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
