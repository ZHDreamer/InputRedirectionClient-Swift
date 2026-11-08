import Foundation
import GameController
import InputCore

struct ControllerProfile {
    var mappingOverrides: [InputTarget: InputSource] = [:]
    var invertY = false
}

@MainActor final class ControllerProfileStore {
    private let preferences: UserDefaults

    init(preferences: UserDefaults) { self.preferences = preferences }

    static func key(for controller: GCController?) -> String {
        controller?.productCategory ?? "unassigned"
    }

    func load(for key: String) -> ControllerProfile {
        let profiles = preferences.dictionary(forKey: "controllerProfiles") ?? [:]
        let saved = profiles[key] as? [String: Any] ?? [:]
        let mappings = saved["mappingOverrides"] as? [String: String] ?? [:]
        var profile = ControllerProfile()
        for (targetName, sourceName) in mappings {
            guard let target = InputTarget(rawValue: targetName),
                let source = InputSource(rawValue: sourceName), target.sources.contains(source)
            else { continue }
            profile.mappingOverrides[target] = source
        }
        profile.invertY = saved["invertY"] as? Bool ?? false
        return profile
    }

    func save(_ profile: ControllerProfile, for key: String) {
        var profiles = preferences.dictionary(forKey: "controllerProfiles") ?? [:]
        profiles[key] = [
            "mappingOverrides": Dictionary(
                uniqueKeysWithValues: profile.mappingOverrides.map {
                    ($0.key.rawValue, $0.value.rawValue)
                }),
            "invertY": profile.invertY,
        ]
        preferences.set(profiles, forKey: "controllerProfiles")
    }
}
