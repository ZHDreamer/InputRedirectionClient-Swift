import AppKit
import GameController

/// Controller-specific icon overrides, followed by Apple's normal symbol fallback.
/// Extend the registry with a product category and stable input aliases. Display
/// names and vendor names are deliberately excluded because they can be localized or renamed.
@MainActor enum ControllerSymbolResolver {
    private static let overrides: [String: [String: String]] = [
        "Switch N64 Controller": [
            "\(GCInputRightThumbstick) Up": "circle.grid.cross.up.filled",
            "\(GCInputRightThumbstick) Down": "circle.grid.cross.down.filled",
            "\(GCInputRightThumbstick) Left": "circle.grid.cross.left.filled",
            "\(GCInputRightThumbstick) Right": "circle.grid.cross.right.filled",
        ]
    ]

    private static let assetOverrides: [String: [String: String]] = [
        "DualSense": [
            GCInputButtonOptions: "DualSense_create_outline",
            GCInputButtonMenu: "DualSense_options_outline",
        ]
    ]
    private static var images: [String: NSImage] = [:]

    static func asset(for element: GCControllerElement?, productCategory: String) -> String? {
        guard let element, let assets = assetOverrides[productCategory] else { return nil }
        return element.aliases.sorted().compactMap { assets[$0] }.first
    }

    static func image(named name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let image = Bundle.module.image(forResource: NSImage.Name(name))?.copy() as? NSImage
        else { return nil }
        image.size = NSSize(width: 24, height: 24)
        images[name] = image
        return image
    }

    static func symbol(for element: GCControllerElement?, productCategory: String) -> String? {
        guard let element else { return nil }
        if let symbols = overrides[productCategory] {
            for alias in element.aliases.sorted() {
                if let symbol = symbols[alias],
                    NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
                {
                    return symbol
                }
            }
        }
        return element.sfSymbolsName
    }
}
