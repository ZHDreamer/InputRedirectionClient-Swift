import AppKit
import Combine
import GameController
import Darwin
import InputCore

@MainActor final class Client: ObservableObject {
    @Published var address = "192.168.1.100"
    @Published var controllers: [GCController] = []
    @Published var selected = 0 { didSet { configureController() } }
    @Published var sending = false
    @Published var status = "Not sending"
    @Published var pressed: Set<InputTarget> = []
    @Published var invertY = false
    @Published private var mappingOverrides: [InputTarget: InputSource] = [:]
    var defaultMapping: [InputTarget: InputSource] {
        layout.defaultMapping()
    }
    var mapping: [InputTarget: InputSource] {
        get { defaultMapping.merging(mappingOverrides) { _, custom in custom } }
        set {
            let defaults = defaultMapping
            mappingOverrides = newValue.filter { $0.key.sources.contains($0.value) && defaults[$0.key] != $0.value }
            updatePreview()
        }
    }
    @Published private(set) var mappingTarget: InputTarget?
    private var mappingStartedAt = 0.0
    private var stickInputs: [(InputSource, GCControllerDirectionPad)] = []

    func beginMapping(_ target: InputTarget) {
        stop()
        mappingStartedAt = ProcessInfo.processInfo.systemUptime
        mappingTarget = target
    }

    func cancelMapping() { mappingTarget = nil }

    private func captureButton(_ source: InputSource, at time: Double) {
        guard let target = mappingTarget, !target.isStick, time >= mappingStartedAt else { return }
        mapping[target] = source
        cancelMapping()
        save()
    }

    private func captureStick(_ stick: InputSource, at time: Double) {
        guard let target = mappingTarget, time >= mappingStartedAt else { return }
        guard target.isStick else { return }
        mapping[target] = stick
        cancelMapping()
        save()
    }

    func restoreDefaults() {
        cancelMapping()
        mappingOverrides = [:]
        updatePreview()
        save()
    }
    @Published var pressedSources: Set<InputSource> = []
    var currentController: GCController? { controllers.indices.contains(selected) ? controllers[selected] : nil }
    var layout: ControllerLayout {
        guard let controller = currentController else { return .xbox }
        if controller.extendedGamepad is GCDualSenseGamepad || controller.extendedGamepad is GCDualShockGamepad { return .playStation }
        if controller.extendedGamepad is GCXboxGamepad { return .xbox }
        return ControllerLayout.detect(category: controller.productCategory, vendor: controller.vendorName ?? "")
    }
    // Use the same elements for input polling and display metadata.
    private var sourceButtons: [(InputSource, GCControllerButtonInput?)] = []
    private func readSourceButtons() -> [(InputSource, GCControllerButtonInput?)] {
        guard let g = currentController?.extendedGamepad else { return [] }
        return InputSource.allCases.filter { !$0.isStick }.map { source in
            let button: GCControllerButtonInput?
            switch source {
            case .a: button = g.buttonA
            case .b: button = g.buttonB
            case .x: button = g.buttonX
            case .y: button = g.buttonY
            case .lb: button = g.leftShoulder
            case .rb: button = g.rightShoulder
            case .lt: button = g.leftTrigger
            case .rt: button = g.rightTrigger
            case .up: button = g.dpad.up
            case .down: button = g.dpad.down
            case .left: button = g.dpad.left
            case .right: button = g.dpad.right
            case .leftStickButton: button = g.leftThumbstickButton
            case .rightStickButton: button = g.rightThumbstickButton
            case .xbox: button = g.buttonHome
            case .share: button = captureButton
            case .menu: button = g.buttonMenu
            case .view: button = g.buttonOptions
            case .none, .leftStick, .rightStick: button = nil
            }
            return (source, button)
        }
    }
    private var captureButton: GCControllerButtonInput? {
        guard let controller = currentController else { return nil }
        // Xbox Share can be exposed on the specialized gamepad rather than the
        // generic physical profile. Use the actual element for polling and gestures.
        if let share = (controller.extendedGamepad as? GCXboxGamepad)?.buttonShare {
            return share
        }
        let profiles = [controller.extendedGamepad, controller.physicalInputProfile].compactMap { $0 }
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
    @Published private var buttonMetadata: [InputSource: ButtonMetadata] = [:]
    private func refreshButtonMetadata() {
        let elements = Dictionary(uniqueKeysWithValues: sourceButtons)
        let metadata = Dictionary(uniqueKeysWithValues: InputSource.allCases.map { source in
            let element: GCControllerElement?
            if source == .leftStick { element = currentController?.extendedGamepad?.leftThumbstick }
            else if source == .rightStick { element = currentController?.extendedGamepad?.rightThumbstick }
            else { element = elements[source] ?? nil }
            return (source, ButtonMetadata(
                label: element?.localizedName ?? source.rawValue,
                symbol: element?.sfSymbolsName, available: source == .none || element != nil))
        })
        if buttonMetadata != metadata { buttonMetadata = metadata }
    }
    func sourceIsAvailable(_ source: InputSource) -> Bool {
        buttonMetadata[source]?.available ?? (source == .none)
    }
    private func configureController() {
        cancelMapping()
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
                    if isPressed { self.captureButton(source, at: time) }
                    if !self.sending { self.updatePreview() }
                }
            }
        }
        if let gamepad = currentController?.extendedGamepad {
            stickInputs = [(.leftStick, gamepad.leftThumbstick), (.rightStick, gamepad.rightThumbstick)]
            for (source, stick) in stickInputs {
                stick.valueChangedHandler = { [weak self] _, x, y in
                    // Deliberate movement for assignment only; transmitted axes remain unfiltered.
                    guard max(abs(x), abs(y)) > 0.6 else { return }
                    let time = ProcessInfo.processInfo.systemUptime
                    Task { @MainActor [weak self] in self?.captureStick(source, at: time) }
                }
            }
        }
        configureSystemButtons()
        refreshButtonMetadata()
        updatePreview()
    }
    private var systemButtonPreferences: [(GCControllerButtonInput, GCControllerElement.SystemGestureState)] = []
    private func releaseSystemButtons() {
        for (button, preference) in systemButtonPreferences { button.preferredSystemGestureState = preference }
        systemButtonPreferences.removeAll()
    }
    private func configureSystemButtons() {
        releaseSystemButtons()
        for (source, element) in sourceButtons where source == .xbox || source == .share {
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
    var touch: (Double, Double)?
    @Published private(set) var home = false
    enum PowerAction { case press, longPress }
    @Published private(set) var powerAction: PowerAction?
    private enum PulseButton { case home, power }
    private var releaseTasks: [PulseButton: Task<Void, Never>] = [:]

    func triggerHome() {
        guard !home else { return }
        triggerPulse(.home, press: { $0.home = true }, release: { $0.home = false })
    }

    func triggerPower(longPress: Bool) {
        triggerPulse(.power,
                     press: { $0.powerAction = longPress ? .longPress : .press },
                     release: { $0.powerAction = nil })
    }

    private func triggerPulse(_ button: PulseButton, press: (Client) -> Void,
                              release: @escaping (Client) -> Void) {
        guard sending else { return }
        releaseTasks[button]?.cancel()
        press(self)
        tick()
        guard sending else { return }
        releaseTasks[button] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) }
            catch { return }
            guard let self else { return }
            release(self)
            self.releaseTasks[button] = nil
            self.tick()
        }
    }
    private var socketFD: Int32 = -1
    @Published var sendRate = 120 {
        didSet {
            guard sendRate != oldValue else { return }
            scheduleInputTimer()
            preferences.set(sendRate, forKey: "sendRate")
            if sending { status = "Sending to \(address):4950 · \(sendRate) Hz" }
        }
    }
    private var timer: Timer?
    private var sendingActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private let preferences: UserDefaults
    private let controllerProvider: () -> [GCController]
    private let socketFactory: () throws -> Int32
    init(preferences: UserDefaults = .standard, controllerProvider: @escaping () -> [GCController] = { GCController.controllers() }, socketFactory: @escaping () throws -> Int32 = UDPSocket.make) {
        // Continue receiving controller events when another app has focus.
        GCController.shouldMonitorBackgroundEvents = true
        self.preferences = preferences
        self.controllerProvider = controllerProvider
        self.socketFactory = socketFactory
        address = preferences.string(forKey: "address") ?? "192.168.1.100"
        invertY = preferences.bool(forKey: "invertY")
        sendRate = min(250, max(50, preferences.object(forKey: "sendRate") as? Int ?? 120))
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerUserCustomizationsDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(); self?.releaseSystemButtons() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
        let saved = preferences.dictionary(forKey: "mappingOverrides") as? [String: String] ?? [:]
        for (key, value) in saved {
            guard let target = InputTarget(rawValue: key), let source = InputSource(rawValue: value),
                  target.sources.contains(source) else { continue }
            mappingOverrides[target] = source
        }
        refresh()
    }
    private func scheduleInputTimer() {
        timer?.invalidate()
        timer = nil
        guard sending else { return }
        let inputTimer = Timer(timeInterval: 1.0 / Double(sendRate), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        inputTimer.tolerance = 0
        RunLoop.main.add(inputTimer, forMode: .common)
        timer = inputTimer
    }
    func refresh() {
        controllers = controllerProvider().filter { $0.extendedGamepad != nil }
        selected = min(selected, max(0, controllers.count - 1))
    }
    func save() {
        let d = preferences
        d.set(address, forKey: "address"); d.set(Dictionary(uniqueKeysWithValues: mappingOverrides.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: "mappingOverrides")
        d.set(invertY, forKey: "invertY")
    }
    func start() {
        stop()
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = UInt16(4950).bigEndian
        let ip = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inet_pton(AF_INET, ip, &endpoint.sin_addr) == 1 else { status = "Enter a valid 3DS IPv4 address"; return }
        do { socketFD = try socketFactory() }
        catch { status = "Unable to configure UDP socket: \(error.localizedDescription)"; return }
        let result = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            stop(); status = "Network error: \(message)"; return
        }
        // Prevent App Nap from throttling the send timer while hidden or unfocused.
        sendingActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Redirect controller input to Nintendo 3DS"
        )
        address = ip; save(); sending = true; status = "Sending to \(ip):4950 · \(sendRate) Hz"
        scheduleInputTimer()
        tick()
    }
    func stop() {
        cancelMapping()
        if let sendingActivity {
            ProcessInfo.processInfo.endActivity(sendingActivity)
            self.sendingActivity = nil
        }
        for task in releaseTasks.values { task.cancel() }
        releaseTasks.removeAll()
        if powerAction != nil { powerAction = nil }
        timer?.invalidate()
        timer = nil
        if socketFD >= 0 {
            let neutral = InputFrame().encoded()
            for _ in 0..<3 { _ = neutral.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) } }
            Darwin.close(socketFD); socketFD = -1
        }
        sending = false; touch = nil; home = false; status = "Stopped"
        updatePreview()
    }
    // Idle preview uses button transition callbacks; no idle polling timer.
    private func buttonValues() -> [InputSource: Bool] {
        Dictionary(uniqueKeysWithValues: sourceButtons.map { ($0.0, $0.1?.isPressed ?? false) })
    }
    private func updatePreview(values: [InputSource: Bool]? = nil, currentMapping: [InputTarget: InputSource]? = nil) {
        let values = values ?? buttonValues()
        let currentMapping = currentMapping ?? mapping
        let sources = Set(values.filter { $0.value }.map { $0.key })
        let targets = Set(InputTarget.allCases.filter { values[currentMapping[$0] ?? .none] ?? false })
        // @Published emits even for equal values. Avoid redrawing at the send rate.
        if pressedSources != sources { pressedSources = sources }
        if pressed != targets { pressed = targets }
    }
    var isSendTimerRunning: Bool { timer?.isValid ?? false }
    func inputFrame() -> InputFrame {
        var state = InputFrame()
        let values = buttonValues()
        if let g = currentController?.extendedGamepad {
            let circle = mapping[.circlePad] == .leftStick ? g.leftThumbstick : g.rightThumbstick
            let c = mapping[.cStick] == .leftStick ? g.leftThumbstick : g.rightThumbstick
            state.leftX = Double(circle.xAxis.value)
            state.leftY = Double(circle.yAxis.value) * (invertY ? -1 : 1)
            state.rightX = Double(c.xAxis.value)
            state.rightY = Double(c.yAxis.value) * (invertY ? -1 : 1)
        }
        let currentMapping = mapping
        func active(_ target: InputTarget) -> Bool { values[currentMapping[target] ?? .none] ?? false }
        updatePreview(values: values, currentMapping: currentMapping)
        for target in InputTarget.allCases where active(target) { state.buttons |= target.buttonMask }
        state.power = active(.power) || powerAction == .press
        state.powerLong = powerAction == .longPress
        state.zl = active(.zl); state.zr = active(.zr); state.home = home || active(.home); state.touch = touch
        return state
    }
    private func tick() {
        guard sending else { return }
        let data = inputFrame().encoded()
        let sent = data.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
        if sent != data.count {
            let message = String(cString: strerror(errno))
            stop(); status = "Send failed: \(message)"
        }
    }
}
