import ClavimoCore
import ClavimoQuartz
import Foundation
import Observation
import ServiceManagement

/// State shared by the menu bar item and the settings window. The app
/// delegate owns input handling and pushes state here; views call back
/// through the closures instead of touching the event tap directly.
@MainActor
@Observable
final class AppModel {
    var status: AgentStatus = .pausedByUser
    var userEnabled = false
    var permissions = PermissionSnapshot.current()
    var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    var unsupported: [ConfigIssue] = []
    var loadError: String?
    var otherRemapper: String?
    var configURL: URL

    var setEnabled: (Bool) -> Void = { _ in }
    var reloadConfiguration: () -> Void = {}
    var requestPermissions: () -> Void = {}
    /// Suspends remapping while a key is being recorded, so the recorder
    /// sees physical keys rather than remapped output.
    var setRecording: (Bool) -> Void = { _ in }

    init(configURL: URL) {
        self.configURL = configURL
    }

    func refreshSystemState() {
        permissions = PermissionSnapshot.current()
        loginItemStatus = SMAppService.mainApp.status
    }

    var launchAtLogin: Bool { loginItemStatus == .enabled }

    var loginItemDescription: String {
        switch loginItemStatus {
        case .enabled: "Enabled"
        case .requiresApproval: "Needs Approval in System Settings"
        case .notRegistered: "Disabled"
        case .notFound: "Unavailable for this copy of the app"
        @unknown default: "Unknown"
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
}
