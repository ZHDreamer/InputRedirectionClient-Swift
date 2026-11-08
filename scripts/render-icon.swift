import AppKit
import Foundation

// Render the vector master with native AppKit. PNGs are temporary iconutil inputs;
// the SVG is the only artwork source checked into the repository.
func renderIconSet(source: URL, destination: URL) throws {
    guard let image = NSImage(contentsOf: source) else {
        throw NSError(
            domain: "AppIcon", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to read SVG icon: \(source.path)"])
    }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap)
            else {
                throw NSError(
                    domain: "AppIcon", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create icon bitmap"])
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            image.draw(
                in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(
                    domain: "AppIcon", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to encode icon bitmap"])
            }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(
                to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(
            domain: "AppIcon", code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Usage: swift render-icon.swift source.svg output.iconset"
            ])
    }
    try renderIconSet(
        source: URL(fileURLWithPath: CommandLine.arguments[1]),
        destination: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    FileHandle.standardError.write(
        Data("Icon rendering failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
