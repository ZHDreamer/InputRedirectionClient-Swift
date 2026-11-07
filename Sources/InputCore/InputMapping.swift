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
    case home = "HOME"
    case power = "Power"

    public var isStick: Bool { self == .circlePad || self == .cStick }
    public var sources: [InputSource] { InputSource.allCases.filter { $0.isStick == isStick } }
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
    case lb = "LB"
    case rb = "RB"
    case lt = "LT"
    case rt = "RT"
    case up = "D-Pad Up"
    case down = "D-Pad Down"
    case left = "D-Pad Left"
    case right = "D-Pad Right"
    case leftStick = "Left Stick"
    case rightStick = "Right Stick"
    case leftStickButton = "LS"
    case rightStickButton = "RS"
    case menu = "Menu"
    case view = "View"
    case xbox = "Xbox"
    case share = "Share"

    public var isStick: Bool { self == .leftStick || self == .rightStick }
}
