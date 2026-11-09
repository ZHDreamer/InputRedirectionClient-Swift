import AppKit
import GameController
import InputCore

/// Controller-specific icon overrides, followed by Apple's normal symbol fallback.
/// Extend the registry with a product category and stable input aliases. Display
/// names and vendor names are deliberately excluded because they can be localized or renamed.
@MainActor enum ControllerSymbolResolver {
    private static func defaultSymbol(for source: InputSource) -> String {
        switch source {
        case .none: return "nosign"
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .l1: return "l.rectangle.roundedbottom"
        case .r1: return "r.rectangle.roundedbottom"
        case .l2: return "zl.rectangle.roundedtop"
        case .r2: return "zr.rectangle.roundedtop"
        case .dpad: return "dpad"
        case .up: return "dpad.up.filled"
        case .down: return "dpad.down.filled"
        case .left: return "dpad.left.filled"
        case .right: return "dpad.right.filled"
        case .leftStick: return "l.joystick"
        case .rightStick: return "r.joystick"
        case .l3: return "l.joystick.press.down"
        case .r3: return "r.joystick.press.down"
        case .leftStickUp: return "l.joystick.tilt.up"
        case .rightStickUp: return "r.joystick.tilt.up"
        case .leftStickDown: return "l.joystick.tilt.down"
        case .rightStickDown: return "r.joystick.tilt.down"
        case .leftStickLeft: return "l.joystick.tilt.left"
        case .rightStickLeft: return "r.joystick.tilt.left"
        case .leftStickRight: return "l.joystick.tilt.right"
        case .rightStickRight: return "r.joystick.tilt.right"
        case .start: return "plus.circle"
        case .select: return "minus.circle"
        case .home: return "house.circle"
        case .capture: return "circle.square"
        case .touchpad: return "plus.rectangle"
        }
    }

    private static let overrides: [String: [String: String]] = [
        "Switch N64 Controller": [
            "\(GCInputRightThumbstick) Up": "circle.grid.cross.up.filled",
            "\(GCInputRightThumbstick) Down": "circle.grid.cross.down.filled",
            "\(GCInputRightThumbstick) Left": "circle.grid.cross.left.filled",
            "\(GCInputRightThumbstick) Right": "circle.grid.cross.right.filled",
        ],
        "DualSense": [
            GCInputButtonMenu: "DualSense_options_outline",
            GCInputButtonOptions: "DualSense_create_outline",
        ],
    ]

    static func symbol(for element: GCControllerElement?, productCategory: String) -> String? {
        guard let element else { return nil }
        if let symbols = overrides[productCategory] {
            for alias in element.aliases.sorted() {
                if let symbol = symbols[alias], loadImage(named: symbol) != nil {
                    return symbol
                }
            }
        }
        return element.sfSymbolsName
    }

    private static var images: [String: NSImage] = [:]

    static func image(for source: InputSource, symbol: String?, font: NSFont) -> NSImage? {
        if let symbol, let image = image(named: symbol, font: font) { return image }
        return image(named: defaultSymbol(for: source), font: font)
    }

    static func image(named name: String, font: NSFont) -> NSImage? {
        loadImage(named: name).map { fittedImage($0, font: font) }
    }

    private static func loadImage(named name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? Bundle.module.image(forResource: NSImage.Name(name))
        else { return nil }
        images[name] = image
        return image
    }

    private static func fittedImage(_ image: NSImage, font: NSFont) -> NSImage {
        let configured =
            image.withSymbolConfiguration(
                .init(pointSize: font.pointSize, weight: .regular, scale: .medium)) ?? image
        guard let fitted = configured.copy() as? NSImage,
            fitted.size.width > 0, fitted.size.height > 0
        else { return configured }
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let scale = min(1, lineHeight / max(fitted.size.width, fitted.size.height))
        fitted.size = NSSize(width: fitted.size.width * scale, height: fitted.size.height * scale)
        return fitted
    }
}
