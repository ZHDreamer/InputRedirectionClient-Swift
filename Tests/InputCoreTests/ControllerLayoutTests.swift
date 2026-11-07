import XCTest

@testable import InputCore

final class ControllerLayoutTests: XCTestCase {
    func testBrandDefaults() {
        let targets: [InputTarget] = [.a, .b, .x, .y]
        XCTAssertEqual(
            targets.map { ControllerLayout.nintendo.defaultMapping()[$0]! },
            [InputSource.a, InputSource.b, InputSource.x, InputSource.y])
        for family in [ControllerLayout.xbox, .playStation] {
            XCTAssertEqual(
                targets.map { family.defaultMapping()[$0]! },
                [InputSource.b, InputSource.a, InputSource.y, InputSource.x])
            XCTAssertEqual(family.defaultMapping()[.start], InputSource.start)
            XCTAssertEqual(family.defaultMapping()[.select], InputSource.select)
        }
    }

    func testDetectionAndXboxFallback() {
        XCTAssertEqual(
            ControllerLayout.detect(category: "Switch Pro Controller", vendor: "Pro Controller"),
            .nintendo)
        XCTAssertEqual(
            ControllerLayout.detect(category: "DualSense", vendor: "Wireless Controller"),
            .playStation)
        XCTAssertEqual(
            ControllerLayout.detect(category: "DualShock 4", vendor: "Sony"), .playStation)
        XCTAssertEqual(ControllerLayout.detect(category: "Xbox One", vendor: "Microsoft"), .xbox)
        let unknown = ControllerLayout.detect(category: "Generic", vendor: "Third Party")
        XCTAssertEqual(unknown, .xbox)
        XCTAssertEqual(unknown.defaultMapping(), ControllerLayout.xbox.defaultMapping())
    }
}
