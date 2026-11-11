import AppKit
import SwiftUI

/// Creates and shows the app's windows. The app has no Dock icon, so a
/// window is brought forward explicitly when shown.
@MainActor
final class WindowCoordinator {
    private let agent: AgentController
    private let editor: ConfigEditor
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

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

    func showOnboarding(finished: @escaping () -> Void) {
        if onboardingWindow == nil {
            let view = OnboardingView(agent: agent, editor: editor) { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                finished()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Welcome to Clavimo")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
