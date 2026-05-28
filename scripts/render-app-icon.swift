// Renders the canonical 1024×1024 Winch app icon to a path provided
// as the first command-line argument. Blue gradient squircle background
// with a centered 4-direction-arrow SF Symbol in white.

import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render-app-icon.swift <output-path>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = CommandLine.arguments[1]

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// macOS squircle approximation: corner radius ~22.4% of side length.
let radius: CGFloat = size * 0.224
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: radius, yRadius: radius)

// Vertical gradient: lighter top → deeper bottom.
let top = NSColor(red: 0.31, green: 0.62, blue: 1.0, alpha: 1.0)     // #4F9EFF
let bottom = NSColor(red: 0.10, green: 0.36, blue: 0.85, alpha: 1.0) // #1A5CD9
let gradient = NSGradient(starting: top, ending: bottom)!
bgPath.addClip()
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// SF Symbol foreground at ~60% canvas size, white.
let symbolPt = size * 0.60
let baseConfig = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let config = baseConfig.applying(colorConfig)

guard let symbol = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
                           accessibilityDescription: nil)?
                           .withSymbolConfiguration(config) else {
    FileHandle.standardError.write("symbol not found\n".data(using: .utf8)!)
    exit(1)
}
let s = symbol.size
symbol.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1.0)

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("PNG encode failed\n".data(using: .utf8)!)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
