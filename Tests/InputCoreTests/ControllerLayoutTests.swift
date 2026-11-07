import XCTest
@testable import InputCore

final class ControllerLayoutTests: XCTestCase {
    func testDistinctControllerLegends() {
        let keys = ["South", "East", "West", "North", "L1", "R1", "L2", "R2", "Menu", "Options"]
        XCTAssertEqual(keys.map { ControllerLayout.xbox.label(for: $0) }, ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Menu", "View"])
        XCTAssertEqual(keys.map { ControllerLayout.nintendo.label(for: $0) }, ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "+", "−"])
        XCTAssertEqual(keys.map { ControllerLayout.dualShock.label(for: $0) }, ["×", "○", "□", "△", "L1", "R1", "L2", "R2", "Options", "SHARE"])
        XCTAssertEqual(ControllerLayout.dualSense.label(for: "Options"), "Create")
    }

    func testPositionalDefaultsAcrossControllerFamilies() {
        let targets = ["A", "B", "X", "Y"]
        for layout in [ControllerLayout.xbox, .nintendo, .dualShock, .dualSense] {
            let mapping = layout.defaultMapping()
            let expected: [String]
            switch layout {
            case .nintendo: expected = ["A", "B", "X", "Y"]
            case .dualShock, .dualSense: expected = ["○", "×", "△", "□"]
            default: expected = ["B", "A", "Y", "X"]
            }
            XCTAssertEqual(targets.map { layout.label(for: mapping[$0]!) }, expected)
            XCTAssertEqual(mapping["Start"], "Menu")
            XCTAssertEqual(mapping["Select"], "Options")
        }
    }

    func testNintendoDriverUsingPositionalSlots() {
        let legends = ["South": "B", "East": "A", "West": "Y", "North": "X"]
        let mapping = ControllerLayout.nintendo.defaultMapping(faceLegends: legends)
        XCTAssertEqual(["A", "B", "X", "Y"].map { mapping[$0]! }, ["East", "South", "North", "West"])
    }

    func testSystemButtonLegends() {
        XCTAssertEqual(ControllerLayout.nintendo.label(for: "ControllerHome"), "HOME")
        XCTAssertEqual(ControllerLayout.nintendo.label(for: "Capture"), "Capture")
        XCTAssertEqual(ControllerLayout.xbox.label(for: "ControllerHome"), "Xbox")
        XCTAssertEqual(ControllerLayout.dualShock.label(for: "ControllerHome"), "PS")
        XCTAssertEqual(ControllerLayout.dualSense.label(for: "ControllerHome"), "PS")
    }

    func testDriverMetadataOverridesAssumedLayout() {
        // A physical button may differ from its logical slot after system remapping.
        XCTAssertEqual(ControllerLayout.xbox.label(for: "South", symbol: "b.circle"), "B")
        XCTAssertEqual(ControllerLayout.nintendo.label(for: "East", symbol: "a.circle.fill"), "A")
        XCTAssertEqual(ControllerLayout.dualShock.label(for: "South", symbol: "cross.circle"), "×")
        XCTAssertEqual(ControllerLayout.dualSense.label(for: "North", symbol: "triangle.circle.fill"), "△")
        XCTAssertEqual(ControllerLayout.xbox.label(for: "L1", symbol: "lb.button.roundedbottom.horizontal"), "LB")
        XCTAssertNil(ControllerLayout.legend(for: "arrow.triangle.2.circlepath"))
    }

    func testDetectionAndUnknownFallback() {
        XCTAssertEqual(ControllerLayout.detect(category: "Switch Pro Controller", vendor: "Pro Controller"), .nintendo)
        XCTAssertEqual(ControllerLayout.detect(category: "DualSense", vendor: "Wireless Controller"), .dualSense)
        XCTAssertEqual(ControllerLayout.detect(category: "DualShock 4", vendor: "Sony"), .dualShock)
        XCTAssertEqual(ControllerLayout.detect(category: "Xbox One", vendor: "Microsoft"), .xbox)
        XCTAssertEqual(ControllerLayout.detect(category: "Generic", vendor: "Third Party"), .generic)
        XCTAssertEqual(ControllerLayout.generic.label(for: "South"), "Button A")
    }
}
