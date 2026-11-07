import Foundation

public enum ControllerLayout: String, CaseIterable {
    case automatic = "Automatic"
    case xbox = "Xbox"
    case nintendo = "Nintendo"
    case dualShock = "PlayStation (DualShock 4)"
    case dualSense = "PlayStation (DualSense)"
    case generic = "Generic"

    public static func detect(category: String, vendor: String) -> Self {
        let name = (category + " " + vendor).lowercased()
        if name.contains("dualsense") { return .dualSense }
        if name.contains("dualshock") || name.contains("playstation") || name.contains("wireless controller") && name.contains("sony") { return .dualShock }
        if name.contains("xbox") { return .xbox }
        if name.contains("nintendo") || name.contains("switch") || name.contains("joy-con") { return .nintendo }
        return .generic
    }

    // Source IDs are stable polling slots, retained for saved mapping compatibility.
    // Face-button slots refer to GameController properties, not physical legends.
    public func label(for source: String, symbol: String? = nil) -> String {
        if let symbol, let legend = Self.legend(for: symbol) { return legend }
        if source == "ControllerHome" {
            switch self {
            case .nintendo: return "HOME"
            case .xbox: return "Xbox"
            case .dualShock, .dualSense: return "PS"
            case .automatic, .generic: return "Home"
            }
        }
        if source == "Capture" { return self == .nintendo ? "Capture" : "Share / Capture" }
        let face: [String]
        let shoulders: [String]
        switch self {
        case .nintendo:
            face = ["A", "B", "X", "Y"]
            shoulders = ["L", "R", "ZL", "ZR", "+", "−", "Left Stick", "Right Stick"]
        case .dualShock, .dualSense:
            face = ["×", "○", "□", "△"]
            shoulders = ["L1", "R1", "L2", "R2", "Options", self == .dualSense ? "Create" : "SHARE", "L3", "R3"]
        case .xbox:
            face = ["A", "B", "X", "Y"]
            shoulders = ["LB", "RB", "LT", "RT", "Menu", "View", "LS", "RS"]
        case .automatic, .generic:
            face = ["Button A", "Button B", "Button X", "Button Y"]
            shoulders = ["Left Shoulder", "Right Shoulder", "Left Trigger", "Right Trigger", "Menu", "Options", "Left Stick", "Right Stick"]
        }
        let keys = ["South", "East", "West", "North", "L1", "R1", "L2", "R2", "Menu", "Options", "L3", "R3"]
        let names = face + shoulders
        if let index = keys.firstIndex(of: source) { return names[index] }
        return source
    }

    public static let legacyDefaults = Dictionary(uniqueKeysWithValues: zip(
        ["A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "R", "L", "X", "Y", "ZL", "ZR", "Home"],
        ["East", "South", "Options", "Menu", "→", "←", "↑", "↓", "R1", "L1", "North", "West", "L2", "R2", "None"]
    ))

    public func defaultMapping(faceLegends: [String: String] = [:]) -> [String: String] {
        var result = Self.legacyDefaults
        let positions = ["East", "South", "North", "West"]
        let targets = ["A", "B", "X", "Y"]
        let legends: [String]
        switch self {
        case .nintendo: legends = ["A", "B", "X", "Y"]
        case .dualShock, .dualSense: legends = ["○", "×", "△", "□"]
        default: legends = ["B", "A", "Y", "X"]
        }
        let slots = ["South", "East", "West", "North"]
        for index in targets.indices {
            // Resolve printed legends back to the polled element, including system remapping.
            result[targets[index]] = slots.first { slot in
                (faceLegends[slot] ?? label(for: slot)) == legends[index]
            } ?? positions[index]
        }
        return result
    }

    public static func legend(for symbol: String) -> String? {
        let legends = ["a": "A", "b": "B", "x": "X", "y": "Y", "cross": "×", "circle": "○", "square": "□", "triangle": "△", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "zl": "ZL", "zr": "ZR", "l": "L", "r": "R", "plus": "+", "minus": "−"]
        // Accept only recognized button glyphs, not arbitrary SF Symbol prefixes.
        for (prefix, label) in legends where symbol == prefix + ".circle" || symbol == prefix + ".circle.fill" || symbol == prefix + ".button.roundedtop.horizontal" || symbol == prefix + ".button.roundedbottom.horizontal" || symbol == prefix + ".button.roundedtop.horizontal.fill" || symbol == prefix + ".button.roundedbottom.horizontal.fill" { return label }
        return nil
    }
}
