import AppKit
import SwiftUI
import XCTest

@testable import InputRedirection

final class ContentLayoutTests: XCTestCase {
    @MainActor func testFixedWindowSizeIncludesContentPadding() {
        let name = "ContentLayout.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let client = Client(preferences: preferences, controllerProvider: { [] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        let content = ContentView(client: client)
            .fixedSize(horizontal: true, vertical: true)
        let controller = NSHostingController(rootView: content)
        let minimum = controller.sizeThatFits(in: .zero)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(minimum.height, host.fittingSize.height, accuracy: 1)
        let expanded = controller.sizeThatFits(in: NSSize(width: 1400, height: 1200))
        XCTAssertEqual(expanded.width, minimum.width, accuracy: 1)
        XCTAssertEqual(expanded.height, minimum.height, accuracy: 1)
        XCTAssertLessThan(host.fittingSize.height, 650)
        host.setFrameSize(minimum)
        host.layoutSubtreeIfNeeded()
        func findTouchView(in view: NSView) -> TouchView? {
            (view as? TouchView) ?? view.subviews.lazy.compactMap { findTouchView(in: $0) }.first
        }
        guard let touch = findTouchView(in: host) else {
            return XCTFail("Touch surface must be present")
        }
        let bounds = touch.convert(touch.bounds, to: host)
        let bottomPadding = host.isFlipped ? host.bounds.maxY - bounds.maxY : bounds.minY
        XCTAssertEqual(bounds.height, 240, accuracy: 1)
        XCTAssertEqual(bottomPadding, 24, accuracy: 1)
    }
}
