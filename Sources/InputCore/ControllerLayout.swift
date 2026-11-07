import Foundation

public enum ControllerLayout {
    case xbox, nintendo, playStation

    public static func detect(category: String, vendor: String) -> Self {
        let name = (category + " " + vendor).lowercased()
        if name.contains("dualsense") || name.contains("dualshock") || name.contains("playstation")
            || name.contains("wireless controller") && name.contains("sony") { return .playStation }
        if name.contains("xbox") { return .xbox }
        if name.contains("nintendo") || name.contains("switch") || name.contains("joy-con") { return .nintendo }
        return .xbox
    }

    public func defaultMapping() -> [InputTarget: InputSource] {
        var result: [InputTarget: InputSource] = [
            .a: .b, .b: .a,
            .x: .y, .y: .x,
            .l: .lb, .r: .rb,
            .zl: .lt, .zr: .rt,
            .up: .up, .down: .down,
            .left: .left, .right: .right,
            .circlePad: .leftStick,
            .cStick: .rightStick,
            .start: .menu, .select: .view,
            .home: .none, .power: .none]
        if self == .nintendo {
            result[.a] = .a; result[.b] = .b
            result[.x] = .x; result[.y] = .y
        }
        return result
    }
}
