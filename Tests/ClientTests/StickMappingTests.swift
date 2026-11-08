import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class StickMappingTests: XCTestCase {
    @MainActor func testOutputPreviewIncludesMappedSticks() {
        let name = "StickPreviewTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let gamepad = controller.extendedGamepad!
        gamepad.leftThumbstick.setValueForXAxis(1, yAxis: 0)
        _ = client.inputFrame()
        XCTAssertEqual(client.pressed, [.circlePadRight])
        client.mapping[.cStick] = .leftStick
        XCTAssertEqual(client.pressed, [.circlePadRight, .cStickRight])
        gamepad.leftThumbstick.setValueForXAxis(0, yAxis: 0)
        _ = client.inputFrame()
        XCTAssertTrue(client.pressed.isEmpty)
        client.mapping[.circlePad] = .dpad
        gamepad.dpad.setValueForXAxis(0, yAxis: -1)
        _ = client.inputFrame()
        XCTAssertTrue(client.pressed.contains(.circlePadDown))
        client.invertY = true
        _ = client.inputFrame()
        XCTAssertTrue(client.pressed.contains(.circlePadUp))
        XCTAssertFalse(client.pressed.contains(.circlePadDown))
        for (x, y, expected): (Float, Float, InputTarget) in [
            (-1, 0, .circlePadLeft), (1, 0, .circlePadRight),
            (0, 1, .circlePadDown), (0, -1, .circlePadUp),
        ] {
            gamepad.dpad.setValueForXAxis(x, yAxis: y)
            _ = client.inputFrame()
            XCTAssertTrue(client.pressed.contains(expected))
        }
        client.mapping[.circlePad] = InputSource.none
        XCTAssertFalse(client.pressed.contains(.circlePadUp))
        client.mapping[.circlePadUp] = .a
        XCTAssertNil(client.mapping[.circlePadUp], "Preview directions are not separate mappings")
    }

    @MainActor func testDpadRoutesToBothSticksAndCanBeCaptured() async throws {
        let name = "DpadMappingTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertTrue(client.availableSources(for: .circlePad).contains(.dpad))
        XCTAssertFalse(client.availableSources(for: .a).contains(.dpad))
        client.mapping[.circlePad] = .dpad
        client.mapping[.cStick] = .dpad
        let dpad = controller.extendedGamepad!.dpad
        for (x, y): (Float, Float) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (0, 0)] {
            dpad.setValueForXAxis(x, yAxis: y)
            let frame = client.inputFrame()
            XCTAssertEqual(frame.leftX, Double(x))
            XCTAssertEqual(frame.leftY, Double(y))
            XCTAssertEqual(frame.rightX, Double(x))
            XCTAssertEqual(frame.rightY, Double(y))
        }
        client.invertY = true
        client.beginMapping(.circlePad)
        dpad.setValueForXAxis(0, yAxis: 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(client.mappingTarget)
        XCTAssertEqual(client.mapping[.circlePad], .dpad)
        XCTAssertEqual(client.inputFrame().leftY, -1)
        XCTAssertTrue(client.pressedSources.contains(.up))
        XCTAssertFalse(client.pressedSources.contains(.rightStickUp))
        let restored = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(restored.mapping[.circlePad], .dpad)
        XCTAssertEqual(restored.mapping[.cStick], .dpad)
    }

    @MainActor func testStickAssignmentsRouteAxesAndPersist() {
        let name = "StickMappingTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        controller.extendedGamepad!.leftThumbstick.setValueForXAxis(0.25, yAxis: -0.5)
        controller.extendedGamepad!.rightThumbstick.setValueForXAxis(-0.75, yAxis: 1)
        client.mapping[.circlePad] = .rightStick
        client.mapping[.cStick] = .leftStick
        client.save()
        var expected = InputFrame()
        expected.leftX = -0.75
        expected.leftY = 1
        expected.rightX = 0.25
        expected.rightY = -0.5
        XCTAssertEqual(client.inputFrame().encoded(), expected.encoded())
        client.invertY = true
        expected.leftY = -1
        expected.rightY = 0.5
        XCTAssertEqual(client.inputFrame().encoded(), expected.encoded())
        let restored = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(restored.mapping[.circlePad], .rightStick)
        XCTAssertEqual(restored.mapping[.cStick], .leftStick)
        client.restoreDefaults()
        let reset = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(reset.mapping[.circlePad], .leftStick)
        XCTAssertEqual(reset.mapping[.cStick], .rightStick)
    }
}
