import GameController
import InputCore
import XCTest

@testable import InputRedirection

private final class ProfileOnlyController: GCController {
    private let profile: GCPhysicalInputProfile

    init(profile: GCPhysicalInputProfile) {
        self.profile = profile
        super.init()
    }

    override var physicalInputProfile: GCPhysicalInputProfile { profile }
    override var extendedGamepad: GCExtendedGamepad? { nil }
    override var productCategory: String { "Switch N64 Controller" }
    override var vendorName: String? { "N64 Controller" }
}

final class PhysicalProfileTests: XCTestCase {
    @MainActor func testGenericProfileSupportsButtonsAndSticks() async throws {
        let name = "PhysicalProfile.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let snapshot = GCController.withExtendedGamepad()
        let controller = ProfileOnlyController(profile: snapshot.physicalInputProfile)
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertNil(controller.extendedGamepad)
        XCTAssertEqual(client.controllers.count, 1)
        XCTAssertEqual(client.layout, .nintendo)
        XCTAssertTrue(client.sourceIsAvailable(.a))
        XCTAssertTrue(client.sourceIsAvailable(.leftStick))
        XCTAssertEqual(client.sourceSymbol(.rightStickUp), "circle.grid.cross.up.filled")
        XCTAssertEqual(client.sourceSymbol(.rightStickDown), "circle.grid.cross.down.filled")
        XCTAssertEqual(client.sourceSymbol(.rightStickLeft), "circle.grid.cross.left.filled")
        XCTAssertEqual(client.sourceSymbol(.rightStickRight), "circle.grid.cross.right.filled")
        let gamepad = snapshot.extendedGamepad!
        gamepad.buttonA.setValue(1)
        gamepad.leftThumbstick.setValueForXAxis(0.5, yAxis: -1)
        gamepad.rightThumbstick.setValueForXAxis(-0.25, yAxis: 0.75)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.pressedSources.contains(.a))
        XCTAssertTrue(client.pressed.contains(.a))
        let frame = client.inputFrame()
        XCTAssertEqual(frame.buttons & 1, 1)
        XCTAssertEqual(frame.leftX, 0.5)
        XCTAssertEqual(frame.leftY, -1)
        XCTAssertEqual(frame.rightX, -0.25)
        XCTAssertEqual(frame.rightY, 0.75)
        client.beginMapping(.power)
        gamepad.buttonB.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.power], .b)
    }

    @MainActor func testReducedProfileIsListedAndMissingControlsStayUnavailable() {
        let name = "ReducedProfile.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withMicroGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertNil(controller.extendedGamepad)
        XCTAssertEqual(client.controllers.count, 1)
        XCTAssertTrue(client.sourceIsAvailable(.a))
        XCTAssertFalse(client.sourceIsAvailable(.leftStick))
        XCTAssertFalse(client.availableSources(for: .a).contains(.r2))
        XCTAssertEqual(client.defaultMapping[.circlePad], InputSource.none)
        let frame = client.inputFrame()
        XCTAssertEqual(frame.leftX, 0)
        XCTAssertEqual(frame.rightX, 0)
    }
}
