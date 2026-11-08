import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class ControllerAvailabilityTests: XCTestCase {
    @MainActor func testMissingButtonsAreHiddenAndDefaultToNone() {
        let name = "ControllerAvailability.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertFalse(client.sourceIsAvailable(.capture))
        XCTAssertFalse(client.availableSources(for: .home).contains(.capture))
        XCTAssertTrue(client.availableSources(for: .home).contains(.none))
        XCTAssertTrue(client.availableSources(for: .a).contains(.a))
        XCTAssertEqual(client.defaultMapping[.a], .b)
        for (target, source) in client.layout.defaultMapping() {
            if !client.sourceIsAvailable(source) {
                XCTAssertEqual(client.defaultMapping[target], InputSource.none)
                XCTAssertFalse(client.availableSources(for: target).contains(source))
            }
        }
        XCTAssertEqual(
            client.availableSources(for: .circlePad), [.none, .dpad, .leftStick, .rightStick])
        client.mapping[.home] = .a
        client.restoreDefaults()
        XCTAssertEqual(client.mapping[.home], client.defaultMapping[.home])
    }

    @MainActor func testAvailabilityUpdatesOnControllerChanges() {
        let name = "ControllerAvailabilityChanges.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        var connected = [controller]
        let client = Client(preferences: preferences, controllerProvider: { connected })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.mapping[.power] = .a
        client.save()
        XCTAssertTrue(client.availableSources(for: .power).contains(.a))
        connected = []
        client.refresh()
        XCTAssertEqual(client.availableSources(for: .power), [.none])
        connected = [controller]
        client.refresh()
        XCTAssertTrue(client.availableSources(for: .power).contains(.a))
        XCTAssertEqual(client.mapping[.power], .a)
    }
}
