#!/usr/bin/env swift

import Cocoa

// Create a beautiful DMG background image
let width: CGFloat = 600
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// Create gradient background - dark purple to dark blue
let gradient = NSGradient(colors: [
    NSColor(red: 0.08, green: 0.05, blue: 0.15, alpha: 1.0),  // Dark purple
    NSColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 1.0),  // Dark blue
    NSColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1.0)   // Darker
])

gradient?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -45)

// Add subtle glow effects
let context = NSGraphicsContext.current?.cgContext

// Glow 1 - purple
context?.saveGState()
context?.setBlendMode(.plusLighter)
let glow1 = NSGradient(colors: [
    NSColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 0.15),
    NSColor.clear
])
glow1?.draw(in: NSRect(x: -100, y: height - 200, width: 400, height: 300), angle: 45)
context?.restoreGState()

// Glow 2 - blue
context?.saveGState()
context?.setBlendMode(.plusLighter)
let glow2 = NSGradient(colors: [
    NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.12),
    NSColor.clear
])
glow2?.draw(in: NSRect(x: width - 250, y: -50, width: 350, height: 250), angle: -45)
context?.restoreGState()

// Draw a subtle curved arrow
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 200, y: 200))
arrowPath.curve(to: NSPoint(x: 400, y: 200), 
                controlPoint1: NSPoint(x: 260, y: 180),
                controlPoint2: NSPoint(x: 340, y: 180))

// Arrow head
arrowPath.move(to: NSPoint(x: 380, y: 220))
arrowPath.line(to: NSPoint(x: 400, y: 200))
arrowPath.line(to: NSPoint(x: 380, y: 180))

NSColor(white: 1.0, alpha: 0.25).setStroke()
arrowPath.lineWidth = 2.5
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.stroke()

// Draw instruction text
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let textAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(white: 1.0, alpha: 0.7),
    .paragraphStyle: paragraphStyle
]

let text = "Drag MyShot to Applications to install"
let textRect = NSRect(x: 0, y: 45, width: width, height: 30)
text.draw(in: textRect, withAttributes: textAttributes)

// Draw small hint at bottom
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10, weight: .regular),
    .foregroundColor: NSColor(white: 1.0, alpha: 0.4),
    .paragraphStyle: paragraphStyle
]

let hintText = "Free • Open Source • Made with ❤️"
let hintRect = NSRect(x: 0, y: 22, width: width, height: 20)
hintText.draw(in: hintRect, withAttributes: hintAttributes)

image.unlockFocus()

// Save the image
let outputPath = CommandLine.arguments.count > 1 
    ? CommandLine.arguments[1] 
    : "dmg_background.png"

if let tiffData = image.tiffRepresentation,
   let bitmapRep = NSBitmapImageRep(data: tiffData),
   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: outputPath))
    print("✅ Background saved to: \(outputPath)")
} else {
    print("❌ Failed to save image")
    exit(1)
}
