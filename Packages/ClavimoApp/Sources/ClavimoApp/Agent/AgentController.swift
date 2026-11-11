import AppKit
import ClavimoCore
import ClavimoQuartz
import Foundation
import Observation
import ServiceManagement

/// Owns input handling: the independent inputs that decide whether the
/// event tap may run, the tap's lifecycle, and the state shown by the
/// menu bar and the settings window.
@MainActor
@Observable
final class AgentController {
    // MARK: Observable state

    private(set) var status: AgentStatus = .pausedByUser
    private(set) var userEnabled = false
    /// When remapping is paused for a limited time, when it resumes.
    private(set) var pausedUntil: Date?
    private(set) var permissions = PermissionSnapshot.current()
    private(set) var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    private(set) var unsupported: [ConfigIssue] = []
    private(set) var loadError: String?
    private(set) var otherRemapper: String?
    private(set) var loaded: ConfigStore.Loaded?
    let configURL: URL

    /// Called after every state change, for consumers outside SwiftUI.
    @ObservationIgnored var onChange: () -> Void = {}

    // MARK: Private state

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let executor = SystemShortcutExecutor()
    @ObservationIgnored private var controller: EventTapController?
    @ObservationIgnored private var inputs = AgentInputs(
        userEnabled: false, sessionActive: true, permissionsGranted: false, rulesLoaded: false, safeMode: false
    )
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var resumeTimer: Timer?
    @ObservationIgnored private var isRecordingKey = false

    init(store: ConfigStore) {
        self.store = store
        configURL = store.fileURL
    }

    var isTapRunning: Bool { controller != nil }

    // MARK: Lifecycle

    func start() {
        // Cold start can happen inside an inactive session; do not rely on
        // notifications alone.
        inputs.sessionActive = ConsoleSession.isActive() ?? true
        inputs.permissionsGranted = Self.permissionsGranted()
        reloadConfiguration(applyEnabledOnLaunch: true)
        requestPermissionsOnFirstLaunch()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionChanged(active: false) }
        }
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessionChanged(active: true) }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemWoke() }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.controller?.setFrontmostApp(bundleID) }
        }
    }

    func stop() {
        stopTap()
    }

    /// Loads the configuration and shows remapping as active without
    /// touching input, for rendering screenshots.
    func loadForPreview() {
        if case let .success(result) = store.load() {
            loaded = result
            unsupported = result.unsupported
        }
        userEnabled = true
        status = .active
    }

    // MARK: User actions

    func setEnabled(_ enabled: Bool) {
        if enabled, inputs.safeMode { inputs.safeMode = false }
        cancelTimedPause()
        inputs.userEnabled = enabled
        reconcile()
    }

    /// Pauses remapping and resumes automatically after `duration`.
    func pause(for duration: TimeInterval) {
        cancelTimedPause()
        inputs.userEnabled = false
        pausedUntil = Date().addingTimeInterval(duration)
        resumeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.setEnabled(true) }
        }
        reconcile()
    }

    func emergencyDisable() {
        cancelTimedPause()
        inputs.userEnabled = false
        reconcile()
    }

    func leaveSafeMode() {
        inputs.safeMode = false
        setEnabled(true)
    }

    func reloadConfiguration() {
        reloadConfiguration(applyEnabledOnLaunch: false)
    }

    func requestPermissions() {
        PermissionSnapshot.requestAccess()
        SystemSettingsLink.open(.accessibility)
    }

    /// Suspends remapping while a key is being recorded, so the recorder
    /// sees physical keys rather than remapped output.
    func setRecording(_ recording: Bool) {
        isRecordingKey = recording
        controller?.setPaused(recording)
    }

    var launchAtLogin: Bool { loginItemStatus == .enabled }

    var loginItemDescription: String {
        switch loginItemStatus {
        case .enabled: String(localized: "Enabled")
        case .requiresApproval: String(localized: "Needs approval in System Settings")
        case .notRegistered: String(localized: "Disabled")
        case .notFound: String(localized: "Unavailable for this copy of the app")
        @unknown default: String(localized: "Unknown")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        defer { refreshSystemState() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func refreshSystemState() {
        permissions = PermissionSnapshot.current()
        loginItemStatus = SMAppService.mainApp.status
        otherRemapper = Self.otherRemapperName()
    }

    /// Re-reads permissions and makes sure the tap matches the status, for
    /// example when the menu opens after permissions were granted.
    func revalidate() {
        inputs.permissionsGranted = Self.permissionsGranted()
        reconcile()
    }

    func setInspectorEnabled(_ enabled: Bool) {
        controller?.setInspectorEnabled(enabled)
    }

    func inspectedEvents(_ completion: @escaping @Sendable ([EventTapController.InspectedEvent]) -> Void) {
        controller?.inspectedEvents(completion)
    }

    func statistics(_ completion: @escaping @Sendable (EventTapController.Statistics) -> Void) -> Bool {
        guard let controller else { return false }
        controller.statistics(completion)
        return true
    }

    // MARK: State machine

    /// The single place that starts or stops input handling.
    private func reconcile() {
        let resolved = AgentStatus.resolve(inputs)
        if resolved.shouldRunTap {
            if controller == nil { startTap() }
        } else {
            stopTap()
        }
        if isRecordingKey { controller?.setPaused(true) }
        status = AgentStatus.resolve(inputs)
        userEnabled = inputs.userEnabled
        unsupported = loaded?.unsupported ?? []
        refreshSystemState()
        updatePermissionPolling()
        onChange()
    }

    private func startTap() {
        guard let rules = loaded?.rules else { return }
        let executor = executor
        let tap = EventTapController(
            rules: rules,
            actionHandler: { action in executor.run(action) },
            onStop: { [weak self] reason in
                guard reason == .tooManyTapFailures else { return }
                Task { @MainActor in self?.enterSafeMode() }
            }
        )
        do {
            try tap.start()
            tap.setFrontmostApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            controller = tap
        } catch {
            // Creation fails when permissions are missing or were revoked.
            inputs.permissionsGranted = false
        }
    }

    private func stopTap() {
        controller?.stop()
        controller = nil
    }

    private func enterSafeMode() {
        controller = nil
        inputs.safeMode = true
        reconcile()
    }

    private func cancelTimedPause() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        pausedUntil = nil
    }

    private func reloadConfiguration(applyEnabledOnLaunch: Bool) {
        stopTap()
        switch store.load() {
        case let .success(result):
            loaded = result
            loadError = nil
            inputs.rulesLoaded = true
            if applyEnabledOnLaunch { inputs.userEnabled = result.document.engine.enabledOnLaunch }
        case let .failure(error):
            loaded = nil
            loadError = error.description
            inputs.rulesLoaded = false
        }
        reconcile()
    }

    private func sessionChanged(active: Bool) {
        inputs.sessionActive = active
        // Re-check instead of trusting state from before the switch.
        if active { inputs.permissionsGranted = Self.permissionsGranted() }
        reconcile()
    }

    private func systemWoke() {
        guard controller != nil else { return }
        // Fresh tap and empty pressed-state ledger after sleep.
        stopTap()
        reconcile()
    }

    private func updatePermissionPolling() {
        let needsPolling = status == .needsPermission
        if needsPolling, permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollPermissions() }
            }
        } else if !needsPolling {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private func pollPermissions() {
        let granted = Self.permissionsGranted()
        guard granted != inputs.permissionsGranted else { return }
        inputs.permissionsGranted = granted
        reconcile()
    }

    /// Opening the app is the user's explicit action, so ask once; this
    /// also lists the app in System Settings, which the user can otherwise
    /// only do by browsing to the bundle. Later requests come from the UI.
    private func requestPermissionsOnFirstLaunch() {
        let key = "didRequestPermissions"
        guard !inputs.permissionsGranted, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        PermissionSnapshot.requestAccess()
    }

    private static func permissionsGranted() -> Bool {
        let snapshot = PermissionSnapshot.current()
        return snapshot.accessibilityTrusted && snapshot.listenEventAccess
    }

    static func otherRemapperName() -> String? {
        let known = [
            "org.pqrs.Karabiner": "Karabiner-Elements",
            "com.logi.optionsplus": "Logi Options+",
            "com.pilotmoon.scroll-reverser": "Scroll Reverser",
            "com.hegenberg.BetterTouchTool": "BetterTouchTool",
            "com.lujjjh.LinearMouse": "LinearMouse",
        ]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            if let match = known.first(where: { id.hasPrefix($0.key) }) { return match.value }
        }
        return nil
    }
}

/// Deep links into System Settings.
enum SystemSettingsLink {
    case accessibility, inputMonitoring, loginItems, mouse, keyboardShortcuts

    private var url: String {
        switch self {
        case .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .loginItems: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case .mouse: "x-apple.systempreferences:com.apple.Mouse-Settings.extension"
        case .keyboardShortcuts: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        }
    }

    @MainActor
    static func open(_ link: SystemSettingsLink) {
        if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
    }
}
