import XCTest

@testable import InputCore

final class InputFrameTests: XCTestCase {
    func words(_ frame: InputFrame) -> [UInt32] {
        let bytes = Array(frame.encoded())
        return stride(from: 0, to: 20, by: 4).map { i in
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[i + $1]) << ($1 * 8) }
        }
    }
    func testNeutralWireBytes() {
        XCTAssertEqual(words(InputFrame()), [0xfff, 0x0200_0000, 0x7ff7ff, 0x8080_0081, 0])
    }
    func testButtonsAndTouch() {
        var frame = InputFrame()
        frame.buttons = 1 | (1 << 11)
        frame.zl = true
        frame.zr = true
        frame.home = true
        frame.touch = (320, 240)
        XCTAssertEqual(words(frame), [0x7fe, 0x01ff_ffff, 0x7ff7ff, 0x8080_0681, 1])
    }
    func testPowerActionsAndRelease() {
        var frame = InputFrame()
        frame.power = true
        XCTAssertEqual(words(frame)[4], 2)
        frame.power = false
        frame.powerLong = true
        XCTAssertEqual(words(frame)[4], 4)
        frame.home = true
        frame.power = true
        XCTAssertEqual(words(frame)[4], 7)
        frame.home = false
        frame.power = false
        frame.powerLong = false
        XCTAssertEqual(words(frame)[4], 0)
        XCTAssertEqual(frame.encoded().count, 20)
    }

    func testStickRangeAndRotation() {
        var frame = InputFrame()
        frame.leftX = 1
        frame.leftY = -1
        frame.rightX = 1
        frame.rightY = 1
        XCTAssertEqual(words(frame)[2], UInt32(4095))
        XCTAssertEqual(words(frame)[3], 0x80ff_0081)
        frame.rightX = -1
        frame.rightY = -1
        XCTAssertEqual(words(frame)[3], 0x8000_0081)
    }
    func testSmallInputsAreNotDiscarded() {
        var frame = InputFrame()
        frame.leftX = 0.001
        frame.leftY = -0.001
        let circle = words(frame)[2]
        XCTAssertEqual(circle & 0xfff, 2049)
        XCTAssertEqual((circle >> 12) & 0xfff, 2045)
        frame.rightX = 0.02
        frame.rightY = 0
        let cpp = words(frame)[3]
        XCTAssertEqual((cpp >> 16) & 0xff, 130)
        XCTAssertEqual(cpp >> 24, 126)
    }

    func testEveryCirclePadCodeIsReachable() {
        for code in 0...4095 {
            let input = Double(code - 2047) / Double(code < 2047 ? 2047 : 2048)
            var frame = InputFrame()
            frame.leftX = input
            frame.leftY = input
            XCTAssertEqual(words(frame)[2], UInt32(code | (code << 12)))
        }
    }

    func testEveryCPPCodeIsReachable() {
        for code in 0...255 {
            let input = Double(code - 128) / Double(code < 128 ? 128 : 127)
            var frame = InputFrame()
            // Inverse rotation puts the requested CPP value on X, leaving Y neutral.
            frame.rightX = input / sqrt(2)
            frame.rightY = input / sqrt(2)
            XCTAssertEqual(words(frame)[3], UInt32(0x8000_0081) | UInt32(code << 16))
        }
    }

    func testAxisBoundsAndInvalidValues() {
        var frame = InputFrame()
        frame.leftX = -2
        frame.leftY = 2
        XCTAssertEqual(words(frame)[2], 0xfff000)
        frame.leftX = .nan
        frame.leftY = .infinity
        frame.rightX = .nan
        frame.rightY = -.infinity
        XCTAssertEqual(words(frame)[2], 0x7ff7ff)
        XCTAssertEqual(words(frame)[3], 0x8080_0081)
    }
}
