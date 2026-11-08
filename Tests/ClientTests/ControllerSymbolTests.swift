import AppKit
import GameController
import XCTest

@testable import InputRedirection

private final class LocalizedButton: GCControllerButtonInput {
    private let inputAliases: Set<String>
    private var displayName: String?

    init(aliases: Set<String>) {
        inputAliases = aliases
        super.init()
    }

    override var aliases: Set<String> { inputAliases }
    override var localizedName: String? {
        get { displayName }
        set { displayName = newValue }
    }
}

final class ControllerSymbolTests: XCTestCase {
    @MainActor func testN64DirectionIconsIgnoreLocalizedNames() throws {
        let controller = GCController.withExtendedGamepad()
        let stick = try XCTUnwrap(controller.extendedGamepad).rightThumbstick
        let directions: [(GCControllerButtonInput, String)] = [
            (stick.up, "circle.grid.cross.up.filled"),
            (stick.down, "circle.grid.cross.down.filled"),
            (stick.left, "circle.grid.cross.left.filled"),
            (stick.right, "circle.grid.cross.right.filled"),
        ]
        let names: [String?] = [
            "C Buttons (Left)",
            "C \u{952e}\u{ff08}\u{5de6}\u{ff09}",
            "C\u{30dc}\u{30bf}\u{30f3}\u{ff08}\u{5de6}\u{ff09}",
            nil,
        ]
        for (systemButton, expected) in directions {
            // Directional elements synthesize their names, so use a controllable
            // element with the real system aliases to exercise different locales.
            let button = LocalizedButton(aliases: systemButton.aliases)
            button.sfSymbolsName = nil
            for name in names {
                button.localizedName = name
                XCTAssertEqual(
                    ControllerSymbolResolver.symbol(
                        for: button, productCategory: "Switch N64 Controller"),
                    expected)
                XCTAssertNotNil(NSImage(systemSymbolName: expected, accessibilityDescription: nil))
                XCTAssertEqual(button.localizedName, name)
                XCTAssertNil(
                    button.sfSymbolsName, "Overrides must not mutate the system input metadata")
            }
        }
    }

    @MainActor func testOverridesAreScopedAndPreserveSystemFallback() throws {
        let controller = GCController.withExtendedGamepad()
        let gamepad = try XCTUnwrap(controller.extendedGamepad)
        let direction = gamepad.rightThumbstick.left
        direction.sfSymbolsName = "l.circle"
        XCTAssertEqual(
            ControllerSymbolResolver.symbol(for: direction, productCategory: "Xbox One"), "l.circle"
        )
        XCTAssertEqual(
            ControllerSymbolResolver.symbol(
                for: direction, productCategory: "Switch Pro Controller"),
            "l.circle")
        XCTAssertEqual(
            ControllerSymbolResolver.symbol(
                for: direction, productCategory: "Switch N64 Controller"),
            "circle.grid.cross.left.filled")
        gamepad.buttonA.sfSymbolsName = "a.circle"
        XCTAssertEqual(
            ControllerSymbolResolver.symbol(
                for: gamepad.buttonA, productCategory: "Switch N64 Controller"),
            "a.circle")
        gamepad.buttonA.sfSymbolsName = nil
        XCTAssertNil(
            ControllerSymbolResolver.symbol(
                for: gamepad.buttonA, productCategory: "Switch N64 Controller"))
        XCTAssertNil(
            ControllerSymbolResolver.symbol(for: nil, productCategory: "Switch N64 Controller"))
    }
}
