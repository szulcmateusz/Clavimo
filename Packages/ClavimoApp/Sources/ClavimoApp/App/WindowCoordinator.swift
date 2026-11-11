import AppKit
import SwiftUI

/// Creates and shows the app's windows. The app has no Dock icon, so a
/// window is brought forward explicitly when shown.
@MainActor
final class WindowCoordinator {
    private let agent: AgentController
    private let editor: ConfigEditor
    private var settingsWindow: NSWindow?

    init(agent: AgentController, editor: ConfigEditor) {
        self.agent = agent
        self.editor = editor
    }

    func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: agent, editor: editor))
            let window = NSWindow(contentViewController: host)
            window.title = "Clavimo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 900, height: 600))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("ClavimoSettings")
            settingsWindow = window
        }
        editor.reload()
        agent.refreshSystemState()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
