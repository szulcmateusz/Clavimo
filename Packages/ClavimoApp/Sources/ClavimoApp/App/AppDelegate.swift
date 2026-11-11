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

    func applicationDidFinishLaunching(_: Notification) {
        let menu = StatusMenuController(agent: agent, editor: editor) { [weak self] in self?.windows.showSettings() }
        self.menu = menu
        agent.onChange = { [weak menu] in menu?.updateIcon() }
        editor.onSaved = { [weak self] in self?.agent.reloadConfiguration() }
        agent.start()

        let document = agent.loaded?.document
        if document?.rules.isEmpty == true && (document?.deviceSettings ?? []).isEmpty {
            windows.showSettings()
        }
    }

    func applicationWillTerminate(_: Notification) {
        agent.stop()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows settings,
    /// so the app stays reachable even when the menu bar item is hidden.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        windows.showSettings()
        return false
    }
}
