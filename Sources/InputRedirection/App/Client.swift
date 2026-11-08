import AppKit
import Combine
import Darwin
import Foundation
import GameController
import InputCore

@MainActor final class Client: ObservableObject {
    @Published var address = "192.168.1.100"
    @Published var controllers: [GCController] = []
    @Published var selected = 0 { didSet { configureController() } }
    @Published var sending = false
    @Published var status = "Not sending"
    @Published var pressed: Set<InputTarget> = []
    @Published var pressedSources: Set<InputSource> = []
    @Published var invertY = false {
        didSet { if invertY != oldValue { saveCurrentProfile() } }
    }
    @Published private(set) var mappingTarget: InputTarget?
    @Published private(set) var home = false
    @Published private(set) var powerAction: PowerAction?
    @Published var sendRate = 125 {
        didSet {
            guard sendRate != oldValue else { return }
            scheduleInputTimer()
            preferences.set(sendRate, forKey: "sendRate")
            if sending { status = "Sending to \(address):4950 · \(sendRate) Hz" }
        }
    }

    var touch: (Double, Double)?

    @Published private var mappingOverrides: [InputTarget: InputSource] = [:]
    private var mappingStartedAt = 0.0
    private var mappingInputSuppressed = false
    private let controllerInput = ControllerInput()
    enum PowerAction { case press, longPress }
    private enum PulseButton { case home, power }
    private var releaseTasks: [PulseButton: Task<Void, Never>] = [:]
    private var socketFD: Int32 = -1
    private var timer: Timer?
    private var sendingActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private let profileStore: ControllerProfileStore
    private var activeProfileKey: String?
    private var unassignedProfile = ControllerProfile()
    private var isLoadingProfile = false
    private let preferences: UserDefaults
    private let controllerProvider: () -> [GCController]
    private let socketFactory: () throws -> Int32

    init(
        preferences: UserDefaults = .standard,
        controllerProvider: @escaping () -> [GCController] = { GCController.controllers() },
        socketFactory: @escaping () throws -> Int32 = UDPSocket.make
    ) {
        // Continue receiving controller events when another app has focus.
        GCController.shouldMonitorBackgroundEvents = true
        self.preferences = preferences
        profileStore = ControllerProfileStore(preferences: preferences)
        self.controllerProvider = controllerProvider
        self.socketFactory = socketFactory
        address = preferences.string(forKey: "address") ?? "192.168.1.100"
        sendRate = min(250, max(50, preferences.object(forKey: "sendRate") as? Int ?? 125))
        controllerInput.onButtonPress = { [weak self] source, time in
            self?.captureButton(source, at: time)
        }
        controllerInput.onStickMove = { [weak self] source, time in
            self?.captureStick(source, at: time)
        }
        controllerInput.onChange = { [weak self] in
            guard let self, !self.sending else { return }
            self.updatePreview()
        }
        observeLifecycle()
        useProfile(for: nil)
        refresh()
    }

    var currentController: GCController? {
        controllers.indices.contains(selected) ? controllers[selected] : nil
    }
    var layout: ControllerLayout {
        guard let controller = currentController else { return .xbox }
        if controller.extendedGamepad is GCDualSenseGamepad
            || controller.extendedGamepad is GCDualShockGamepad
        {
            return .playStation
        }
        if controller.extendedGamepad is GCXboxGamepad { return .xbox }
        return ControllerLayout.detect(
            category: controller.productCategory, vendor: controller.vendorName ?? "")
    }
    private func configureController() {
        cancelMapping()
        controllerInput.configure(currentController)
        useProfile(for: currentController)
        objectWillChange.send()
        updatePreview()
    }

    func sourceSymbol(_ source: InputSource) -> String? { controllerInput.sourceSymbol(source) }
    func sourceLabel(_ source: InputSource) -> String { controllerInput.sourceLabel(source) }
    func sourceIsAvailable(_ source: InputSource) -> Bool {
        controllerInput.sourceIsAvailable(source)
    }

    func refresh() {
        let previous = currentController
        controllers = controllerProvider().filter {
            let profile = $0.physicalInputProfile
            return !profile.buttons.isEmpty || !profile.dpads.isEmpty
        }
        selected =
            controllers.firstIndex { $0 === previous }
            ?? min(selected, max(0, controllers.count - 1))
    }

    func availableSources(for target: InputTarget) -> [InputSource] {
        target.sources.filter { sourceIsAvailable($0) }
    }

    var defaultMapping: [InputTarget: InputSource] {
        let defaults = layout.defaultMapping()
        guard currentController != nil else { return defaults }
        return defaults.mapValues { sourceIsAvailable($0) ? $0 : .none }
    }
    var mapping: [InputTarget: InputSource] {
        get { defaultMapping.merging(mappingOverrides) { _, custom in custom } }
        set {
            let defaults = defaultMapping
            mappingOverrides = newValue.filter {
                $0.key.sources.contains($0.value) && defaults[$0.key] != $0.value
            }
            updatePreview()
            saveCurrentProfile()
        }
    }

    func beginMapping(_ target: InputTarget) {
        cancelButtonActions()
        home = false
        touch = nil
        mappingInputSuppressed = sending
        mappingStartedAt = ProcessInfo.processInfo.systemUptime
        mappingTarget = target
        tick()
    }

    func cancelMapping() {
        mappingTarget = nil
        if mappingInputSuppressed && !controllerInput.buttonValues().values.contains(true) {
            mappingInputSuppressed = false
        }
    }

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

    private func useProfile(for controller: GCController?) {
        let key = controller.map { ControllerProfileStore.key(for: $0) }
        guard activeProfileKey != key else { return }
        saveCurrentProfile()
        let profile = key.map { profileStore.load(for: $0) } ?? unassignedProfile
        isLoadingProfile = true
        activeProfileKey = key
        mappingOverrides = profile.mappingOverrides
        invertY = profile.invertY
        isLoadingProfile = false
    }

    private func saveCurrentProfile() {
        guard !isLoadingProfile else { return }
        let profile = ControllerProfile(mappingOverrides: mappingOverrides, invertY: invertY)
        if let key = activeProfileKey {
            profileStore.save(profile, for: key)
        } else {
            unassignedProfile = profile
        }
    }

    func save() {
        preferences.set(address, forKey: "address")
        saveCurrentProfile()
    }

    private func observeLifecycle() {
        for name in [
            Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
            .GCControllerUserCustomizationsDidChange,
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                    self?.controllerInput.releaseSystemButtons()
                }
            })
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
    }

    func triggerHome() {
        guard !home else { return }
        triggerPulse(.home, press: { $0.home = true }, release: { $0.home = false })
    }

    func triggerPower(longPress: Bool) {
        triggerPulse(
            .power,
            press: { $0.powerAction = longPress ? .longPress : .press },
            release: { $0.powerAction = nil })
    }

    private func triggerPulse(
        _ button: PulseButton, press: (Client) -> Void,
        release: @escaping (Client) -> Void
    ) {
        guard sending, !mappingInputSuppressed else { return }
        releaseTasks[button]?.cancel()
        press(self)
        tick()
        guard sending else { return }
        releaseTasks[button] = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self else { return }
            release(self)
            self.releaseTasks[button] = nil
            self.tick()
        }
    }
    private func cancelButtonActions() {
        for task in releaseTasks.values { task.cancel() }
        releaseTasks.removeAll()
        if powerAction != nil { powerAction = nil }
    }

    private func updatePreview(
        values: [InputSource: Bool]? = nil, currentMapping: [InputTarget: InputSource]? = nil
    ) {
        let values = values ?? controllerInput.buttonValues()
        let currentMapping = currentMapping ?? mapping
        let sources = Set(values.filter { $0.value }.map { $0.key })
        let targets: Set<InputTarget> =
            mappingInputSuppressed
            ? []
            : Set(
                InputTarget.allCases.filter { values[currentMapping[$0] ?? .none] ?? false })
        // @Published emits even for equal values. Avoid redrawing at the send rate.
        if pressedSources != sources { pressedSources = sources }
        if pressed != targets { pressed = targets }
    }
    func inputFrame() -> InputFrame {
        var state = InputFrame()
        let values = controllerInput.buttonValues()
        if mappingInputSuppressed {
            if mappingTarget != nil || values.values.contains(true) {
                updatePreview(values: values)
                return state
            }
            // Do not forward the press or stick movement used to assign a mapping.
            mappingInputSuppressed = false
        }
        let circle = controllerInput.stick(mapping[.circlePad] ?? .none)
        let c = controllerInput.stick(mapping[.cStick] ?? .none)
        state.leftX = Double(circle?.xAxis.value ?? 0)
        state.leftY = Double(circle?.yAxis.value ?? 0) * (invertY ? -1 : 1)
        state.rightX = Double(c?.xAxis.value ?? 0)
        state.rightY = Double(c?.yAxis.value ?? 0) * (invertY ? -1 : 1)
        let currentMapping = mapping
        func active(_ target: InputTarget) -> Bool {
            values[currentMapping[target] ?? .none] ?? false
        }
        updatePreview(values: values, currentMapping: currentMapping)
        for target in InputTarget.allCases where active(target) {
            state.buttons |= target.buttonMask
        }
        state.power = active(.power) || powerAction == .press
        state.powerLong = powerAction == .longPress
        state.zl = active(.zl)
        state.zr = active(.zr)
        state.home = home || active(.home)
        state.touch = touch
        return state
    }

    private func scheduleInputTimer() {
        timer?.invalidate()
        timer = nil
        guard sending else { return }
        let inputTimer = Timer(timeInterval: 1.0 / Double(sendRate), repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        inputTimer.tolerance = 0
        RunLoop.main.add(inputTimer, forMode: .common)
        timer = inputTimer
    }
    func start() {
        stop()
        var endpoint = sockaddr_in()
        endpoint.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endpoint.sin_family = sa_family_t(AF_INET)
        endpoint.sin_port = UInt16(4950).bigEndian
        let ip = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inet_pton(AF_INET, ip, &endpoint.sin_addr) == 1 else {
            status = "Enter a valid 3DS IPv4 address"
            return
        }
        do { socketFD = try socketFactory() } catch {
            status = "Unable to configure UDP socket: \(error.localizedDescription)"
            return
        }
        let result = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            stop()
            status = "Network error: \(message)"
            return
        }
        // Prevent App Nap from throttling the send timer while hidden or unfocused.
        sendingActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Redirect controller input to Nintendo 3DS"
        )
        address = ip
        save()
        sending = true
        status = "Sending to \(ip):4950 · \(sendRate) Hz"
        scheduleInputTimer()
        tick()
    }
    func stop() {
        cancelMapping()
        mappingInputSuppressed = false
        if let sendingActivity {
            ProcessInfo.processInfo.endActivity(sendingActivity)
            self.sendingActivity = nil
        }
        cancelButtonActions()
        timer?.invalidate()
        timer = nil
        if socketFD >= 0 {
            let neutral = InputFrame().encoded()
            for _ in 0..<3 {
                _ = neutral.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
            }
            Darwin.close(socketFD)
            socketFD = -1
        }
        sending = false
        touch = nil
        home = false
        status = "Stopped"
        updatePreview()
    }
    var isSendTimerRunning: Bool { timer?.isValid ?? false }
    private func tick() {
        guard sending else { return }
        let data = inputFrame().encoded()
        let sent = data.withUnsafeBytes { Darwin.send(socketFD, $0.baseAddress, $0.count, 0) }
        if sent != data.count {
            let message = String(cString: strerror(errno))
            stop()
            status = "Send failed: \(message)"
        }
    }
}
