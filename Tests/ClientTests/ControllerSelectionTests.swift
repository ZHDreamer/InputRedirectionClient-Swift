import GameController
import XCTest

@testable import InputRedirection

final class ControllerSelectionTests: XCTestCase {
    @MainActor func testButtonSelectsControllerOnlyWhileListening() async throws {
        let name = "ControllerSelection.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let first = GCController.withExtendedGamepad()
        let second = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [first, second] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let button = second.extendedGamepad!.buttonA
        button.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.currentController === first)
        client.beginControllerSelection()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.isSelectingController, "An already-held button must not select")
        button.setValue(0)
        button.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.currentController === second)
        XCTAssertFalse(client.isSelectingController)
        button.setValue(0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(client.pressedSources.contains(.a))
        button.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(
            client.pressedSources.contains(.a), "Normal input handlers must remain active")
        button.setValue(0)
        client.beginControllerSelection()
        button.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(
            client.isSelectingController, "Pressing the selected controller also closes the menu")
        XCTAssertTrue(client.currentController === second)
    }

    @MainActor func testCancellationIgnoresQueuedPressAndRestoresHandlers() async throws {
        let name = "ControllerSelectionCancel.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let first = GCController.withExtendedGamepad()
        let second = GCController.withExtendedGamepad()
        var connected = [first, second]
        let client = Client(preferences: preferences, controllerProvider: { connected })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let button = second.extendedGamepad!.buttonA
        XCTAssertNil(button.pressedChangedHandler)
        client.beginControllerSelection()
        button.setValue(1)
        client.cancelControllerSelection()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.currentController === first)
        XCTAssertFalse(client.isSelectingController)
        XCTAssertNil(button.pressedChangedHandler)
        button.setValue(0)
        client.beginControllerSelection()
        connected = [first]
        client.refresh()
        button.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.currentController === first)
        XCTAssertFalse(client.isSelectingController)
        XCTAssertNil(button.pressedChangedHandler)
    }
}
