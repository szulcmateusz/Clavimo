import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        if let status = CommandLineTool.run(CommandLine.arguments) {
            exit(status)
        }
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-screenshots"), index + 1 < arguments.count {
            exit(ScreenshotRenderer.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1])))
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let store = ConfigStore(fileURL: ConfigStore.defaultLocation())
    private lazy var agent = AgentController(store: store)
    private lazy var editor = ConfigEditor(store: store)
    private lazy var windows = WindowCoordinator(agent: agent, editor: editor)
    private var menu: StatusMenuController?
    /// Set when another copy is already running; this one quits without
    /// touching input or the Caps Lock mapping that copy owns.
    private var isDuplicate = false
    private let overlayPanel = KeyboardOverlayPanel()

    func applicationDidFinishLaunching(_: Notification) {
        // Two copies would each install an event tap and run every rule
        // twice. A second launch shows the running copy's settings instead.
        let me = NSRunningApplication.current
        if let bundleID = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }) {
            isDuplicate = true
            other.activate()
            NSApp.terminate(nil)
            return
        }
        let menu = StatusMenuController(agent: agent, editor: editor) { [weak self] in self?.windows.showSettings() }
        self.menu = menu
        agent.onChange = { [weak menu] in menu?.updateIcon() }
        agent.onOverlayChange = { [weak self, weak menu] overlay in
            self?.overlayPanel.show(overlay)
            menu?.showLayer(overlay.layers.last)
        }
        editor.onSaved = { [weak self] in self?.agent.reloadConfiguration() }
        agent.start()

        // First launch with no rules: guide the user. People who already
        // have rules (for example from an earlier version) skip the guide.
        NotificationCenter.default.addObserver(forName: .showWelcomeGuide, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows.showOnboarding { [weak self] in self?.windows.showSettings() }
            }
        }

        let key = "didCompleteOnboarding"
        let document = agent.loaded?.document
        let hasRules = !(document?.rules.isEmpty ?? true) || !(document?.deviceSettings ?? []).isEmpty
        if !UserDefaults.standard.bool(forKey: key) {
            if hasRules {
                UserDefaults.standard.set(true, forKey: key)
            } else {
                windows.showOnboarding { [weak self] in
                    UserDefaults.standard.set(true, forKey: key)
                    self?.windows.showSettings()
                }
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        guard !isDuplicate else { return }
        agent.stop()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows settings,
    /// so the app stays reachable even when the menu bar item is hidden.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        windows.showSettings()
        return false
    }
}
