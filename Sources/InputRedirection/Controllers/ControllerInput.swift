import GameController
import InputCore

@MainActor final class ControllerInput {
    var onButtonPress: ((InputSource, Double) -> Void)?
    var onStickMove: ((InputSource, Double) -> Void)?
    var onChange: (() -> Void)?
    private var controller: GCController?
    private var stickInputs: [(InputSource, GCControllerDirectionPad)] = []
    // Use the same elements for input polling and display metadata.
    private var sourceButtons: [(InputSource, GCControllerButtonInput?)] = []
    private func readSourceButtons() -> [(InputSource, GCControllerButtonInput?)] {
        guard let g = controller?.extendedGamepad else { return [] }
        return InputSource.allCases.filter { !$0.isStick }.map { source in
            let button: GCControllerButtonInput?
            switch source {
            case .a: button = g.buttonA
            case .b: button = g.buttonB
            case .x: button = g.buttonX
            case .y: button = g.buttonY
            case .l1: button = g.leftShoulder
            case .r1: button = g.rightShoulder
            case .l2: button = g.leftTrigger
            case .r2: button = g.rightTrigger
            case .up: button = g.dpad.up
            case .down: button = g.dpad.down
            case .left: button = g.dpad.left
            case .right: button = g.dpad.right
            case .l3: button = g.leftThumbstickButton
            case .r3: button = g.rightThumbstickButton
            case .home: button = g.buttonHome
            case .capture: button = captureButton
            case .start: button = g.buttonMenu
            case .select: button = g.buttonOptions
            case .none, .leftStick, .rightStick: button = nil
            }
            return (source, button)
        }
    }
    private var captureButton: GCControllerButtonInput? {
        guard let controller else { return nil }
        // Xbox Share can be exposed on the specialized gamepad rather than the
        // generic physical profile. Use the actual element for polling and gestures.
        if let share = (controller.extendedGamepad as? GCXboxGamepad)?.buttonShare {
            return share
        }
        let profiles = [controller.extendedGamepad, controller.physicalInputProfile].compactMap {
            $0
        }
        for profile in profiles {
            if let button = profile.buttons[GCInputButtonShare] { return button }
        }
        // Drivers may expose Share/Capture under a vendor-specific name or alias.
        for profile in profiles {
            if let button = profile.buttons.first(where: { key, button in
                let aliases = ([key] + Array(button.aliases)).map { $0.lowercased() }
                return aliases.contains {
                    $0.contains("share") || $0.contains("capture") || $0.contains("screenshot")
                } || button.sfSymbolsName?.hasPrefix("camera.") == true
            })?.value {
                return button
            }
        }
        return nil
    }

    private struct ButtonMetadata: Equatable {
        var label: String
        var symbol: String?
        var available: Bool
    }
    private var buttonMetadata: [InputSource: ButtonMetadata] = [:]
    private func refreshButtonMetadata() {
        let elements = Dictionary(uniqueKeysWithValues: sourceButtons)
        let metadata = Dictionary(
            uniqueKeysWithValues: InputSource.allCases.map { source in
                let element: GCControllerElement?
                if source == .leftStick {
                    element = controller?.extendedGamepad?.leftThumbstick
                } else if source == .rightStick {
                    element = controller?.extendedGamepad?.rightThumbstick
                } else {
                    element = elements[source] ?? nil
                }
                return (
                    source,
                    ButtonMetadata(
                        label: element?.localizedName ?? source.rawValue,
                        symbol: element?.sfSymbolsName, available: source == .none || element != nil
                    )
                )
            })
        if buttonMetadata != metadata { buttonMetadata = metadata }
    }
    func sourceIsAvailable(_ source: InputSource) -> Bool {
        buttonMetadata[source]?.available ?? (source == .none)
    }
    func configure(_ controller: GCController?) {
        self.controller = controller
        for (_, stick) in stickInputs { stick.valueChangedHandler = nil }
        stickInputs.removeAll()
        for (_, button) in sourceButtons { button?.pressedChangedHandler = nil }
        releaseSystemButtons()
        sourceButtons = readSourceButtons()
        for (source, button) in sourceButtons {
            button?.pressedChangedHandler = { [weak self] _, _, isPressed in
                let time = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if isPressed { self.onButtonPress?(source, time) }
                    self.onChange?()
                }
            }
        }
        if let gamepad = controller?.extendedGamepad {
            stickInputs = [
                (.leftStick, gamepad.leftThumbstick), (.rightStick, gamepad.rightThumbstick),
            ]
            for (source, stick) in stickInputs {
                stick.valueChangedHandler = { [weak self] _, x, y in
                    // Deliberate movement for assignment only; transmitted axes remain unfiltered.
                    guard max(abs(x), abs(y)) > 0.6 else { return }
                    let time = ProcessInfo.processInfo.systemUptime
                    Task { @MainActor [weak self] in self?.onStickMove?(source, time) }
                }
            }
        }
        configureSystemButtons()
        refreshButtonMetadata()
    }
    private var systemButtonPreferences:
        [(GCControllerButtonInput, GCControllerElement.SystemGestureState)] = []
    func releaseSystemButtons() {
        for (button, preference) in systemButtonPreferences {
            button.preferredSystemGestureState = preference
        }
        systemButtonPreferences.removeAll()
    }
    private func configureSystemButtons() {
        releaseSystemButtons()
        for (source, element) in sourceButtons where source == .home || source == .capture {
            guard let button = element, button.isBoundToSystemGesture else { continue }
            systemButtonPreferences.append((button, button.preferredSystemGestureState))
            button.preferredSystemGestureState = .disabled
        }
    }
    func sourceSymbol(_ source: InputSource) -> String? {
        buttonMetadata[source]?.symbol
    }
    func sourceLabel(_ source: InputSource) -> String {
        buttonMetadata[source]?.label ?? source.rawValue
    }
    func buttonValues() -> [InputSource: Bool] {
        Dictionary(uniqueKeysWithValues: sourceButtons.map { ($0.0, $0.1?.isPressed ?? false) })
    }
}
