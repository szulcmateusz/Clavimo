import ApplicationServices
import CoreGraphics

/// Reads the current permission state without prompting. Nothing here is
/// treated as granted unless the system API reports it.
public struct PermissionSnapshot: Equatable, Sendable {
    public let accessibilityTrusted: Bool
    public let listenEventAccess: Bool
    public let postEventAccess: Bool

    public static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibilityTrusted: AXIsProcessTrusted(),
            listenEventAccess: CGPreflightListenEventAccess(),
            postEventAccess: CGPreflightPostEventAccess()
        )
    }

    /// Opens the system prompts. Only call after an explicit user action.
    public static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        _ = CGRequestPostEventAccess()
    }
}

/// Whether this process runs in the session that owns the console, i.e.
/// the account currently in front after Fast User Switching.
public enum ConsoleSession {
    public static func isActive() -> Bool? {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return info[kCGSessionOnConsoleKey as String] as? Bool
    }
}
