import ClavimoCore
import Foundation

/// The editable form of one rule, covering every rule type the engine
/// supports. Rules written by hand that do not fit this form are kept in
/// the file untouched and shown as advanced rules.
struct RuleDraft: Equatable {
    /// Scroll settings for one wheel axis.
    struct Axis: Equatable {
        enum Mode: String, CaseIterable, Identifiable {
            case system, accelerated, byLines, byPixels
            var id: String { rawValue }
            var title: String {
                switch self {
                case .system: "System"
                case .accelerated: "Accelerated"
                case .byLines: "By lines"
                case .byPixels: "By pixels"
                }
            }
            var explanation: String {
                switch self {
                case .system: "Distance and acceleration as set in macOS."
                case .accelerated: "The macOS acceleration curve, faster or slower."
                case .byLines: "The same number of lines for every wheel notch, without acceleration."
                case .byPixels: "The same distance in pixels for every wheel notch, without acceleration. Experimental."
                }
            }
        }

        var reverse = false
        var mode: Mode = .system
        var speed = 1.0
        var lines = 3
        var pixels = 60.0

        var changesEvents: Bool { reverse || mode != .system }

        var summary: String? {
            var parts: [String] = []
            if reverse { parts.append("reversed") }
            switch mode {
            case .system: break
            case .accelerated: parts.append("speed \(speed.formatted(.number.precision(.fractionLength(0...1))))x")
            case .byLines: parts.append("\(lines) \(lines == 1 ? "line" : "lines")")
            case .byPixels: parts.append("\(Int(pixels)) px")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        var json: JSONValue {
            var object: [String: JSONValue] = ["reverse": .bool(reverse), "mode": .string(mode.rawValue)]
            switch mode {
            case .system: break
            case .accelerated: object["speedMultiplier"] = .number(speed)
            case .byLines: object["distanceLines"] = .number(Double(lines))
            case .byPixels: object["distancePixels"] = .number(pixels)
            }
            return .object(object)
        }

        init() {}

        init?(json value: JSONValue?) {
            guard let value else { return }
            guard Set(value.keys).isSubset(of: ["reverse", "mode", "speedMultiplier", "distanceLines", "distancePixels"]),
                  let mode = Mode(rawValue: value["mode"]?.string ?? "system") else { return nil }
            self.mode = mode
            reverse = value["reverse"] == .bool(true)
            if let speed = value["speedMultiplier"]?.number { self.speed = speed }
            if let lines = value["distanceLines"]?.int { self.lines = lines }
            if let pixels = value["distancePixels"]?.number { self.pixels = pixels }
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case swapKeys, remapKey, modifierClick, keyClick, wheel
        var id: String { rawValue }

        var title: String {
            switch self {
            case .swapKeys: "Swap two keys"
            case .remapKey: "Remap a key"
            case .modifierClick: "Modifier + mouse button"
            case .keyClick: "Key + mouse button"
            case .wheel: "Mouse wheel direction"
            }
        }
    }

    enum Modifier: String, CaseIterable, Identifiable {
        case control, option, shift, command, function
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            case .function: "fn"
            }
        }
    }

    enum Action: String, CaseIterable, Identifiable {
        case nextWorkspace, previousWorkspace, missionControl, applicationWindows
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nextWorkspace: "Next Space"
            case .previousWorkspace: "Previous Space"
            case .missionControl: "Mission Control"
            case .applicationWindows: "Application Windows"
            }
        }
    }

    enum Policy: String, CaseIterable, Identifiable {
        case boundedWindow, deferredUntilUp, nonConsuming
        var id: String { rawValue }
        var title: String {
            switch self {
            case .boundedWindow: "Short wait, then type normally"
            case .deferredUntilUp: "Wait until the key is released"
            case .nonConsuming: "Type immediately"
            }
        }
        var explanation: String {
            switch self {
            case .boundedWindow: "The key is held back briefly. Clicking within the window triggers the action; otherwise the key types as usual, slightly delayed."
            case .deferredUntilUp: "The key never types by accident, but it types only when released and does not repeat while held."
            case .nonConsuming: "The key types instantly and the action still triggers, but the character also reaches the app."
            }
        }
    }

    var kind: Kind = .swapKeys
    var name = ""
    var profileID = "default"
    var enabled = true
    var priority = 50
    var firstKey: UInt16 = KeyCode.rightCommand.rawValue
    var secondKey: UInt16 = KeyCode.rightOption.rawValue
    var modifiers: Set<Modifier> = [.function]
    var button = 4
    var action: Action = .nextWorkspace
    var policy: Policy = .boundedWindow
    var windowMilliseconds = LeaderPolicy.defaultWindowMilliseconds
    var vertical: Axis = {
        var axis = Axis()
        axis.reverse = true
        return axis
    }()
    var horizontal = Axis()
    var devices: [String] = []
    var onlyApps: [String] = []
    var exceptApps: [String] = []

    var usesProtectedButton: Bool { button <= 2 && (kind == .modifierClick) }

    var suggestedName: String {
        switch kind {
        case .swapKeys:
            "Swap \(KeyNames.name(for: firstKey)) and \(KeyNames.name(for: secondKey))"
        case .remapKey:
            "\(KeyNames.name(for: firstKey)) to \(KeyNames.name(for: secondKey))"
        case .modifierClick:
            "\(modifierText) + \(KeyNames.buttonName(button)): \(action.title)"
        case .keyClick:
            "\(KeyNames.name(for: firstKey)) + \(KeyNames.buttonName(button)): \(action.title)"
        case .wheel:
            "Mouse wheel: " + [vertical.summary.map { "vertical \($0)" }, horizontal.summary.map { "horizontal \($0)" }]
                .compactMap { $0 }.joined(separator: "; ")
        }
    }

    var modifierText: String {
        Modifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined(separator: " ")
    }

    var displayName: String { name.isEmpty ? suggestedName : name }

    /// Problems that make the draft unsavable.
    var validationMessage: String? {
        switch kind {
        case .swapKeys, .remapKey:
            if firstKey == secondKey { return "Choose two different keys." }
            let unsupported: Set<UInt16> = [KeyCode.capsLock.rawValue, KeyCode.function.rawValue]
            if unsupported.contains(firstKey) || unsupported.contains(secondKey) {
                return "Caps Lock and Fn cannot be remapped yet."
            }
        case .modifierClick:
            if modifiers.isEmpty { return "Choose at least one modifier." }
        case .keyClick:
            if KeyCode(firstKey).modifierKey != nil || firstKey == KeyCode.capsLock.rawValue || firstKey == KeyCode.function.rawValue {
                return "Use \"Modifier + mouse button\" for modifier keys."
            }
            if button <= 2 { return "Letter key chords cannot use the left or right button." }
            if !devices.isEmpty { return "Key + mouse button rules cannot be limited to a device." }
        case .wheel:
            if !vertical.changesEvents && !horizontal.changesEvents { return "Change at least one direction or mode." }
            if !devices.isEmpty { return "Scrolling cannot be limited to a device yet." }
            if onlyApps.count > 1 || !exceptApps.isEmpty { return "Scrolling rules can be limited to one app only." }
        }
        return nil
    }
}

// MARK: - JSON conversion

extension RuleDraft {
    private static func key(_ code: UInt16) -> JSONValue {
        .object(["codeNamespace": .string("macVirtualKeyCode"), "code": .number(Double(code))])
    }

    private static func code(_ value: JSONValue?) -> UInt16? {
        guard value?["codeNamespace"]?.string == "macVirtualKeyCode", let code = value?["code"]?.int,
              (0...Int(UInt16.max)).contains(code) else { return nil }
        return UInt16(code)
    }

    private var conditionValues: [JSONValue] {
        devices.map { .object(["kind": .string("physicalDeviceIs"), "deviceId": .string($0)]) }
            + onlyApps.map { .object(["kind": .string("appIs"), "bundleId": .string($0)]) }
            + exceptApps.map { .object(["kind": .string("appIsNot"), "bundleId": .string($0)]) }
    }

    func makeRule(id: String, order: Int) -> ConfigDocument.Rule {
        var behavior = ConfigDocument.Behavior(consumeTrigger: true, fireOn: "down", repeat: "once")
        let trigger: JSONValue
        let actionValue: JSONValue
        switch kind {
        case .swapKeys:
            trigger = .object(["kind": .string("keyPair"), "first": Self.key(firstKey), "second": Self.key(secondKey)])
            actionValue = .object(["kind": .string("swapKeys"), "sideMode": .string("asSpecified")])
            behavior.repeat = "onAutorepeat"
        case .remapKey:
            trigger = .object(["kind": .string("key"), "key": Self.key(firstKey)])
            actionValue = .object(["kind": .string("sendKey"), "key": Self.key(secondKey)])
            behavior.repeat = "onAutorepeat"
        case .modifierClick:
            let names = Modifier.allCases.filter { modifiers.contains($0) }.map { JSONValue.string($0.rawValue) }
            trigger = .object(["kind": .string("modifierChord"), "requiredModifiers": .array(names), "mouseButton": .number(Double(button))])
            actionValue = .object(["kind": .string(action.rawValue)])
            if button <= 2 { behavior.allowProtectedButton = true }
        case .keyClick:
            trigger = .object([
                "kind": .string("keyMouseChord"), "leaderKey": Self.key(firstKey),
                "mouseButton": .number(Double(button)), "order": .string("leaderThenMouse"),
            ])
            actionValue = .object(["kind": .string(action.rawValue)])
            behavior.leaderPolicy = policy.rawValue
            if policy == .boundedWindow { behavior.leaderWindowMs = windowMilliseconds }
        case .wheel:
            preconditionFailure("wheel drafts are stored as device settings")
        }
        return ConfigDocument.Rule(
            id: id, name: displayName, enabled: enabled, priority: priority, profileId: profileID,
            trigger: trigger, conditions: conditionValues, action: actionValue, behavior: behavior,
            ui: .object(["order": .number(Double(order))])
        )
    }

    func makeDeviceSetting(id: String) -> JSONValue {
        var scope: [String: JSONValue] = ["deviceClass": .string("mouse")]
        if let app = onlyApps.first { scope["appBundleId"] = .string(app) }
        return .object([
            "id": .string(id), "name": .string(displayName), "enabled": .bool(enabled),
            "profileId": .string(profileID), "priority": .number(Double(priority)),
            "scope": .object(scope),
            "scrolling": .object(["vertical": vertical.json, "horizontal": horizontal.json]),
        ])
    }

    /// Returns nil when the rule uses features the form cannot represent.
    init?(rule: ConfigDocument.Rule) {
        name = rule.name
        profileID = rule.profileId
        enabled = rule.enabled
        priority = rule.priority
        for condition in rule.conditions {
            switch condition["kind"]?.string {
            case "physicalDeviceIs": guard let id = condition["deviceId"]?.string else { return nil }; devices.append(id)
            case "appIs": guard let id = condition["bundleId"]?.string else { return nil }; onlyApps.append(id)
            case "appIsNot": guard let id = condition["bundleId"]?.string else { return nil }; exceptApps.append(id)
            default: return nil
            }
        }
        let trigger = rule.trigger
        switch (trigger["kind"]?.string, rule.action["kind"]?.string) {
        case ("keyPair", "swapKeys"):
            guard let first = Self.code(trigger["first"]), let second = Self.code(trigger["second"]),
                  rule.action["sideMode"]?.string != "both" else { return nil }
            kind = .swapKeys; firstKey = first; secondKey = second
        case ("key", "sendKey"):
            guard let from = Self.code(trigger["key"]), let to = Self.code(rule.action["key"]) else { return nil }
            kind = .remapKey; firstKey = from; secondKey = to
        case let ("modifierChord", actionKind?):
            guard trigger["key"] == nil, let number = trigger["mouseButton"]?.int, let action = Action(rawValue: actionKind) else { return nil }
            var set: Set<Modifier> = []
            for item in trigger["requiredModifiers"]?.array ?? [] {
                guard let modifier = item.string.flatMap(Modifier.init(rawValue:)) else { return nil }
                set.insert(modifier)
            }
            kind = .modifierClick; modifiers = set; button = number; self.action = action
        case let ("keyMouseChord", actionKind?):
            guard let leader = Self.code(trigger["leaderKey"]), let number = trigger["mouseButton"]?.int,
                  let action = Action(rawValue: actionKind),
                  let policy = rule.behavior.leaderPolicy.flatMap(Policy.init(rawValue:)) else { return nil }
            kind = .keyClick; firstKey = leader; button = number; self.action = action; self.policy = policy
            windowMilliseconds = rule.behavior.leaderWindowMs ?? LeaderPolicy.defaultWindowMilliseconds
        default:
            return nil
        }
    }

    init?(deviceSetting value: JSONValue) {
        guard value["scope"]?["deviceClass"]?.string == "mouse", value["pointer"] == nil,
              value["scope"]?["vendorId"] == nil, value["scope"]?["displayId"] == nil else { return nil }
        guard let vertical = Axis(json: value["scrolling"]?["vertical"]),
              let horizontal = Axis(json: value["scrolling"]?["horizontal"]) else { return nil }
        kind = .wheel
        profileID = value["profileId"]?.string ?? "default"
        self.vertical = vertical
        self.horizontal = horizontal
        name = value["name"]?.string ?? ""
        enabled = value["enabled"] == .bool(true)
        priority = value["priority"]?.int ?? 50
        if let app = value["scope"]?["appBundleId"]?.string { onlyApps = [app] }
    }

}

extension JSONValue {
    var keys: [String] {
        if case let .object(object) = self { return Array(object.keys) }
        return []
    }
}
