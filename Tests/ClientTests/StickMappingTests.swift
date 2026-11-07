import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class StickMappingTests: XCTestCase {
    @MainActor func testStickAssignmentsRouteAxesAndPersist() {
        let name = "StickMappingTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer { client.stop()
            preferences.removePersistentDomain(forName: name) }
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
        let restored = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(restored.mapping[.circlePad], .rightStick)
        XCTAssertEqual(restored.mapping[.cStick], .leftStick)
        client.restoreDefaults()
        let reset = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(reset.mapping[.circlePad], .leftStick)
        XCTAssertEqual(reset.mapping[.cStick], .rightStick)
    }
}
