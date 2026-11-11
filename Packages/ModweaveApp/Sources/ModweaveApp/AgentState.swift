/// The independent inputs that decide whether input handling may run.
/// Keeping them separate (instead of one "enabled" Boolean) is what lets
/// the agent resume correctly after Fast User Switching, permission
/// changes, or a tap failure.
struct AgentInputs: Equatable {
    var userEnabled: Bool
    var sessionActive: Bool
    var permissionsGranted: Bool
    var rulesLoaded: Bool
    var safeMode: Bool
}

enum AgentStatus: Equatable {
    case active
    case pausedByUser
    case pausedInactiveSession
    case needsPermission
    case configurationError
    case safeMode

    /// Ordered by what the user must resolve first.
    static func resolve(_ inputs: AgentInputs) -> AgentStatus {
        if !inputs.sessionActive { return .pausedInactiveSession }
        if inputs.safeMode { return .safeMode }
        if !inputs.rulesLoaded { return .configurationError }
        if !inputs.permissionsGranted { return .needsPermission }
        if !inputs.userEnabled { return .pausedByUser }
        return .active
    }

    var shouldRunTap: Bool { self == .active }

    var title: String {
        switch self {
        case .active: "Active"
        case .pausedByUser: "Paused"
        case .pausedInactiveSession: "Paused - Another User Session"
        case .needsPermission: "Paused - Permissions Required"
        case .configurationError: "Paused - Configuration Error"
        case .safeMode: "Stopped - Safe Mode"
        }
    }
}
