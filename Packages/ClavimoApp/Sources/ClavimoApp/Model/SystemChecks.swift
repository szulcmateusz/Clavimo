import Foundation

/// Reads macOS settings that Clavimo's actions depend on. Read-only:
/// Clavimo never changes these settings itself.
enum SystemChecks {
    /// The Mission Control shortcuts used by Clavimo's actions, with the
    /// identifiers macOS uses in `com.apple.symbolichotkeys`.
    enum Shortcut: Int, CaseIterable {
        case missionControl = 32
        case applicationWindows = 33
        case moveLeftASpace = 79
        case moveRightASpace = 81

        var title: String {
            switch self {
            case .missionControl: String(localized: "Mission Control")
            case .applicationWindows: String(localized: "Application windows")
            case .moveLeftASpace: String(localized: "Move left a space")
            case .moveRightASpace: String(localized: "Move right a space")
            }
        }
    }

    /// Shortcuts that are explicitly disabled. Missing entries mean the
    /// macOS default, which is enabled.
    static func disabledShortcuts() -> [Shortcut] {
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        return Shortcut.allCases.filter { shortcut in
            guard let entry = hotkeys["\(shortcut.rawValue)"] as? [String: Any] else { return false }
            return (entry["enabled"] as? Bool) == false || (entry["enabled"] as? Int) == 0
        }
    }

    /// Whether macOS accelerates mouse pointer movement (System Settings >
    /// Mouse > Advanced > Pointer acceleration).
    static var pointerAccelerationEnabled: Bool {
        !UserDefaults.standard.bool(forKey: "com.apple.mouse.linear")
    }
}
