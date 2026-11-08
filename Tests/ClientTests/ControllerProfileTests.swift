import GameController
import InputCore
import XCTest

@testable import InputRedirection

private final class NamedController: GCController {
    private let inputSnapshot = GCController.withExtendedGamepad()
    private let category: String
    private let name: String

    init(category: String, name: String) {
        self.category = category
        self.name = name
        super.init()
    }

    override var productCategory: String { category }
    override var vendorName: String? { name }
    override var physicalInputProfile: GCPhysicalInputProfile { inputSnapshot.physicalInputProfile }
    override var extendedGamepad: GCExtendedGamepad? { inputSnapshot.extendedGamepad }
}

final class ControllerProfileTests: XCTestCase {
    @MainActor func testControllersKeepIndependentMappingsAndSettings() {
        let name = "ControllerProfiles.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let n64 = NamedController(category: "Switch N64 Controller", name: "N64 Controller")
        let xbox = NamedController(category: "Xbox One", name: "Xbox Controller")
        let client = Client(preferences: preferences, controllerProvider: { [n64, xbox] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.mapping[.x] = .rightStickDown
        client.mapping[.cStick] = InputSource.none
        client.invertY = true
        client.sendRate = 220
        client.address = "10.0.0.3"
        client.save()
        client.selected = 1
        XCTAssertEqual(client.mapping[.x], .y)
        XCTAssertEqual(client.mapping[.cStick], .rightStick)
        XCTAssertFalse(client.invertY)
        XCTAssertEqual(client.sendRate, 120)
        XCTAssertEqual(client.address, "10.0.0.3")
        client.mapping[.x] = .a
        client.sendRate = 75
        client.selected = 0
        XCTAssertEqual(client.mapping[.x], .rightStickDown)
        XCTAssertEqual(client.mapping[.cStick], InputSource.none)
        XCTAssertTrue(client.invertY)
        XCTAssertEqual(client.sendRate, 220)
        client.restoreDefaults()
        XCTAssertEqual(client.mapping[.x], .x)
        client.selected = 1
        XCTAssertEqual(client.mapping[.x], .a)
        XCTAssertEqual(client.sendRate, 75)
    }

    @MainActor func testProfilesSurviveDisconnectReconnectAndRestart() {
        let name = "ControllerProfileReconnect.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let original = NamedController(category: "Switch N64 Controller", name: "N64 Controller")
        var connected: [GCController] = [original]
        let client = Client(preferences: preferences, controllerProvider: { connected })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.mapping[.power] = .a
        client.invertY = true
        client.sendRate = 180
        connected = []
        client.refresh()
        XCTAssertFalse(client.invertY)
        client.mapping[.power] = .b
        client.sendRate = 50
        let reconnected = NamedController(category: "Switch N64 Controller", name: "Renamed N64")
        XCTAssertEqual(ControllerProfileStore.key(for: reconnected), "Switch N64 Controller")
        connected = [reconnected]
        client.refresh()
        XCTAssertEqual(client.mapping[.power], .a)
        XCTAssertTrue(client.invertY)
        XCTAssertEqual(client.sendRate, 180)
        let restarted = Client(preferences: preferences, controllerProvider: { [reconnected] })
        defer { restarted.stop() }
        XCTAssertEqual(restarted.mapping[.power], .a)
        XCTAssertTrue(restarted.invertY)
        XCTAssertEqual(restarted.sendRate, 180)
    }

    @MainActor func testRefreshPreservesSelectionWhenControllerOrderChanges() {
        let name = "ControllerProfileOrder.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let n64 = NamedController(category: "Switch N64 Controller", name: "N64 Controller")
        let xbox = NamedController(category: "Xbox One", name: "Xbox Controller")
        var connected: [GCController] = [n64, xbox]
        let client = Client(preferences: preferences, controllerProvider: { connected })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        client.selected = 1
        client.mapping[.power] = .x
        connected = [xbox, n64]
        client.refresh()
        XCTAssertTrue(client.currentController === xbox)
        XCTAssertEqual(client.selected, 0)
        XCTAssertEqual(client.mapping[.power], .x)
        client.selected = 1
        XCTAssertTrue(client.currentController === n64)
        XCTAssertEqual(client.mapping[.power], InputSource.none)
    }
}
