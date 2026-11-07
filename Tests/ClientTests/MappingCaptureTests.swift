import AppKit
import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class MappingCaptureTests: XCTestCase {
    @MainActor func testCaptureButtonsSticksAndCancellation() async throws {
        let name = "MappingCapture.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer { client.stop()
            preferences.removePersistentDomain(forName: name) }
        let gamepad = controller.extendedGamepad!
        client.beginMapping(.x)
        gamepad.buttonA.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.x], InputSource.a)
        XCTAssertNil(client.mappingTarget)
        gamepad.buttonB.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.x], InputSource.a)
        client.beginMapping(.home)
        client.cancelMapping()
        gamepad.buttonX.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.home], InputSource.none)
        client.beginMapping(.circlePad)
        gamepad.rightThumbstick.setValueForXAxis(0.1, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mappingTarget, .circlePad, "Small drift must not assign a stick")
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.circlePad], .rightStick)
        XCTAssertNil(client.mappingTarget)
        let restored = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(restored.mapping[.x], InputSource.a)
        XCTAssertEqual(restored.mapping[.circlePad], .rightStick)
        client.beginMapping(.power)
        client.refresh()
        XCTAssertNil(client.mappingTarget)
    }
}
