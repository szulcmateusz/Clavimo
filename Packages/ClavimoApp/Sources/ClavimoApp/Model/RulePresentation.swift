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
    /// A small trackpad drawing with the fingers of a gesture.
    case trackpad(TrackpadGlyphModel, title: String)
}

/// What a trackpad drawing shows.
struct TrackpadGlyphModel: Equatable {
    var fingers: Int = 0
    var arrow: GestureEvent.Direction?
    var corner: TrackpadCorner?
    var tipTapSide: GestureEvent.Side?
    /// A physical click rather than a light tap.
    var pressed = false

    init(_ trigger: TrackpadTrigger) {
        switch trigger {
        case let .gesture(.tap(count)): fingers = count
        case let .gesture(.tipTap(side)): fingers = 2; tipTapSide = side
        case let .gesture(.swipe(count, direction)): fingers = count; arrow = direction
        case let .click(count): fingers = count; pressed = true
        case let .cornerClick(place): fingers = 1; corner = place; pressed = true
        }
    }
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
            return (glyph, caption == "L" ? String(localized: "left") : String(localized: "right"))
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
        case .middleClick: "computermouse"
        case .backClick: "chevron.backward.circle"
        case .forwardClick: "chevron.forward.circle"
        case .shortcut: "command"
        case .launchApp: "app"
        case .media: "playpause"
        }
    }

    var localizedTitle: String {
        switch self {
        case .nextWorkspace: String(localized: "Next Space")
        case .previousWorkspace: String(localized: "Previous Space")
        case .missionControl: String(localized: "Mission Control")
        case .applicationWindows: String(localized: "App Windows")
        case .middleClick: String(localized: "Middle click")
        case .backClick: String(localized: "Back")
        case .forwardClick: String(localized: "Forward")
        case .shortcut: String(localized: "Shortcut")
        case .launchApp: String(localized: "Open app")
        case .media: String(localized: "Media key")
        }
    }
}

extension MediaKey {
    var symbol: String {
        switch self {
        case .playPause: "playpause"
        case .nextTrack: "forward"
        case .previousTrack: "backward"
        case .volumeUp: "speaker.wave.3"
        case .volumeDown: "speaker.wave.1"
        case .mute: "speaker.slash"
        case .brightnessUp: "sun.max"
        case .brightnessDown: "sun.min"
        }
    }
}

extension RuleDraft {
    var modifierTokens: [RuleToken] {
        Modifier.allCases.filter { modifiers.contains($0) }.map { .key($0.symbol, caption: nil) }
    }

    var actionToken: RuleToken {
        .action(actionTitle, symbol: action == .media ? mediaKey.symbol : action.symbol)
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
            modifierTokens + [.text("+"), .mouse(KeyNames.shortButtonName(button)), .symbol("arrow.right"), actionToken]
        case .keyClick:
            [key(firstKey), .text("+"), .mouse(KeyNames.shortButtonName(button)), .symbol("arrow.right"), actionToken]
        case .trackpadGesture, .trackpadClick:
            Modifier.allCases.filter { trackpadModifiers.contains($0) }.flatMap { [RuleToken.key($0.symbol, caption: nil), .text("+")] }
                + [.trackpad(TrackpadGlyphModel(trackpadTrigger), title: trackpadTriggerTitle), .symbol("arrow.right"), actionToken]
        case .wheel:
            [.mouse(String(localized: "Wheel")), .symbol("arrow.right"),
             .action(wheelSummary, symbol: "arrow.up.and.down")]
        case .trackpadScroll:
            [.trackpad(TrackpadGlyphModel(.gesture(.swipe(fingers: 2, .up))), title: String(localized: "Trackpad")), .symbol("arrow.right"),
             .action(trackpadScrollSummary, symbol: "arrow.up.and.down")]
        }
    }

    var trackpadScrollSummary: String {
        var parts: [String] = []
        if trackpadScroll.reverseVertical && trackpadScroll.reverseHorizontal {
            parts.append(String(localized: "reversed"))
        } else if trackpadScroll.reverseVertical {
            parts.append(String(localized: "vertical reversed"))
        } else if trackpadScroll.reverseHorizontal {
            parts.append(String(localized: "horizontal reversed"))
        }
        if trackpadScroll.speed != 1 {
            parts.append(String(localized: "speed \(trackpadScroll.speed.formatted(.number.precision(.fractionLength(0...2))))×"))
        }
        if !trackpadScroll.momentum { parts.append(String(localized: "no momentum")) }
        return parts.isEmpty ? String(localized: "as in macOS") : parts.joined(separator: ", ")
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
            text = String(localized: "While you hold \(held), the \(button) runs \(actionTitle). Other clicks work as usual.")
        case .keyClick:
            text = String(localized: "While you hold \(first), the \(button) runs \(actionTitle).")
            switch policy {
            case .boundedWindow:
                text += " " + String(localized: "Otherwise \(first) types normally, up to \(windowMilliseconds) ms later.")
            case .deferredUntilUp:
                text += " " + String(localized: "Otherwise \(first) types when you release it.")
            case .nonConsuming:
                text += " " + String(localized: "\(first) also types its character.")
            }
        case .trackpadGesture, .trackpadClick:
            let held = Modifier.allCases.filter { trackpadModifiers.contains($0) }.map(\.localizedName).formatted(.list(type: .and))
            text = trackpadModifiers.isEmpty
                ? String(localized: "\(trackpadTriggerTitle) runs \(actionTitle).")
                : String(localized: "While you hold \(held), \(trackpadTriggerTitle.lowercasedFirst) runs \(actionTitle).")
            if kind == .trackpadClick {
                text += " " + String(localized: "The click itself does not reach the app.")
            }
        case .wheel:
            text = String(localized: "Mouse wheels scroll like this: \(wheelSummary). Trackpads keep their own setting.")
        case .trackpadScroll:
            text = String(localized: "Trackpads scroll like this: \(trackpadScrollSummary). Mouse wheels keep their own setting.")
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
        // Key names such as "prawy Command" can start the sentence.
        return text.prefix(1).localizedUppercase + text.dropFirst()
    }
}

extension String {
    /// "Tap with 3 fingers" -> "tap with 3 fingers", for use mid-sentence.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
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
        case .smoothed: parts.append(String(localized: "smooth, \(Int(pixels)) px per notch"))
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
