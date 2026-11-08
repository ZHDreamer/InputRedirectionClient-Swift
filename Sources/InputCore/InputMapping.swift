import Foundation

public enum InputTarget: String, CaseIterable {
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
    case l = "L"
    case r = "R"
    case zl = "ZL"
    case zr = "ZR"
    case up = "D-Pad Up"
    case down = "D-Pad Down"
    case left = "D-Pad Left"
    case right = "D-Pad Right"
    case circlePad = "Circle Pad"
    case cStick = "C-Stick"
    case start = "Start"
    case select = "Select"
    case home = "Home"
    case power = "Power"

    case circlePadUp = "Circle Pad Up"
    case circlePadDown = "Circle Pad Down"
    case circlePadLeft = "Circle Pad Left"
    case circlePadRight = "Circle Pad Right"
    case cStickUp = "C-Stick Up"
    case cStickDown = "C-Stick Down"
    case cStickLeft = "C-Stick Left"
    case cStickRight = "C-Stick Right"

    public var defaultSymbol: String? {
        switch self {
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .l: return "l.rectangle.roundedbottom"
        case .r: return "r.rectangle.roundedbottom"
        case .zl: return "zl.rectangle.roundedtop"
        case .zr: return "zr.rectangle.roundedtop"
        case .up: return "dpad.up.filled"
        case .down: return "dpad.down.filled"
        case .left: return "dpad.left.filled"
        case .right: return "dpad.right.filled"
        case .circlePad: return "l.joystick"
        case .cStick: return "r.joystick"
        case .home: return "house.circle"
        case .power: return "power"
        case .circlePadUp: return "l.joystick.tilt.up.fill"
        case .circlePadDown: return "l.joystick.tilt.down.fill"
        case .circlePadLeft: return "l.joystick.tilt.left.fill"
        case .circlePadRight: return "l.joystick.tilt.right.fill"
        case .cStickUp: return "r.joystick.tilt.up.fill"
        case .cStickDown: return "r.joystick.tilt.down.fill"
        case .cStickLeft: return "r.joystick.tilt.left.fill"
        case .cStickRight: return "r.joystick.tilt.right.fill"
        case .start, .select: return nil
        }
    }

    public var isStick: Bool { self == .circlePad || self == .cStick }
    public var sources: [InputSource] {
        switch self {
        // Direction cases describe the output preview; sticks are mapped as a whole.
        case .circlePadUp, .circlePadDown, .circlePadLeft, .circlePadRight,
            .cStickUp, .cStickDown, .cStickLeft, .cStickRight:
            return []
        default:
            return InputSource.allCases.filter { $0 == .none || $0.isStick == isStick }
        }
    }
    public var buttonMask: UInt32 {
        switch self {
        case .a: return 1 << 0
        case .b: return 1 << 1
        case .select: return 1 << 2
        case .start: return 1 << 3
        case .right: return 1 << 4
        case .left: return 1 << 5
        case .up: return 1 << 6
        case .down: return 1 << 7
        case .r: return 1 << 8
        case .l: return 1 << 9
        case .x: return 1 << 10
        case .y: return 1 << 11
        default: return 0
        }
    }
}

public enum InputSource: String, CaseIterable {
    case none = "None"
    case a = "A"
    case b = "B"
    case x = "X"
    case y = "Y"
    case l1 = "L"
    case r1 = "R"
    case l2 = "ZL"
    case r2 = "ZR"
    case dpad = "D-Pad"
    case up = "D-Pad Up"
    case down = "D-Pad Down"
    case left = "D-Pad Left"
    case right = "D-Pad Right"
    case leftStick = "Left Stick"
    case rightStick = "Right Stick"
    case l3 = "LS"
    case r3 = "RS"
    case start = "Start"
    case select = "Select"
    case home = "Home"
    case capture = "Capture"
    case touchpad = "Touchpad"
    case leftStickUp = "Left Stick Up"
    case leftStickDown = "Left Stick Down"
    case leftStickLeft = "Left Stick Left"
    case leftStickRight = "Left Stick Right"
    case rightStickUp = "Right Stick Up"
    case rightStickDown = "Right Stick Down"
    case rightStickLeft = "Right Stick Left"
    case rightStickRight = "Right Stick Right"

    public var isStick: Bool { self == .dpad || self == .leftStick || self == .rightStick }
    public var stickSource: InputSource? {
        switch self {
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight: return .leftStick
        case .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight: return .rightStick
        default: return nil
        }
    }

    public var defaultSymbol: String? {
        switch self {
        case .none: return "nosign"
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .l1: return "l.rectangle.roundedbottom"
        case .r1: return "r.rectangle.roundedbottom"
        case .l2: return "zl.rectangle.roundedtop"
        case .r2: return "zr.rectangle.roundedtop"
        case .dpad: return "dpad"
        case .up: return "dpad.up.filled"
        case .down: return "dpad.down.filled"
        case .left: return "dpad.left.filled"
        case .right: return "dpad.right.filled"
        case .leftStick: return "l.joystick"
        case .rightStick: return "r.joystick"
        case .l3: return "l.joystick.press.down"
        case .r3: return "r.joystick.press.down"
        case .leftStickUp: return "l.joystick.tilt.up"
        case .rightStickUp: return "r.joystick.tilt.up"
        case .leftStickDown: return "l.joystick.tilt.down"
        case .rightStickDown: return "r.joystick.tilt.down"
        case .leftStickLeft: return "l.joystick.tilt.left"
        case .rightStickLeft: return "r.joystick.tilt.left"
        case .leftStickRight: return "l.joystick.tilt.right"
        case .rightStickRight: return "r.joystick.tilt.right"
        case .start: return "plus.circle"
        case .select: return "minus.circle"
        case .home: return "house.circle"
        case .capture: return "circle.square"
        case .touchpad: return "plus.rectangle"
        }
    }

}
