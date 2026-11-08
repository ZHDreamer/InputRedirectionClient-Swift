import GameController
import InputCore
import XCTest

@testable import InputRedirection

final class MappingEnumTests: XCTestCase {
    @MainActor func testCurrentSettingsRoundTripAndInvalidAssignments() {
        let name = "MappingEnums.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(
            [
                ControllerProfileStore.key(for: nil): [
                    "mappingOverrides": [
                        "Home": "Capture", "D-Pad Up": "A", "A": "B", "Power (Long)": "Y",
                        "B": "Unknown", "X": "Left Stick", "Circle Pad": "Right Stick",
                        "C-Stick": "Left Stick",
                    ]
                ]
            ], forKey: "controllerProfiles")
        let client = Client(preferences: preferences, controllerProvider: { [] })
        defer { client.stop() }
        XCTAssertEqual(client.mapping[.home], .capture)
        XCTAssertEqual(client.mapping[.up], .a)
        XCTAssertEqual(client.mapping[.a], .b)
        XCTAssertEqual(client.mapping[.b], .a)
        XCTAssertEqual(client.mapping[.x], .y)
        XCTAssertEqual(client.mapping[.circlePad], .rightStick)
        XCTAssertEqual(client.mapping[.cStick], .leftStick)
        client.mapping[.a] = .leftStick
        client.mapping[.cStick] = .a
        XCTAssertEqual(client.mapping[.a], .b)
        XCTAssertEqual(client.mapping[.cStick], .rightStick)
        client.save()
        let profiles = preferences.dictionary(forKey: "controllerProfiles")
        let profile = profiles?[ControllerProfileStore.key(for: nil)] as? [String: Any]
        let saved = profile?["mappingOverrides"] as? [String: String]
        XCTAssertEqual(saved?["Home"], "Capture")
        XCTAssertEqual(saved?["D-Pad Up"], "A")
        XCTAssertNil(saved?["Power (Long)"])
        let restored = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(restored.mapping, client.mapping)
        client.restoreDefaults()
        let reset = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(reset.mapping, ControllerLayout.xbox.defaultMapping())
    }

    @MainActor func testObsoleteSettingsAreIgnored() {
        let name = "ObsoleteMapping.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(["A": "X"], forKey: "mapping")
        preferences.set("Right Stick", forKey: "circlePadStick")
        preferences.set("Left Stick", forKey: "cStick")
        let client = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(client.mapping, ControllerLayout.xbox.defaultMapping())
        preferences.set(["Home": "Share", "A": "South", "Up": "A"], forKey: "mappingOverrides")
        let oldNames = Client(preferences: preferences, controllerProvider: { [] })
        XCTAssertEqual(oldNames.mapping, ControllerLayout.xbox.defaultMapping())
    }

    @MainActor func testTargetOrderDoesNotChangeProtocolBits() {
        let name = "MappingBits.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        let controller = GCController.withExtendedGamepad()
        let client = Client(preferences: preferences, controllerProvider: { [controller] })
        defer {
            client.stop()
            preferences.removePersistentDomain(forName: name)
        }
        controller.extendedGamepad!.buttonA.setValue(1)
        let wireOrder: [InputTarget] = [
            .a, .b, .select, .start, .right, .left, .up, .down, .r, .l, .x, .y,
        ]
        for (bit, target) in wireOrder.enumerated() {
            var mapping = client.mapping
            for button in InputTarget.allCases where !button.isStick {
                mapping[button] = InputSource.none
            }
            mapping[target] = .a
            client.mapping = mapping
            let packet = client.inputFrame().encoded()
            let actual = packet.prefix(4).enumerated().reduce(UInt32(0)) {
                $0 | UInt32($1.element) << ($1.offset * 8)
            }
            XCTAssertEqual(actual, 0xfff & ~(1 << bit), "Incorrect HID bit for \(target.rawValue)")
        }
    }
}
