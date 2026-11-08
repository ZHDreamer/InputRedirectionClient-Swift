import GameController
import InputCore
import XCTest

@testable import InputRedirection

private final class NamedController: GCController {
    private let inputSnapshot: GCController
    private let category: String
    private let name: String

    init(category: String, name: String, inputs: GCController = GCController.withExtendedGamepad())
    {
        inputSnapshot = inputs
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
        XCTAssertEqual(client.sendRate, 220)
        XCTAssertEqual(client.address, "10.0.0.3")
        client.mapping[.x] = .a
        client.sendRate = 75
        client.selected = 0
        XCTAssertEqual(client.mapping[.x], .rightStickDown)
        XCTAssertEqual(client.mapping[.cStick], InputSource.none)
        XCTAssertTrue(client.invertY)
        XCTAssertEqual(client.sendRate, 75)
        client.restoreDefaults()
        XCTAssertEqual(client.mapping[.x], .x)
        client.selected = 1
        XCTAssertEqual(client.mapping[.x], .a)
        XCTAssertEqual(client.sendRate, 75)
        XCTAssertEqual(preferences.integer(forKey: "sendRate"), 75)
        let profiles = preferences.dictionary(forKey: "controllerProfiles") ?? [:]
        for value in profiles.values {
            XCTAssertNil((value as? [String: Any])?["sendRate"])
        }
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
        XCTAssertEqual(
            ControllerProfileStore.key(for: reconnected), ControllerProfileStore.key(for: original))
        let key = ControllerProfileStore.key(for: reconnected)
        XCTAssertEqual(key.count, 64)
        XCTAssertTrue(key.allSatisfy { "0123456789abcdef".contains($0) })
        connected = [reconnected]
        client.refresh()
        XCTAssertEqual(client.mapping[.power], .a)
        XCTAssertTrue(client.invertY)
        XCTAssertEqual(client.sendRate, 50)
        let restarted = Client(preferences: preferences, controllerProvider: { [reconnected] })
        defer { restarted.stop() }
        XCTAssertEqual(restarted.mapping[.power], .a)
        XCTAssertTrue(restarted.invertY)
        XCTAssertEqual(restarted.sendRate, 50)
    }

    @MainActor func testSameCategoryWithDifferentControlsHasSeparateProfiles() {
        let name = "ControllerProfileControls.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let extended = NamedController(category: "Generic", name: "Gamepad")
        let reduced = NamedController(
            category: "Generic", name: "Gamepad", inputs: GCController.withMicroGamepad())
        let client = Client(preferences: preferences, controllerProvider: { [extended, reduced] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertNotEqual(
            ControllerProfileStore.key(for: extended), ControllerProfileStore.key(for: reduced))
        client.mapping[.power] = .rightStickUp
        client.selected = 1
        XCTAssertEqual(client.mapping[.power], InputSource.none)
        client.mapping[.power] = .a
        client.selected = 0
        XCTAssertEqual(client.mapping[.power], .rightStickUp)
        client.selected = 1
        XCTAssertEqual(client.mapping[.power], .a)
    }

    @MainActor func testUnassignedProfileStaysInMemory() {
        let name = "InMemoryProfile.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        preferences.set(
            [
                "unassigned": ["invertY": true, "mappingOverrides": ["Power": "X"]]
            ], forKey: "controllerProfiles")
        let controller = NamedController(category: "Xbox One", name: "Xbox Controller")
        var connected: [GCController] = []
        let client = Client(preferences: preferences, controllerProvider: { connected })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        XCTAssertFalse(client.invertY)
        client.mapping[.power] = .b
        client.invertY = true
        client.save()
        XCTAssertNil(preferences.dictionary(forKey: "controllerProfiles")?["unassigned"])
        connected = [controller]
        client.refresh()
        XCTAssertEqual(client.mapping[.power], InputSource.none)
        XCTAssertFalse(client.invertY)
        client.mapping[.power] = .a
        connected = []
        client.refresh()
        XCTAssertEqual(client.mapping[.power], .b)
        XCTAssertTrue(client.invertY)
        client.save()
        let profiles = preferences.dictionary(forKey: "controllerProfiles") ?? [:]
        XCTAssertNil(profiles["unassigned"])
        XCTAssertEqual(profiles.count, 1)
        let restarted = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(restarted.mapping[.power], InputSource.none)
        XCTAssertFalse(restarted.invertY)
        let reconnected = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(reconnected.mapping[.power], .a)
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
