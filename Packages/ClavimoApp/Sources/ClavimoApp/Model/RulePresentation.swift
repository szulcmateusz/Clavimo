import AppKit
import ClavimoCore
import Foundation

/// One visual element of a rule summary.
enum RuleToken: Equatable {
    case key(String, caption: String?)
    case mouse(String)
    case action(String, symbol: String)
    case symbol(String)
    case text(String)
}

extension KeyNames {
    /// A compact keycap label: a glyph for special keys and a caption for
    /// the side of a modifier.
    static func keyCap(for code: UInt16) -> (label: String, caption: String?) {
        let side: [UInt16: (String, String)] = [
            0x37: ("⌘", "L"), 0x36: ("⌘", "R"), 0x3A: ("⌥", "L"), 0x3D: ("⌥", "R"),
            0x3B: ("⌃", "L"), 0x3E: ("⌃", "R"), 0x38: ("⇧", "L"), 0x3C: ("⇧", "R"),
        ]
        if let (glyph, caption) = side[code] {
            return (glyph, String(localized: caption == "L" ? "left" : "right"))
        }
        let glyphs: [UInt16: String] = [
            0x39: "⇪", 0x35: "esc", 0x24: "↩", 0x30: "⇥", 0x31: String(localized: "space"), 0x33: "⌫", 0x75: "⌦",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟", 0x3F: "fn",
        ]
        return (glyphs[code] ?? name(for: code), nil)
    }

    static func shortButtonName(_ number: Int) -> String {
        switch number {
        case 1: String(localized: "Left")
        case 2: String(localized: "Right")
        case 3: String(localized: "Middle")
        default: String(localized: "Button \(number)")
        }
    }
}

extension RuleDraft.Action {
    var symbol: String {
        switch self {
        case .nextWorkspace: "rectangle.righthalf.inset.filled.arrow.right"
        case .previousWorkspace: "rectangle.lefthalf.inset.filled.arrow.left"
        case .missionControl: "rectangle.3.group"
        case .applicationWindows: "macwindow.on.rectangle"
        }
    }

    var localizedTitle: String {
        switch self {
        case .nextWorkspace: String(localized: "Next Space")
        case .previousWorkspace: String(localized: "Previous Space")
        case .missionControl: String(localized: "Mission Control")
        case .applicationWindows: String(localized: "App Windows")
        }
    }
}

extension RuleDraft {
    var modifierTokens: [RuleToken] {
        Modifier.allCases.filter { modifiers.contains($0) }.map { .key($0.symbol, caption: nil) }
    }

    private func key(_ code: UInt16) -> RuleToken {
        let cap = KeyNames.keyCap(for: code)
        return .key(cap.label, caption: cap.caption)
    }

    /// A compact visual summary: trigger, then result.
    var tokens: [RuleToken] {
        switch kind {
        case .swapKeys:
            [key(firstKey), .symbol("arrow.left.arrow.right"), key(secondKey)]
        case .remapKey:
            [key(firstKey), .symbol("arrow.right"), key(secondKey)]
        case .modifierClick:
            modifierTokens + [.text("+"), .mouse(KeyNames.shortButtonName(button)), .symbol("arrow.right"),
                              .action(action.localizedTitle, symbol: action.symbol)]
        case .keyClick:
            [key(firstKey), .text("+"), .mouse(KeyNames.shortButtonName(button)), .symbol("arrow.right"),
             .action(action.localizedTitle, symbol: action.symbol)]
        case .wheel:
            [.mouse(String(localized: "Wheel")), .symbol("arrow.right"),
             .action(wheelSummary, symbol: "arrow.up.and.down")]
        }
    }

    var wheelSummary: String {
        [vertical.localizedSummary.map { String(localized: "Vertical: \($0)") },
         horizontal.localizedSummary.map { String(localized: "Horizontal: \($0)") }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// One sentence that says exactly what the rule does.
    var sentence: String {
        var text: String
        let first = KeyNames.name(for: firstKey)
        let second = KeyNames.name(for: secondKey)
        let button = KeyNames.buttonName(button)
        switch kind {
        case .swapKeys:
            text = String(localized: "\(first) acts as \(second), and \(second) acts as \(first).")
        case .remapKey:
            text = String(localized: "Pressing \(first) sends \(second).")
        case .modifierClick:
            let held = Modifier.allCases.filter { modifiers.contains($0) }.map(\.localizedName).formatted(.list(type: .and))
            text = String(localized: "While you hold \(held), the \(button) runs \(action.localizedTitle). Other clicks work as usual.")
        case .keyClick:
            text = String(localized: "While you hold \(first), the \(button) runs \(action.localizedTitle).")
            switch policy {
            case .boundedWindow:
                text += " " + String(localized: "Otherwise \(first) types normally, up to \(windowMilliseconds) ms later.")
            case .deferredUntilUp:
                text += " " + String(localized: "Otherwise \(first) types when you release it.")
            case .nonConsuming:
                text += " " + String(localized: "\(first) also types its character.")
            }
        case .wheel:
            text = String(localized: "Mouse wheels scroll like this: \(wheelSummary). Trackpads are not changed.")
        }
        if !onlyApps.isEmpty {
            text += " " + String(localized: "Only in \(onlyApps.map(AppNames.name).formatted(.list(type: .or))).")
        }
        if !exceptApps.isEmpty {
            text += " " + String(localized: "Not in \(exceptApps.map(AppNames.name).formatted(.list(type: .or))).")
        }
        if !devices.isEmpty {
            text += " " + String(localized: "Only on \(devices.map(DeviceNames.name).formatted(.list(type: .or))).")
        }
        return text
    }
}

extension RuleDraft.Modifier {
    var localizedName: String {
        switch self {
        case .control: String(localized: "Control")
        case .option: String(localized: "Option")
        case .shift: String(localized: "Shift")
        case .command: String(localized: "Command")
        case .function: String(localized: "Fn")
        }
    }
}

extension RuleDraft.Axis {
    var localizedSummary: String? {
        var parts: [String] = []
        if reverse { parts.append(String(localized: "reversed")) }
        switch mode {
        case .system: break
        case .accelerated: parts.append(String(localized: "speed \(speed.formatted(.number.precision(.fractionLength(1))))×"))
        case .byLines: parts.append(String(localized: "\(lines) lines per notch"))
        case .byPixels: parts.append(String(localized: "\(Int(pixels)) px per notch"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Display names for app bundle identifiers, from installed apps.
enum AppNames {
    static func name(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

/// Display names for device IDs, from devices seen in this session.
/// Written on the main thread when the device list refreshes.
enum DeviceNames {
    nonisolated(unsafe) static var cache: [String: String] = [:]

    static func name(_ id: String) -> String {
        cache[id] ?? id
    }
}
