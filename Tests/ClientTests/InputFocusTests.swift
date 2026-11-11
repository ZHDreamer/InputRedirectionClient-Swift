import AppKit
import XCTest

@testable import InputRedirection

final class InputFocusTests: XCTestCase {
    @MainActor func testClicksInsideTextFieldsPreserveEditingAndOutsideClicksDismiss() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        let address = NSTextField(frame: NSRect(x: 20, y: 220, width: 200, height: 24))
        let rate = NSTextField(frame: NSRect(x: 240, y: 220, width: 60, height: 24))
        let popup = NSPopUpButton(frame: NSRect(x: 20, y: 160, width: 200, height: 26))
        let touch = TouchView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
        let anchor = NSView(frame: .zero)
        for view in [address, rate, popup, touch, anchor] { content.addSubview(view) }
        window.orderFront(nil)
        var dismissals = 0
        let coordinator = InputFocusDismissal.Coordinator { dismissals += 1 }
        coordinator.view = anchor

        func click(_ point: NSPoint) throws -> NSEvent {
            let event = try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: content.convert(point, to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            XCTAssertTrue(event.window === window)
            return event
        }
        func beginEditing() throws -> NSTextView {
            XCTAssertTrue(window.makeFirstResponder(address))
            let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
            XCTAssertTrue(editor.isFieldEditor)
            return editor
        }

        let editor = try beginEditing()
        for field in [address, rate] {
            coordinator.dismissFocus(
                for: try click(NSPoint(x: field.frame.midX, y: field.frame.midY)))
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(dismissals, 0)
        }

        for point in [
            NSPoint(x: 350, y: 280),
            NSPoint(x: popup.frame.midX, y: popup.frame.midY),
            NSPoint(x: touch.frame.midX, y: touch.frame.midY),
        ] {
            let editor = try beginEditing()
            let before = dismissals
            coordinator.dismissFocus(for: try click(point))
            XCTAssertFalse(window.firstResponder === editor)
            XCTAssertEqual(dismissals, before + 1)
        }
    }

    @MainActor func testClicksInOtherWindowsDoNotDismissEditing() throws {
        let first = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let second = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        second.isReleasedWhenClosed = false
        defer {
            first.close()
            second.close()
        }
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        let anchor = NSView(frame: .zero)
        first.contentView?.addSubview(field)
        first.contentView?.addSubview(anchor)
        first.orderFront(nil)
        second.orderFront(nil)
        XCTAssertTrue(first.makeFirstResponder(field))
        let editor = try XCTUnwrap(first.firstResponder as? NSTextView)
        let coordinator = InputFocusDismissal.Coordinator { XCTFail("Must stay within its window") }
        coordinator.view = anchor
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 250, y: 150), modifierFlags: [],
                timestamp: 0, windowNumber: second.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertTrue(event.window === second)
        coordinator.dismissFocus(for: event)
        XCTAssertTrue(first.firstResponder === editor)
    }
}
