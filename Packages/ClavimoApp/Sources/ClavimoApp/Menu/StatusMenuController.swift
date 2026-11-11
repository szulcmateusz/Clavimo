import AppKit
import ServiceManagement

/// The menu bar item: an icon that reflects the agent status and a menu
/// with the controls that must stay reachable without the main window.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let agent: AgentController
    private let editor: ConfigEditor
    private let showSettings: () -> Void
    private let statusItem: NSStatusItem

    init(agent: AgentController, editor: ConfigEditor, showSettings: @escaping () -> Void) {
        self.agent = agent
        self.editor = editor
        self.showSettings = showSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    /// Names the active layer next to the icon, so it is visible even when
    /// the overlay is turned off.
    func showLayer(_ layer: String?) {
        statusItem.button?.title = layer.map { " \($0)" } ?? ""
        statusItem.button?.imagePosition = .imageLeading
    }

    func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(for: agent.status)
        statusItem.button?.setAccessibilityLabel(String(localized: "Clavimo: \(agent.status.title)"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        agent.revalidate()
        menu.removeAllItems()

        menu.addItem(disabled(String(localized: "Clavimo: \(agent.status.title)")))
        if agent.secureInput.isEnabled, agent.status == .active {
            let text = agent.secureInput.appName.map { String(localized: "Keyboard rules wait: secure typing is on in \($0)") }
                ?? String(localized: "Keyboard rules wait: secure typing (a password field) is on")
            menu.addItem(disabled(text))
        }
        if let until = agent.pausedUntil {
            menu.addItem(disabled(String(localized: "Resumes at \(until.formatted(date: .omitted, time: .shortened))")))
        }

        if agent.status == .safeMode {
            menu.addItem(item(String(localized: "Leave Safe Mode and Resume")) { [agent] in agent.leaveSafeMode() })
        } else if agent.userEnabled {
            let pause = NSMenuItem(title: String(localized: "Pause Remapping"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(item(String(localized: "For 5 Minutes")) { [agent] in agent.pause(for: 5 * 60) })
            submenu.addItem(item(String(localized: "For 1 Hour")) { [agent] in agent.pause(for: 60 * 60) })
            submenu.addItem(item(String(localized: "Until I Resume")) { [agent] in agent.setEnabled(false) })
            pause.submenu = submenu
            menu.addItem(pause)
        } else {
            menu.addItem(item(String(localized: "Resume Remapping")) { [agent] in agent.setEnabled(true) })
        }
        menu.addItem(item(String(localized: "Emergency Disable")) { [agent] in agent.emergencyDisable() })
        menu.addItem(.separator())

        editor.reload()
        if editor.profiles.count > 1 {
            let parent = NSMenuItem(title: String(localized: "Profile: \(editor.profileName(editor.activeProfileID))"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for profile in editor.profiles {
                let entry = item(profile.name) { [editor] in editor.setActiveProfile(profile.id) }
                entry.state = profile.id == editor.activeProfileID ? .on : .off
                submenu.addItem(entry)
            }
            parent.submenu = submenu
            menu.addItem(parent)
            menu.addItem(.separator())
        }

        if !agent.unsupported.isEmpty {
            let parent = NSMenuItem(title: String(localized: "Unsupported Rules (\(agent.unsupported.count))"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for issue in agent.unsupported { submenu.addItem(disabled(Messages.describe(issue))) }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        if let error = agent.loadError {
            menu.addItem(disabled(error))
        }
        if let other = agent.otherRemapper {
            menu.addItem(disabled(String(localized: "\(other) is running and may conflict")))
        }
        if !(agent.permissions.accessibilityTrusted && agent.permissions.listenEventAccess) {
            menu.addItem(item(String(localized: "Grant Permissions...")) { [agent] in agent.requestPermissions() })
        }
        if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }

        menu.addItem(item(String(localized: "Settings..."), key: ",") { [showSettings] in showSettings() })
        menu.addItem(item(String(localized: "Reload Configuration"), key: "r") { [agent] in agent.reloadConfiguration() })
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Clavimo"), key: "q") { [agent] in
            agent.stop()
            NSApp.terminate(nil)
        })
    }

    // MARK: - Helpers

    private func item(_ title: String, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// A menu item that runs a closure, so menus do not need one selector per
/// command.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

/// The menu bar icon: the Clavimo mark as a template image, so it adapts
/// to light and dark menu bars. Paused states are dimmed and states that
/// need attention carry a badge. Outside an app bundle (tests, development
/// runs) SF Symbols stand in.
enum MenuBarIcon {
    @MainActor
    static func image(for status: AgentStatus) -> NSImage? {
        let (resource, symbol) = switch status {
        case .active: ("MenuBarIcon", "keyboard")
        case .pausedByUser, .pausedInactiveSession: ("MenuBarIcon-paused", "pause.circle")
        case .needsPermission, .configurationError, .safeMode: ("MenuBarIcon-attention", "exclamationmark.triangle")
        }
        let image = Bundle.main.image(forResource: resource)
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: status.title)
        image?.isTemplate = true
        image?.accessibilityDescription = status.title
        return image
    }
}
