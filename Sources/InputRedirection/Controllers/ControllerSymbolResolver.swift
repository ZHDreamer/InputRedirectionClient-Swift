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
