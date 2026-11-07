import AppKit
import Combine
import GameController
import Darwin
import InputCore

@MainActor final class Client: ObservableObject {
    @Published var address = UserDefaults.standard.string(forKey: "address") ?? "192.168.1.100"
    @Published var controllers: [GCController] = []
    @Published var selected = 0 { didSet { configureSystemButtons() } }
    @Published var sending = false
    @Published var status = "Not sending"
    @Published var pressed: Set<String> = []
    @Published var invertY = UserDefaults.standard.bool(forKey: "invertY")
    @Published private var mappingOverrides = UserDefaults.standard.dictionary(forKey: "mappingOverrides") as? [String: String] ?? [:]
    var defaultMapping: [String: String] {
        let legends = Dictionary(uniqueKeysWithValues: ["South", "East", "West", "North"].map { ($0, sourceLabel($0)) })
        return layout.defaultMapping(faceLegends: legends)
    }
    var mapping: [String: String] {
        get { defaultMapping.merging(mappingOverrides) { _, custom in custom } }
        set { mappingOverrides = newValue.filter { defaultMapping[$0.key] != $0.value } }
    }
    func restoreDefaults() {
        mappingOverrides = [:]
        save()
    }
    @Published var layoutChoice = UserDefaults.standard.string(forKey: "layoutChoice") ?? ControllerLayout.automatic.rawValue
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
    var sourceButtons: [(String, GCControllerButtonInput?)] {
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
    func sourceIsAvailable(_ source: String) -> Bool {
        source == "None" || sourceButtons.contains { $0.0 == source && $0.1 != nil }
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
        guard layoutChoice == ControllerLayout.automatic.rawValue else { return nil }
        return sourceButtons.first { $0.0 == source }?.1?.sfSymbolsName
    }
    func sourceLabel(_ source: String) -> String {
        layout.label(for: source, symbol: sourceSymbol(source))
    }
    var touch: (Double, Double)?
    var home = false
    private var socketFD: Int32 = -1
    @Published var sendRate = min(250, max(50, UserDefaults.standard.object(forKey: "sendRate") as? Int ?? 120)) {
        didSet {
            guard sendRate != oldValue else { return }
            scheduleInputTimer()
            UserDefaults.standard.set(sendRate, forKey: "sendRate")
            if sending { status = "Sending to \(address):4950 · \(sendRate) Hz" }
        }
    }
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    static let targets = ["A", "B", "Select", "Start", "Right", "Left", "Up", "Down", "R", "L", "X", "Y", "ZL", "ZR", "Home"]
    static let sources = ["None", "South", "East", "West", "North", "L1", "R1", "L2", "R2", "Menu", "Options", "L3", "R3", "ControllerHome", "Capture", "↑", "↓", "←", "→"]


    init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
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
        if UserDefaults.standard.dictionary(forKey: "mappingOverrides") == nil {
            let previous = UserDefaults.standard.dictionary(forKey: "mapping") as? [String: String] ?? [:]
            let migrated = previous.mapValues { legacySources[$0] ?? $0 }
            mappingOverrides = migrated.filter { ControllerLayout.legacyDefaults[$0.key] != $0.value }
            UserDefaults.standard.set(mappingOverrides, forKey: "mappingOverrides")
        }
        refresh()
        scheduleInputTimer()
    }
    private func scheduleInputTimer() {
        timer?.invalidate()
        let inputTimer = Timer(timeInterval: 1.0 / Double(sendRate), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        inputTimer.tolerance = 0
        RunLoop.main.add(inputTimer, forMode: .common)
        timer = inputTimer
    }
    func refresh() {
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        selected = min(selected, max(0, controllers.count - 1))
        configureSystemButtons()
    }
    func save() {
        let d = UserDefaults.standard
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
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { status = "Unable to create UDP socket"; return }
        let result = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { stop(); status = "Network error: \(String(cString: strerror(errno)))"; return }
        _ = fcntl(socketFD, F_SETFL, O_NONBLOCK)
        address = ip; save(); sending = true; status = "Sending to \(ip):4950 · \(sendRate) Hz"
    }
    func stop() {
        if socketFD >= 0 {
            let neutral = InputFrame().encoded()
            for _ in 0..<3 { _ = neutral.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) } }
            Darwin.close(socketFD); socketFD = -1
        }
        sending = false; touch = nil; home = false; status = "Stopped"
    }
    private func tick() {
        var state = InputFrame()
        var values: [String: Bool] = [:]
        if controllers.indices.contains(selected), let g = controllers[selected].extendedGamepad {
            for (name, button) in sourceButtons { values[name] = button?.isPressed ?? false }
            state.leftX = Double(g.leftThumbstick.xAxis.value)
            state.leftY = Double(g.leftThumbstick.yAxis.value) * (invertY ? -1 : 1)
            state.rightX = Double(g.rightThumbstick.xAxis.value)
            state.rightY = Double(g.rightThumbstick.yAxis.value) * (invertY ? -1 : 1)
        }
        let currentMapping = mapping
        func active(_ target: String) -> Bool { values[currentMapping[target] ?? "None"] ?? false }
        pressedSources = Set(values.filter { $0.value }.map { $0.key })
        pressed = Set(Self.targets.filter(active))
        for (bit, target) in Self.targets.prefix(12).enumerated() where active(target) { state.buttons |= 1 << bit }
        state.zl = active("ZL"); state.zr = active("ZR"); state.home = home || active("Home"); state.touch = touch
        guard sending else { return }
        let data = state.encoded()
        let sent = data.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
        if sent != data.count {
            let message = String(cString: strerror(errno))
            stop(); status = "Send failed: \(message)"
        }
    }
}
