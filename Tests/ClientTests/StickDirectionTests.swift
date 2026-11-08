import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class StickDirectionTests: XCTestCase {
    @MainActor func testAllStickDirectionsSendButtonsAndRelease() {
        let name = "StickDirections.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let gamepad = controller.extendedGamepad!
        let directions: [(InputSource, GCControllerDirectionPad, Float, Float)] = [
            (.leftStickUp, gamepad.leftThumbstick, 0, 1),
            (.leftStickDown, gamepad.leftThumbstick, 0, -1),
            (.leftStickLeft, gamepad.leftThumbstick, -1, 0),
            (.leftStickRight, gamepad.leftThumbstick, 1, 0),
            (.rightStickUp, gamepad.rightThumbstick, 0, 1),
            (.rightStickDown, gamepad.rightThumbstick, 0, -1),
            (.rightStickLeft, gamepad.rightThumbstick, -1, 0),
            (.rightStickRight, gamepad.rightThumbstick, 1, 0),
        ]
        for (source, stick, x, y) in directions {
            XCTAssertTrue(client.availableSources(for: .a).contains(source))
            XCTAssertFalse(client.availableSources(for: .circlePad).contains(source))
            client.mapping[.a] = source
            stick.setValueForXAxis(x, yAxis: y)
            XCTAssertEqual(client.inputFrame().buttons & 1, 1, source.rawValue)
            stick.setValueForXAxis(0, yAxis: 0)
            XCTAssertEqual(client.inputFrame().buttons & 1, 0, source.rawValue)
        }
        client.mapping[.a] = .rightStickUp
        client.mapping[.b] = .rightStickRight
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 1)
        XCTAssertEqual(
            client.inputFrame().buttons & 3, 3, "Diagonals must allow simultaneous buttons")
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 0)
        XCTAssertEqual(client.inputFrame().buttons & 3, 0)
        client.mapping[.cStick] = InputSource.none
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 1)
        let buttonsOnly = client.inputFrame()
        XCTAssertEqual(buttonsOnly.buttons & 1, 1)
        XCTAssertEqual(buttonsOnly.rightX, 0)
        XCTAssertEqual(buttonsOnly.rightY, 0)
    }

    @MainActor func testListeningAndPersistencePreserveAnalogAxes() async throws {
        let name = "StickDirectionCapture.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let gamepad = controller.extendedGamepad!
        client.beginMapping(.x)
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.x], .rightStickUp)
        XCTAssertNil(client.mappingTarget)
        XCTAssertEqual(client.inputFrame().buttons & (1 << 10), 1 << 10)
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(client.pressed.contains(.x))
        client.beginMapping(.circlePad)
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            client.mapping[.circlePad], .rightStick, "Full-stick capture must remain available")
        gamepad.rightThumbstick.setValueForXAxis(0.125, yAxis: -0.375)
        let frame = client.inputFrame()
        XCTAssertEqual(frame.leftX, 0.125)
        XCTAssertEqual(frame.leftY, -0.375)
        XCTAssertEqual(frame.rightX, 0.125)
        XCTAssertEqual(frame.rightY, -0.375)
        let restored = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(restored.mapping[.x], .rightStickUp)
        XCTAssertEqual(restored.mapping[.circlePad], .rightStick)
        client.refresh()
        gamepad.rightThumbstick.setValueForXAxis(0, yAxis: 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.pressedSources.contains(.rightStickUp))
        XCTAssertTrue(client.pressed.contains(.x))
    }

    @MainActor func testMissingStickDirectionsAreHidden() {
        let name = "MissingStickDirections.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withMicroGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertFalse(client.availableSources(for: .a).contains(.leftStickUp))
        XCTAssertFalse(client.availableSources(for: .a).contains(.rightStickUp))
    }
}
