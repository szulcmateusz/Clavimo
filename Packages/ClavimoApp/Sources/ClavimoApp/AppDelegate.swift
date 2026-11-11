import AppKit
import ClavimoCore
import ClavimoQuartz
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        if CommandLine.arguments.contains("--check-config") {
            exit(checkConfiguration())
        }
        if CommandLine.arguments.contains("--list-devices") {
            for device in HIDDeviceCatalog.connectedDevices() {
                let kinds = [device.isKeyboard ? "keyboard" : nil, device.isPointer ? "pointer" : nil].compactMap { $0 }
                print("\(device.id)\t\(device.name) [\(kinds.joined(separator: ", "))] \(device.transport ?? "")")
            }
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Validates the configuration without touching input and prints a
    /// summary. Exit status 0 means every enabled rule is active.
    private static func checkConfiguration() -> Int32 {
        let store = ConfigStore(fileURL: ConfigStore.defaultLocation())
        print("Configuration: \(store.fileURL.path)")
        switch store.load() {
        case let .failure(error):
            print(error.description)
            return 1
        case let .success(loaded):
            let document = loaded.document
            let enabled = document.rules.filter { $0.enabled && $0.profileId == document.activeProfileId }
            print("Active profile: \(document.activeProfileId)")
            print("Enabled rules: \(enabled.count), supported: \(enabled.count - loaded.unsupported.count)")
            for rule in enabled where !loaded.unsupported.contains(where: { $0.ruleID == rule.id }) {
                print("  ok    \(rule.name)")
            }
            for issue in loaded.unsupported {
                print("  skip  \(issue)")
            }
            print("Remapping on launch: \(document.engine.enabledOnLaunch ? "yes" : "no")")
            return loaded.unsupported.isEmpty ? 0 : 2
        }
    }

    private let store = ConfigStore(fileURL: ConfigStore.defaultLocation())
    private let executor = SystemShortcutExecutor()
    private var statusItem: NSStatusItem?
    private var controller: EventTapController?
    private var loaded: ConfigStore.Loaded?
    private var loadError: ConfigStore.LoadError?
    private var permissionTimer: Timer?
    private var inputs = AgentInputs(
        userEnabled: false,
        sessionActive: true,
        permissionsGranted: false,
        rulesLoaded: false,
        safeMode: false
    )

    private var status: AgentStatus { AgentStatus.resolve(inputs) }

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // Cold start can happen inside an inactive session; do not rely on
        // notifications alone.
        inputs.sessionActive = ConsoleSession.isActive() ?? true
        inputs.permissionsGranted = Self.permissionsGranted()
        reloadConfiguration(applyEnabledOnLaunch: true)
        requestPermissionsOnFirstLaunch()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_: Notification) {
        stopTap()
    }

    /// Opening the app is the user's explicit action, so ask once; this
    /// also lists the app in System Settings, which the user can otherwise
    /// only do by browsing to the bundle. Later requests come from the menu.
    private func requestPermissionsOnFirstLaunch() {
        let key = "didRequestPermissions"
        guard !inputs.permissionsGranted, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        PermissionSnapshot.requestAccess()
    }

    // MARK: - State

    private static func permissionsGranted() -> Bool {
        let snapshot = PermissionSnapshot.current()
        return snapshot.accessibilityTrusted && snapshot.listenEventAccess
    }

    /// The single place that starts or stops input handling.
    private func reconcile() {
        if status.shouldRunTap {
            if controller == nil { startTap() }
        } else {
            stopTap()
        }
        updatePermissionPolling()
        updateIcon()
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

    private func updatePermissionPolling() {
        let needsPolling = status == .needsPermission
        if needsPolling, permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollPermissions() }
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

    private func reloadConfiguration(applyEnabledOnLaunch: Bool) {
        let wasRunning = controller != nil
        stopTap()
        switch store.load() {
        case let .success(result):
            loaded = result
            loadError = nil
            inputs.rulesLoaded = true
            if applyEnabledOnLaunch { inputs.userEnabled = result.document.engine.enabledOnLaunch }
        case let .failure(error):
            loaded = nil
            loadError = error
            inputs.rulesLoaded = false
        }
        _ = wasRunning
        reconcile()
    }

    // MARK: - Notifications

    @objc private func sessionResigned() {
        inputs.sessionActive = false
        reconcile()
    }

    @objc private func sessionBecameActive() {
        inputs.sessionActive = true
        // Re-check instead of trusting state from before the switch.
        inputs.permissionsGranted = Self.permissionsGranted()
        reconcile()
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        controller?.setFrontmostApp(app?.bundleIdentifier)
    }

    @objc private func systemWoke() {
        guard controller != nil else { return }
        // Fresh tap and empty pressed-state ledger after sleep.
        stopTap()
        reconcile()
    }

    // MARK: - Menu

    private func updateIcon() {
        let symbol = switch status {
        case .active: "keyboard"
        case .pausedByUser, .pausedInactiveSession: "pause.circle"
        case .needsPermission, .configurationError, .safeMode: "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Clavimo: \(status.title)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        inputs.permissionsGranted = Self.permissionsGranted()
        if status.shouldRunTap != (controller != nil) { reconcile() }
        menu.removeAllItems()

        menu.addItem(disabled("Clavimo - \(status.title)"))
        let toggle = item(inputs.userEnabled ? "Pause Remapping" : "Resume Remapping", #selector(toggleEnabled))
        toggle.isEnabled = !inputs.safeMode
        menu.addItem(toggle)
        if inputs.safeMode {
            menu.addItem(item("Leave Safe Mode and Resume", #selector(leaveSafeMode)))
        }
        menu.addItem(item("Emergency Disable", #selector(emergencyDisable)))
        menu.addItem(.separator())

        if let loaded {
            let count = loaded.document.rules.filter { $0.enabled && $0.profileId == loaded.document.activeProfileId }.count
            menu.addItem(disabled("\(count - loaded.unsupported.count) of \(count) rules supported"))
            if !loaded.unsupported.isEmpty {
                let submenu = NSMenu()
                for issue in loaded.unsupported { submenu.addItem(disabled(issue.description)) }
                let parent = NSMenuItem(title: "Unsupported Rules (\(loaded.unsupported.count))", action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            }
        } else if let loadError {
            menu.addItem(disabled(loadError.description))
        }
        if let conflict = Self.otherRemapperName() {
            menu.addItem(disabled("Warning: \(conflict) is running and may conflict"))
        }
        if !inputs.permissionsGranted {
            menu.addItem(item("Grant Permissions...", #selector(requestPermissions)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Reload Configuration", #selector(reload), key: "r"))
        menu.addItem(item("Show Configuration in Finder", #selector(revealConfiguration)))
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.title = "Launch at Login (Needs Approval in System Settings)"
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Clavimo", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func otherRemapperName() -> String? {
        let known = [
            "org.pqrs.Karabiner": "Karabiner-Elements",
            "com.logi.optionsplus": "Logi Options+",
            "com.pilotmoon.scroll-reverser": "Scroll Reverser",
            "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        ]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            if let match = known.first(where: { id.hasPrefix($0.key) }) { return match.value }
        }
        return nil
    }

    @objc private func toggleEnabled() {
        inputs.userEnabled.toggle()
        reconcile()
    }

    @objc private func leaveSafeMode() {
        inputs.safeMode = false
        inputs.userEnabled = true
        reconcile()
    }

    @objc private func emergencyDisable() {
        inputs.userEnabled = false
        reconcile()
    }

    @objc private func requestPermissions() {
        PermissionSnapshot.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func reload() {
        reloadConfiguration(applyEnabledOnLaunch: false)
    }

    @objc private func revealConfiguration() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func quit() {
        stopTap()
        NSApp.terminate(nil)
    }
}
