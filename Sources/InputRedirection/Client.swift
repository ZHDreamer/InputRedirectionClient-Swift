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
    @Published var pressed: Set<String> = []
    @Published var invertY = false
    @Published private var mappingOverrides: [String: String] = [:]
    var defaultMapping: [String: String] {
        let legends = Dictionary(uniqueKeysWithValues: ["South", "East", "West", "North"].map { ($0, sourceLabel($0)) })
        return layout.defaultMapping(faceLegends: legends)
    }
    var mapping: [String: String] {
        get { defaultMapping.merging(mappingOverrides) { _, custom in custom } }
        set {
            let defaults = defaultMapping
            mappingOverrides = newValue.filter { Self.targets.contains($0.key) && defaults[$0.key] != $0.value }
            updatePreview()
        }
    }
    func restoreDefaults() {
        mappingOverrides = [:]
        updatePreview()
        save()
    }
    @Published var layoutChoice = ControllerLayout.automatic.rawValue {
        didSet { refreshButtonMetadata(); updatePreview() }
    }
    @Published var pressedSources: Set<String> = []
    var currentController: GCController? { controllers.indices.contains(selected) ? controllers[selected] : nil }
    var layout: ControllerLayout {
        let choice = ControllerLayout(rawValue: layoutChoice) ?? .automatic
        guard choice == .automatic else { return choice }
        guard let controller = currentController else { return .generic }
        if controller.extendedGamepad is GCDualSenseGamepad { return .dualSense }
        if controller.extendedGamepad is GCDualShockGamepad { return .dualShock }
        if controller.extendedGamepad is GCXboxGamepad { return .xbox }
        return ControllerLayout.detect(category: controller.productCategory, vendor: controller.vendorName ?? "")
    }
    // Use the same elements for input polling and display metadata.
    private var sourceButtons: [(String, GCControllerButtonInput?)] = []
    private func readSourceButtons() -> [(String, GCControllerButtonInput?)] {
        guard let g = currentController?.extendedGamepad else { return [] }
        return [
            ("ControllerHome", g.buttonHome), ("Capture", captureButton),
            ("South", g.buttonA), ("East", g.buttonB), ("West", g.buttonX), ("North", g.buttonY),
            ("L1", g.leftShoulder), ("R1", g.rightShoulder), ("L2", g.leftTrigger), ("R2", g.rightTrigger),
            ("Menu", g.buttonMenu), ("Options", g.buttonOptions), ("L3", g.leftThumbstickButton), ("R3", g.rightThumbstickButton),
            ("↑", g.dpad.up), ("↓", g.dpad.down), ("←", g.dpad.left), ("→", g.dpad.right)]
    }
    private var captureButton: GCControllerButtonInput? {
        guard let profile = currentController?.physicalInputProfile else { return nil }
        if let button = profile.buttons[GCInputButtonShare] { return button }
        // Some Nintendo drivers expose Capture as a vendor-specific element.
        return profile.buttons.first { key, button in
            let aliases = ([key] + Array(button.aliases)).map { $0.lowercased() }
            return aliases.contains { $0.contains("capture") || $0.contains("screenshot") }
                || button.sfSymbolsName?.hasPrefix("camera.") == true
        }?.value
    }
    private struct ButtonMetadata: Equatable {
        var label: String
        var symbol: String?
        var available: Bool
    }
    @Published private var buttonMetadata: [String: ButtonMetadata] = [:]
    private func refreshButtonMetadata() {
        let currentLayout = layout
        let automatic = layoutChoice == ControllerLayout.automatic.rawValue
        let elements = Dictionary(uniqueKeysWithValues: sourceButtons)
        let metadata = Dictionary(uniqueKeysWithValues: Self.sources.map { source in
            let button = elements[source] ?? nil
            let symbol = automatic ? button?.sfSymbolsName : nil
            return (source, ButtonMetadata(label: currentLayout.label(for: source, symbol: symbol),
                symbol: symbol, available: source == "None" || button != nil))
        })
        if buttonMetadata != metadata { buttonMetadata = metadata }
    }
    func sourceIsAvailable(_ source: String) -> Bool {
        buttonMetadata[source]?.available ?? (source == "None")
    }
    private func configureController() {
        for (_, button) in sourceButtons { button?.pressedChangedHandler = nil }
        releaseSystemButtons()
        sourceButtons = readSourceButtons()
        for (_, button) in sourceButtons {
            button?.pressedChangedHandler = { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.sending else { return }
                    self.updatePreview()
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
        for (source, element) in sourceButtons where source == "ControllerHome" || source == "Capture" {
            guard let button = element, button.isBoundToSystemGesture else { continue }
            systemButtonPreferences.append((button, button.preferredSystemGestureState))
            button.preferredSystemGestureState = .disabled
        }
    }
    func sourceSymbol(_ source: String) -> String? {
        buttonMetadata[source]?.symbol
    }
    func sourceLabel(_ source: String) -> String {
        buttonMetadata[source]?.label ?? layout.label(for: source)
    }
    var touch: (Double, Double)?
    var home = false
    enum PowerAction { case press, longPress }
    @Published private(set) var powerAction: PowerAction?
    private var powerReleaseTask: Task<Void, Never>?

    func triggerPower(longPress: Bool) {
        guard sending else { return }
        powerReleaseTask?.cancel()
        powerAction = longPress ? .longPress : .press
        tick()
        powerReleaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) }
            catch { return }
            self?.powerAction = nil
            self?.powerReleaseTask = nil
            self?.tick()
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
    private var observers: [NSObjectProtocol] = []
    static let targets = ["A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "R", "L", "X", "Y", "ZL", "ZR", "Home", "Power"]
    static let sources = ["None", "South", "East", "West", "North", "L1", "R1", "L2", "R2", "Menu", "Options", "L3", "R3", "ControllerHome", "Capture", "↑", "↓", "←", "→"]


    private let preferences: UserDefaults
    private let controllerProvider: () -> [GCController]
    private let socketFactory: () throws -> Int32
    init(preferences: UserDefaults = .standard, controllerProvider: @escaping () -> [GCController] = { GCController.controllers() }, socketFactory: @escaping () throws -> Int32 = UDPSocket.make) {
        self.preferences = preferences
        self.controllerProvider = controllerProvider
        self.socketFactory = socketFactory
        address = preferences.string(forKey: "address") ?? "192.168.1.100"
        invertY = preferences.bool(forKey: "invertY")
        mappingOverrides = preferences.dictionary(forKey: "mappingOverrides") as? [String: String] ?? [:]
        layoutChoice = preferences.string(forKey: "layoutChoice") ?? ControllerLayout.automatic.rawValue
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
        let legacySources = ["\u{65e0}": "None", "\u{5357}\u{952e}": "South", "\u{4e1c}\u{952e}": "East", "\u{897f}\u{952e}": "West", "\u{5317}\u{952e}": "North"]
        if preferences.dictionary(forKey: "mappingOverrides") == nil {
            let previous = preferences.dictionary(forKey: "mapping") as? [String: String] ?? [:]
            let migrated = previous.mapValues { legacySources[$0] ?? $0 }
            mappingOverrides = migrated.filter { ControllerLayout.legacyDefaults[$0.key] != $0.value }
            preferences.set(mappingOverrides, forKey: "mappingOverrides")
        }
        mappingOverrides = mappingOverrides.filter { Self.targets.contains($0.key) }
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
        d.set(layoutChoice, forKey: "layoutChoice")
        d.set(address, forKey: "address"); d.set(mappingOverrides, forKey: "mappingOverrides")
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
        address = ip; save(); sending = true; status = "Sending to \(ip):4950 · \(sendRate) Hz"
        scheduleInputTimer()
        tick()
    }
    func stop() {
        powerReleaseTask?.cancel()
        powerReleaseTask = nil
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
    private func buttonValues() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: sourceButtons.map { ($0.0, $0.1?.isPressed ?? false) })
    }
    private func updatePreview(values: [String: Bool]? = nil, currentMapping: [String: String]? = nil) {
        let values = values ?? buttonValues()
        let currentMapping = currentMapping ?? mapping
        let sources = Set(values.filter { $0.value }.map { $0.key })
        let targets = Set(Self.targets.filter { values[currentMapping[$0] ?? "None"] ?? false })
        // @Published emits even for equal values. Avoid redrawing at the send rate.
        if pressedSources != sources { pressedSources = sources }
        if pressed != targets { pressed = targets }
    }
    var isSendTimerRunning: Bool { timer?.isValid ?? false }
    private func tick() {
        guard sending else { return }
        var state = InputFrame()
        let values = buttonValues()
        if let g = currentController?.extendedGamepad {
            state.leftX = Double(g.leftThumbstick.xAxis.value)
            state.leftY = Double(g.leftThumbstick.yAxis.value) * (invertY ? -1 : 1)
            state.rightX = Double(g.rightThumbstick.xAxis.value)
            state.rightY = Double(g.rightThumbstick.yAxis.value) * (invertY ? -1 : 1)
        }
        let currentMapping = mapping
        func active(_ target: String) -> Bool { values[currentMapping[target] ?? "None"] ?? false }
        updatePreview(values: values, currentMapping: currentMapping)
        for (bit, target) in Self.targets.prefix(12).enumerated() where active(target) { state.buttons |= 1 << bit }
        state.power = active("Power") || powerAction == .press
        state.powerLong = powerAction == .longPress
        state.zl = active("ZL"); state.zr = active("ZR"); state.home = home || active("Home"); state.touch = touch
        let data = state.encoded()
        let sent = data.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
        if sent != data.count {
            let message = String(cString: strerror(errno))
            stop(); status = "Send failed: \(message)"
        }
    }
}
