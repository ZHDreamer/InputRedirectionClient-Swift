import Foundation

public struct InputFrame {
    public var buttons: UInt32 = 0
    public var leftX: Double = 0, leftY: Double = 0
    public var rightX: Double = 0, rightY: Double = 0
    public var zl = false, zr = false
    public var touch: (Double, Double)?
    public var home = false
    public var power = false, powerLong = false
    public init() {}

    public func encoded() -> Data {
        func bounded(_ value: Double, _ maximum: Int) -> UInt32 {
            UInt32(max(0, min(maximum, Int(value.isFinite ? value : 0))))
        }
        // Quantize once, at the wire boundary, using every representable code.
        // Keep Luma's neutral Circle Pad value (0x7ff) and CPP neutral (0x80).
        let circle =
            Self.coordinate(leftX, center: 2047, maximum: 4095)
            | (Self.coordinate(leftY, center: 2047, maximum: 4095) << 12)
        let rx = Self.normalized(rightX)
        let ry = Self.normalized(rightY)
        // CPP uses a 45-degree coordinate rotation. Clamp after rotation.
        let cX = Self.coordinate((rx + ry) / sqrt(2), center: 128, maximum: 255)
        let cY = Self.coordinate((ry - rx) / sqrt(2), center: 128, maximum: 255)
        let cpp =
            UInt32(0x81) | (UInt32(zr ? 2 : 0) << 8) | (UInt32(zl ? 4 : 0) << 8) | (cX << 16)
            | (cY << 24)
        var screen: UInt32 = 0x0200_0000
        if let (x, y) = touch {
            screen =
                0x0100_0000 | bounded(x / 320 * 4095, 4095) | (bounded(y / 240 * 4095, 4095) << 12)
        }
        let interfaceButtons: UInt32 = (home ? 1 : 0) | (power ? 2 : 0) | (powerLong ? 4 : 0)
        var data = Data()
        for word in [0xfff & ~buttons, screen, circle, cpp, interfaceButtons] {
            var little = word.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        return data
    }
    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? max(-1, min(1, value)) : 0
    }

    private static func coordinate(_ value: Double, center: Int, maximum: Int) -> UInt32 {
        let input = normalized(value)
        let span = input < 0 ? center : maximum - center
        return UInt32((Double(center) + input * Double(span)).rounded())
    }
}
