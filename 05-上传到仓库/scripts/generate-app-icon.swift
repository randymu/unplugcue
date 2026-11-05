import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Expected output PNG path") }
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 198, yRadius: 198)
NSGradient(starting: NSColor(calibratedRed: 1, green: 0.66, blue: 0.29, alpha: 1), ending: NSColor(calibratedRed: 0.93, green: 0.35, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -75)
// A U-shaped cable, open at the top. Drawn from independent Bezier geometry.
let cable = NSBezierPath()
cable.move(to: NSPoint(x: 316, y: 680))
cable.line(to: NSPoint(x: 316, y: 440))
cable.curve(to: NSPoint(x: 676, y: 440), controlPoint1: NSPoint(x: 316, y: 196), controlPoint2: NSPoint(x: 676, y: 196))
cable.line(to: NSPoint(x: 676, y: 516))
cable.lineWidth = 76
cable.lineCapStyle = .round
NSColor(calibratedWhite: 1, alpha: 0.98).setStroke()
cable.stroke()
// Left rounded tip and right cue dot share the same top edge (y = 718).
// Lower the connector to preserve a clear separation below the dot.
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 620, y: 466, width: 112, height: 110), xRadius: 24, yRadius: 24).fill()
NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.23, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 630, y: 626, width: 92, height: 92)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
