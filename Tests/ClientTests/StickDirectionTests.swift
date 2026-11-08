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
            client.inputFrame().buttons & 3, 2,
            "Exact diagonals must choose one horizontal direction")
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

    @MainActor func testNinetyDegreeSectorsAcrossBothSticks() {
        let name = "StickSectors.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let gamepad = controller.extendedGamepad!
        let sticks: [(GCControllerDirectionPad, [InputSource])] = [
            (
                gamepad.leftThumbstick,
                [.leftStickRight, .leftStickUp, .leftStickLeft, .leftStickDown]
            ),
            (
                gamepad.rightThumbstick,
                [.rightStickRight, .rightStickUp, .rightStickLeft, .rightStickDown]
            ),
        ]
        for (stick, directions) in sticks {
            client.mapping[.a] = directions[0]
            client.mapping[.b] = directions[1]
            client.mapping[.x] = directions[2]
            client.mapping[.y] = directions[3]
            for degree in 0..<360 where degree % 90 != 45 {
                let angle = Double(degree) * .pi / 180
                stick.setValueForXAxis(Float(cos(angle)), yAxis: Float(sin(angle)))
                let expected: UInt32
                switch degree {
                case 0..<45, 316..<360: expected = 1
                case 46..<135: expected = 1 << 1
                case 136..<225: expected = 1 << 10
                default: expected = 1 << 11
                }
                XCTAssertEqual(
                    client.inputFrame().buttons, expected, "Incorrect sector at \(degree) degrees")
            }
            for (x, y, expected): (Float, Float, UInt32) in [
                (1, 1, 1), (1, -1, 1), (-1, 1, 1 << 10), (-1, -1, 1 << 10),
                (1, -0.1, 1), (0.1, -1, 1 << 11),
            ] {
                stick.setValueForXAxis(x, yAxis: y)
                XCTAssertEqual(client.inputFrame().buttons, expected)
            }
            stick.setValueForXAxis(0, yAxis: 0)
            XCTAssertEqual(client.inputFrame().buttons, 0)
        }
    }

    @MainActor func testListeningAndPreviewUseDominantDirection() async throws {
        let name = "StickSectorCapture.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let stick = controller.extendedGamepad!.rightThumbstick
        client.beginMapping(.a)
        stick.setValueForXAxis(1, yAxis: -0.1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.a], .rightStickRight)
        XCTAssertTrue(client.pressedSources.contains(.rightStickRight))
        XCTAssertFalse(client.pressedSources.contains(.rightStickDown))
        stick.setValueForXAxis(0.1, yAxis: -1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(client.pressedSources.contains(.rightStickRight))
        XCTAssertTrue(client.pressedSources.contains(.rightStickDown))
        XCTAssertEqual(client.inputFrame().buttons & 1, 0)
        stick.setValueForXAxis(0, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(client.pressedSources.contains(.rightStickDown))
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
