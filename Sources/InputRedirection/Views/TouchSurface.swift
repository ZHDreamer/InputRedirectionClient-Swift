import AppKit
import SwiftUI

struct TouchSurface: NSViewRepresentable {
    var client: Client
    func makeNSView(context: Context) -> TouchView {
        let view = TouchView()
        view.client = client
        return view
    }
    func updateNSView(_ nsView: TouchView, context: Context) { nsView.client = client }
}
final class TouchView: NSView {
    weak var client: Client?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for x in stride(from: 0.0, through: bounds.width, by: 40) {
            grid.move(to: NSPoint(x: x, y: 0))
            grid.line(to: NSPoint(x: x, y: bounds.height))
        }
        for y in stride(from: 0.0, through: bounds.height, by: 40) {
            grid.move(to: NSPoint(x: 0, y: y))
            grid.line(to: NSPoint(x: bounds.width, y: y))
        }
        grid.stroke()
        if let (x, y) = client?.touch {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: x - 5, y: y - 5, width: 10, height: 10)).fill()
        }
    }
    private func update(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        client?.touch = (max(0, min(320, p.x)), max(0, min(240, p.y)))
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) { update(event) }
    override func mouseDragged(with event: NSEvent) { update(event) }
    override func mouseUp(with event: NSEvent) {
        client?.touch = nil
        needsDisplay = true
    }
}
