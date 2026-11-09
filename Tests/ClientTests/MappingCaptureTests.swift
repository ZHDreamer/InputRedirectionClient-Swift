import AppKit
import GameController
import InputCore
import SwiftUI
import XCTest

@testable import InputRedirection

final class MappingCaptureTests: XCTestCase {
    @MainActor func testMenuTeardownDoesNotPublishSynchronously() async throws {
        let name = "MenuTeardown.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let client = Client(preferences: preferences, controllerProvider: { [] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let controllerCoordinator = ControllerMenu.Coordinator(client: client)
        let mappingCoordinator = MappingMenu.Coordinator(client: client, target: .home)
        let menu = NSMenu()
        let button = NSPopUpButton()
        var publications = 0
        let subscription = client.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        ControllerMenu.dismantleNSView(button, coordinator: controllerCoordinator)
        MappingMenu.dismantleNSView(button, coordinator: mappingCoordinator)
        XCTAssertEqual(publications, 0, "Idle teardown must not mutate shared state")

        controllerCoordinator.menu = menu
        menu.delegate = controllerCoordinator
        controllerCoordinator.menuWillOpen(menu)
        publications = 0
        ControllerMenu.dismantleNSView(button, coordinator: controllerCoordinator)
        XCTAssertEqual(publications, 0)
        XCTAssertNil(menu.delegate)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(client.isSelectingController)

        mappingCoordinator.menu = menu
        menu.delegate = mappingCoordinator
        mappingCoordinator.menuWillOpen(menu)
        publications = 0
        MappingMenu.dismantleNSView(button, coordinator: mappingCoordinator)
        XCTAssertEqual(publications, 0)
        XCTAssertNil(menu.delegate)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(client.mappingTarget)
    }

    @MainActor func testNativePopupKeepsIconOnlyLabelAndSelectsInput() async throws {
        let name = "MappingPopup.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let host = NSHostingView(rootView: MappingMenu(client: client, target: .home))
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 26)
        host.layoutSubtreeIfNeeded()
        func findPopup(in view: NSView) -> NSPopUpButton? {
            (view as? NSPopUpButton) ?? view.subviews.lazy.compactMap { findPopup(in: $0) }.first
        }
        let button = try XCTUnwrap(findPopup(in: host))
        let cell = try XCTUnwrap(button.cell as? NSPopUpButtonCell)
        XCTAssertEqual(cell.arrowPosition, .noArrow)
        XCTAssertFalse(cell.usesItemFromMenu)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        let menu = try XCTUnwrap(button.menu)
        let item = try XCTUnwrap(menu.items.first { ($0.representedObject as? InputSource) == .a })
        button.select(item)
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        XCTAssertEqual(client.mapping[.home], .a)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.selectedItem?.representedObject as? InputSource, .a)
        XCTAssertEqual(cell.menuItem?.title, "")
        XCTAssertNotNil(cell.menuItem?.image)
    }

    @MainActor func testCaptureButtonsSticksAndCancellation() async throws {
        let name = "MappingCapture.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let gamepad = controller.extendedGamepad!
        client.beginMapping(.x)
        gamepad.buttonA.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.x], InputSource.a)
        XCTAssertNil(client.mappingTarget)
        gamepad.buttonB.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.x], InputSource.a)
        let previousHome = client.mapping[.home]
        client.beginMapping(.home)
        client.cancelMapping()
        gamepad.buttonX.setValue(1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.home], previousHome)
        client.beginMapping(.circlePad)
        gamepad.rightThumbstick.setValueForXAxis(0.1, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mappingTarget, .circlePad, "Small drift must not assign a stick")
        gamepad.rightThumbstick.setValueForXAxis(1, yAxis: 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.mapping[.circlePad], .rightStick)
        XCTAssertNil(client.mappingTarget)
        let restored = Client(preferences: preferences, controllerProvider: { [controller] })
        XCTAssertEqual(restored.mapping[.x], InputSource.a)
        XCTAssertEqual(restored.mapping[.circlePad], .rightStick)
        client.beginMapping(.power)
        client.refresh()
        XCTAssertNil(client.mappingTarget)
    }
}
