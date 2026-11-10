import AppKit
import SwiftUI
import XCTest

@testable import InputRedirection

final class MappingPanelTests: XCTestCase {
    @MainActor func testHeightFitsContentAndShrinksToLimit() async throws {
        let name = "MappingPanel.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let client = Client(preferences: preferences, controllerProvider: { [] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let host = NSHostingView(
            rootView: MappingPanel(client: client, maximumWidth: 592, maximumHeight: 1600))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 1600)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let naturalHeight = host.fittingSize.height
        XCTAssertEqual(host.fittingSize.width, 592, accuracy: 1)
        XCTAssertGreaterThan(naturalHeight, 350)
        XCTAssertLessThan(naturalHeight, 1600)
        for limit: CGFloat in [350, 1600, 350] {
            host.rootView = MappingPanel(client: client, maximumWidth: 592, maximumHeight: limit)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(host.fittingSize.height, min(naturalHeight, limit), accuracy: 1)
        }
    }
}
