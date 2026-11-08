import GameController
import InputCore

@MainActor final class ControllerInput {
    var onButtonPress: ((InputSource, Double) -> Void)?
    var onStickMove: ((InputSource, Double) -> Void)?
    var onChange: (() -> Void)?
    private var controller: GCController?
    private var pressedStickDirections: [InputSource: InputSource] = [:]
    private var stickInputs: [(InputSource, GCControllerDirectionPad)] = []
    // Use the same elements for input polling and display metadata.
    private var sourceButtons: [(InputSource, GCControllerButtonInput?)] = []
    private func readSourceButtons() -> [(InputSource, GCControllerButtonInput?)] {
        guard let profile = controller?.physicalInputProfile else { return [] }
        let dpad = profile.dpads[GCInputDirectionPad]
        return InputSource.allCases.filter { !$0.isStick }.map { source in
            let button: GCControllerButtonInput?
            switch source {
            case .a: button = profile.buttons[GCInputButtonA]
            case .b: button = profile.buttons[GCInputButtonB]
            case .x: button = profile.buttons[GCInputButtonX]
            case .y: button = profile.buttons[GCInputButtonY]
            case .l1: button = profile.buttons[GCInputLeftShoulder]
            case .r1: button = profile.buttons[GCInputRightShoulder]
            case .l2: button = profile.buttons[GCInputLeftTrigger]
            case .r2: button = profile.buttons[GCInputRightTrigger]
            case .up: button = dpad?.up
            case .down: button = dpad?.down
            case .left: button = dpad?.left
            case .right: button = dpad?.right
            case .leftStickUp: button = stick(.leftStick)?.up
            case .leftStickDown: button = stick(.leftStick)?.down
            case .leftStickLeft: button = stick(.leftStick)?.left
            case .leftStickRight: button = stick(.leftStick)?.right
            case .rightStickUp: button = stick(.rightStick)?.up
            case .rightStickDown: button = stick(.rightStick)?.down
            case .rightStickLeft: button = stick(.rightStick)?.left
            case .rightStickRight: button = stick(.rightStick)?.right
            case .l3: button = profile.buttons[GCInputLeftThumbstickButton]
            case .r3: button = profile.buttons[GCInputRightThumbstickButton]
            case .home: button = profile.buttons[GCInputButtonHome]
            case .capture: button = captureButton
            case .start: button = profile.buttons[GCInputButtonMenu]
            case .select: button = profile.buttons[GCInputButtonOptions]
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
                    element = stick(.leftStick)
                } else if source == .rightStick {
                    element = stick(.rightStick)
                } else {
                    element = elements[source] ?? nil
                }
                return (
                    source,
                    ButtonMetadata(
                        label: element?.localizedName ?? source.rawValue,
                        symbol: ControllerSymbolResolver.symbol(
                            for: element, productCategory: controller?.productCategory ?? ""),
                        available: source == .none || element != nil
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
        for (source, button) in sourceButtons where source.stickSource == nil {
            button?.pressedChangedHandler = { [weak self] _, _, isPressed in
                let time = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if isPressed { self.onButtonPress?(source, time) }
                    self.onChange?()
                }
            }
        }
        stickInputs = InputSource.allCases.filter(\.isStick).compactMap { source in
            stick(source).map { (source, $0) }
        }
        pressedStickDirections.removeAll()
        for (source, stick) in stickInputs {
            pressedStickDirections[source] = Self.pressedDirection(for: source, stick: stick)
            stick.valueChangedHandler = { [weak self] pad, x, y in
                let direction = Self.pressedDirection(for: source, stick: pad)
                let time = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.pressedStickDirections[source] != direction {
                        self.pressedStickDirections[source] = direction
                        if let direction { self.onButtonPress?(direction, time) }
                        self.onChange?()
                    }
                    // Deliberate movement for full-stick assignment only; axes remain unfiltered.
                    if max(abs(x), abs(y)) > 0.6 { self.onStickMove?(source, time) }
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
    func stick(_ source: InputSource) -> GCControllerDirectionPad? {
        guard let profile = controller?.physicalInputProfile else { return nil }
        switch source {
        case .leftStick: return profile.dpads[GCInputLeftThumbstick]
        case .rightStick: return profile.dpads[GCInputRightThumbstick]
        default: return nil
        }
    }

    // Four 90-degree sectors. Exact diagonals choose the horizontal direction.
    // Keep Apple's button activation threshold; analog packet values are never filtered here.
    nonisolated private static func pressedDirection(
        for source: InputSource, stick: GCControllerDirectionPad
    ) -> InputSource? {
        let x = stick.xAxis.value
        let y = stick.yAxis.value
        guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return nil }
        if abs(x) >= abs(y) {
            if x > 0, stick.right.isPressed {
                return source == .leftStick ? .leftStickRight : .rightStickRight
            }
            if x < 0, stick.left.isPressed {
                return source == .leftStick ? .leftStickLeft : .rightStickLeft
            }
        } else {
            if y > 0, stick.up.isPressed {
                return source == .leftStick ? .leftStickUp : .rightStickUp
            }
            if y < 0, stick.down.isPressed {
                return source == .leftStick ? .leftStickDown : .rightStickDown
            }
        }
        return nil
    }

    func buttonValues() -> [InputSource: Bool] {
        let directions = Set(
            stickInputs.compactMap { Self.pressedDirection(for: $0.0, stick: $0.1) })
        return Dictionary(
            uniqueKeysWithValues: sourceButtons.map { source, button in
                (
                    source,
                    source.stickSource == nil
                        ? button?.isPressed ?? false : directions.contains(source)
                )
            })
    }
}
