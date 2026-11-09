import AppKit
import GameController
import InputCore
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
    @MainActor func testImagesResolveAndFitFontLineHeightIndependently() throws {
        let smallFont = NSFont.systemFont(ofSize: 11)
        let largeFont = NSFont.systemFont(ofSize: 18)
        for name in ["a.circle", "DualSense_options_outline"] {
            let small = try XCTUnwrap(ControllerSymbolResolver.image(named: name, font: smallFont))
            let originalSize = small.size
            let large = try XCTUnwrap(ControllerSymbolResolver.image(named: name, font: largeFont))
            for (image, font) in [(small, smallFont), (large, largeFont)] {
                let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
                XCTAssertLessThanOrEqual(image.size.width, lineHeight)
                XCTAssertLessThanOrEqual(image.size.height, lineHeight)
                XCTAssertTrue(image.isTemplate)
                XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
            XCTAssertEqual(small.size, originalSize)
            XCTAssertFalse(small === large)
            XCTAssertGreaterThan(large.size.height, small.size.height)
            if name == "DualSense_options_outline" {
                XCTAssertEqual(
                    small.size.width / small.size.height,
                    large.size.width / large.size.height, accuracy: 0.001)
            }
        }
        XCTAssertNil(ControllerSymbolResolver.image(named: "MissingIcon", font: smallFont))
    }

    @MainActor func testDualSenseOverridesSupportCustomSymbols() throws {
        for (alias, symbol) in [
            (GCInputButtonOptions, "DualSense_create_outline"),
            (GCInputButtonMenu, "DualSense_options_outline"),
        ] {
            let button = LocalizedButton(aliases: [alias])
            for name in ["Create", "Options", "分享", "选项"] {
                button.localizedName = name
                XCTAssertEqual(
                    ControllerSymbolResolver.symbol(
                        for: button, productCategory: "DualSense"), symbol
                )
            }
        }
        let font = NSFont.menuFont(ofSize: 0)
        for name in ["DualSense_create_outline", "DualSense_options_outline"] {
            let image = try XCTUnwrap(ControllerSymbolResolver.image(named: name, font: font))
            XCTAssertTrue(image.isTemplate)
        }
    }

    @MainActor func testDefaultSymbolsAreAvailableAndSystemSymbolsTakePriority() {
        for source in InputSource.allCases {
            XCTAssertNotNil(
                ControllerSymbolResolver.image(
                    for: source, symbol: nil, font: .systemFont(ofSize: NSFont.systemFontSize)),
                source.rawValue)
        }
        for target in InputTarget.allCases where target != .start && target != .select {
            XCTAssertNotNil(target.defaultSymbol, target.rawValue)
            if let symbol = target.defaultSymbol {
                XCTAssertNotNil(
                    NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
            }
        }
        XCTAssertNil(InputTarget.start.defaultSymbol)
        XCTAssertNil(InputTarget.select.defaultSymbol)
        let name = "DefaultSymbols.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        let controller = GCController.withExtendedGamepad()
        controller.extendedGamepad!.buttonA.sfSymbolsName = "triangle.circle"
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer { client.stop() }
        assertSourceImage(client, .a, named: "triangle.circle")
        controller.extendedGamepad!.buttonA.sfSymbolsName = "MissingSymbol"
        client.refresh()
        assertSourceImage(client, .a, named: "a.circle")
        let offline = Client(preferences: preferences, controllerProvider: { [] })
        assertSourceImage(offline, .a, named: "a.circle")
    }

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

@MainActor func assertSourceImage(
    _ client: Client, _ source: InputSource, named name: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    guard let actual = client.sourceImage(source, font: font)?.tiffRepresentation,
        let expected = ControllerSymbolResolver.image(named: name, font: font)?.tiffRepresentation
    else {
        XCTFail("Missing image for \(source.rawValue) or \(name)", file: file, line: line)
        return
    }
    XCTAssertEqual(
        actual, expected, "Unexpected image for \(source.rawValue)", file: file, line: line)
}
