import ClavimoCore
import Foundation

/// The editable form of one rule, covering every rule type the engine
/// supports. Rules written by hand that do not fit this form are kept in
/// the file untouched and shown as advanced rules.
struct RuleDraft: Equatable {
    /// Scroll settings for one wheel axis.
    struct Axis: Equatable {
        enum Mode: String, CaseIterable, Identifiable {
            case system, accelerated, byLines, byPixels, smoothed
            var id: String { rawValue }
        }

        var reverse = false
        var mode: Mode = .system
        var speed = 1.0
        var lines = 3
        var pixels = 60.0
        /// Smooth scrolling animation time in seconds.
        var duration = 0.25

        var changesEvents: Bool { reverse || mode != .system }

        var json: JSONValue {
            var object: [String: JSONValue] = ["reverse": .bool(reverse), "mode": .string(mode.rawValue)]
            switch mode {
            case .system: break
            case .accelerated: object["speedMultiplier"] = .number(speed)
            case .byLines: object["distanceLines"] = .number(Double(lines))
            case .byPixels: object["distancePixels"] = .number(pixels)
            case .smoothed:
                object["distancePixels"] = .number(pixels)
                object["smoothing"] = .object(["response": .number(duration)])
            }
            return .object(object)
        }

        init() {}

        init?(json value: JSONValue?) {
            guard let value else { return }
            guard Set(value.keys).isSubset(of: ["reverse", "mode", "speedMultiplier", "distanceLines", "distancePixels", "smoothing"]),
                  let mode = Mode(rawValue: value["mode"]?.string ?? "system") else { return nil }
            self.mode = mode
            reverse = value["reverse"] == .bool(true)
            if let speed = value["speedMultiplier"]?.number { self.speed = speed }
            if let lines = value["distanceLines"]?.int { self.lines = lines }
            if let pixels = value["distancePixels"]?.number { self.pixels = pixels }
            if let duration = value["smoothing"]?["response"]?.number { self.duration = duration }
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case swapKeys, remapKey, modifierClick, keyClick, trackpadGesture, trackpadClick, wheel, trackpadScroll
        var id: String { rawValue }

        var title: String {
            switch self {
            case .swapKeys: String(localized: "Swap two keys")
            case .remapKey: String(localized: "Remap a key")
            case .modifierClick: String(localized: "Mouse button, alone or with modifiers")
            case .keyClick: String(localized: "Key + mouse button")
            case .trackpadGesture: String(localized: "Trackpad gesture")
            case .trackpadClick: String(localized: "Trackpad click")
            case .wheel: String(localized: "Mouse wheel direction")
            case .trackpadScroll: String(localized: "Trackpad scrolling")
            }
        }

        /// Scroll settings are stored as device settings and edited in
        /// their own panes, not in the rules list.
        var isSetting: Bool { self == .wheel || self == .trackpadScroll }
        var isTrackpad: Bool { self == .trackpadGesture || self == .trackpadClick }
        var hasAction: Bool { self == .modifierClick || self == .keyClick || isTrackpad }
    }

    enum Gesture: String, CaseIterable, Identifiable {
        case tap, tipTap, swipe, rotate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tap: String(localized: "Tap")
            case .tipTap: String(localized: "Tip tap")
            case .swipe: String(localized: "Swipe")
            case .rotate: String(localized: "Rotate")
            }
        }

        var fingerChoices: ClosedRange<Int> {
            switch self {
            case .tap: TrackpadTrigger.tapFingers
            case .swipe: TrackpadTrigger.swipeFingers
            case .tipTap, .rotate: 2...2
            }
        }
    }

    enum ClickPlace: String, CaseIterable, Identifiable {
        case fingers, corner
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fingers: String(localized: "With several fingers")
            case .corner: String(localized: "In a corner")
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
        case middleClick, backClick, forwardClick, shortcut, launchApp, media
        case openCompass, menuItem
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nextWorkspace: String(localized: "Next Space")
            case .previousWorkspace: String(localized: "Previous Space")
            case .missionControl: String(localized: "Mission Control")
            case .applicationWindows: String(localized: "Application Windows")
            case .middleClick: String(localized: "Middle click")
            case .backClick: String(localized: "Back (button 4)")
            case .forwardClick: String(localized: "Forward (button 5)")
            case .shortcut: String(localized: "Keyboard shortcut")
            case .launchApp: String(localized: "Open an app")
            case .media: String(localized: "Media key")
            case .openCompass: String(localized: "Open a compass")
            case .menuItem: String(localized: "Choose an app menu item")
            }
        }

        /// Actions stored as plain `{"kind": rawValue}`.
        var isSimple: Bool { [.nextWorkspace, .previousWorkspace, .missionControl, .applicationWindows].contains(self) }
    }

    enum Policy: String, CaseIterable, Identifiable {
        case boundedWindow, deferredUntilUp, nonConsuming
        var id: String { rawValue }
        var title: String {
            switch self {
            case .boundedWindow: String(localized: "Short wait, then type normally")
            case .deferredUntilUp: String(localized: "Wait until the key is released")
            case .nonConsuming: String(localized: "Type immediately")
            }
        }
        var explanation: String {
            switch self {
            case .boundedWindow: String(localized: "The key is held back briefly. Clicking within the window triggers the action; otherwise the key types as usual, slightly delayed.")
            case .deferredUntilUp: String(localized: "The key never types by accident, but it types only when released and does not repeat while held.")
            case .nonConsuming: String(localized: "The key types instantly and the action still triggers, but the character also reaches the app.")
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
    var shortcutKey: UInt16 = 0x11 // T
    var shortcutModifiers: Set<Modifier> = [.command]
    var appBundleID = ""
    var mediaKey: MediaKey = .playPause
    var compassID = ""
    /// Menu titles from the menu bar down, e.g. ["File", "New Tab"].
    var menuPath: [String] = []
    var gesture: Gesture = .tap
    var fingers = 3
    var direction: GestureEvent.Direction = .left
    var side: GestureEvent.Side = .right
    var rotation: GestureEvent.Rotation = .clockwise
    /// Nil for the whole trackpad. Gestures only.
    var zone: TrackpadZone?
    var clickPlace: ClickPlace = .fingers
    var corner: TrackpadCorner = .topRight
    var trackpadModifiers: Set<Modifier> = []
    var trackpadScroll = TrackpadScrollSettings(reverseVertical: true)
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
            String(localized: "Swap \(KeyNames.name(for: firstKey)) and \(KeyNames.name(for: secondKey))")
        case .remapKey:
            String(localized: "\(KeyNames.name(for: firstKey)) to \(KeyNames.name(for: secondKey))")
        case .modifierClick:
            modifiers.isEmpty
                ? String(localized: "\(KeyNames.buttonName(button)): \(actionTitle)")
                : String(localized: "\(modifierText) + \(KeyNames.buttonName(button)): \(actionTitle)")
        case .keyClick:
            String(localized: "\(KeyNames.name(for: firstKey)) + \(KeyNames.buttonName(button)): \(actionTitle)")
        case .trackpadGesture, .trackpadClick:
            trackpadModifiers.isEmpty
                ? String(localized: "\(trackpadTriggerTitle): \(actionTitle)")
                : String(localized: "\(trackpadModifierText) + \(trackpadTriggerTitle): \(actionTitle)")
        case .wheel:
            String(localized: "Mouse wheel")
        case .trackpadScroll:
            String(localized: "Trackpad scrolling")
        }
    }

    var trackpadModifierText: String {
        Modifier.allCases.filter { trackpadModifiers.contains($0) }.map(\.symbol).joined(separator: " ")
    }

    var trackpadTrigger: TrackpadTrigger {
        if kind == .trackpadClick {
            return clickPlace == .corner ? .cornerClick(corner) : .click(fingers: min(max(fingers, 3), 5))
        }
        switch gesture {
        case .tap: return .gesture(.tap(fingers: fingers))
        case .tipTap: return .gesture(.tipTap(side))
        case .swipe: return .gesture(.swipe(fingers: fingers, direction))
        case .rotate: return .gesture(.rotate(rotation))
        }
    }

    var trackpadTriggerTitle: String { GestureNames.title(trackpadTrigger) }

    /// The action as the engine runs it.
    var actionCommand: ActionCommand {
        switch action {
        case .nextWorkspace: .nextWorkspace
        case .previousWorkspace: .previousWorkspace
        case .missionControl: .missionControl
        case .applicationWindows: .applicationWindows
        case .middleClick: .click(.middle)
        case .backClick: .click(.button4)
        case .forwardClick: .click(.button5)
        case .shortcut: .shortcut(KeyCode(shortcutKey), Modifier.generic(shortcutModifiers))
        case .launchApp: .launchApp(appBundleID)
        case .media: .media(mediaKey)
        case .openCompass: .openCompass(compassID)
        case .menuItem: .menuItem(menuPath)
        }
    }

    /// Names the action including its details, such as the shortcut keys.
    var actionTitle: String {
        switch action {
        case .shortcut:
            (Modifier.allCases.filter { shortcutModifiers.contains($0) }.map(\.symbol) + [KeyNames.keyCap(for: shortcutKey).label])
                .joined()
        case .launchApp:
            appBundleID.isEmpty ? action.title : String(localized: "Open \(AppNames.name(appBundleID))")
        case .media:
            mediaKey.localizedTitle
        case .openCompass:
            String(localized: "Compass")
        case .menuItem:
            menuPath.isEmpty ? action.title : menuPath.joined(separator: " › ")
        default:
            action.localizedTitle
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
            if firstKey == secondKey { return String(localized: "Choose two different keys.") }
            if firstKey == KeyCode.function.rawValue || secondKey == KeyCode.function.rawValue {
                return String(localized: "Fn cannot be remapped.")
            }
            if secondKey == KeyCode.capsLock.rawValue || (kind == .swapKeys && firstKey == KeyCode.capsLock.rawValue) {
                return String(localized: "Caps Lock can be remapped to another key, but no key can type Caps Lock. Use the Keyboard pane to make Caps Lock toggle on a tap or double tap.")
            }
        case .modifierClick:
            if modifiers.isEmpty, button <= 2 {
                return String(localized: "The left and right buttons need at least one modifier. Other buttons can work alone.")
            }
        case .keyClick:
            if KeyCode(firstKey).modifierKey != nil || firstKey == KeyCode.capsLock.rawValue || firstKey == KeyCode.function.rawValue {
                return String(localized: "Use \"Modifier + mouse button\" for modifier keys.")
            }
            if button <= 2 { return String(localized: "Letter key chords cannot use the left or right button.") }
            if !devices.isEmpty { return String(localized: "Key + mouse button rules cannot be limited to a device.") }
        case .trackpadGesture, .trackpadClick:
            if trackpadTrigger == .gesture(.tap(fingers: 2)), trackpadModifiers.isEmpty {
                return String(localized: "A two-finger tap is the macOS secondary click. Add a modifier, such as Fn.")
            }
        case .trackpadScroll:
            if !trackpadScroll.changesEvents { return String(localized: "Change at least one setting.") }
            if onlyApps.count > 1 || !exceptApps.isEmpty { return String(localized: "Scrolling rules can be limited to one app only.") }
        case .wheel:
            if !vertical.changesEvents && !horizontal.changesEvents { return String(localized: "Change at least one direction or mode.") }
            if !devices.isEmpty { return String(localized: "Scrolling cannot be limited to a device yet.") }
            if onlyApps.count > 1 || !exceptApps.isEmpty { return String(localized: "Scrolling rules can be limited to one app only.") }
        }
        if kind.hasAction, action == .launchApp, appBundleID.isEmpty {
            return String(localized: "Choose the app to open.")
        }
        if kind.hasAction, let message = actionValidationMessage { return message }
        return nil
    }

    /// Problems with the action alone, shared with keyboard rules and compass slots.
    var actionValidationMessage: String? {
        switch action {
        case .launchApp where appBundleID.isEmpty: String(localized: "Choose the app to open.")
        case .openCompass where compassID.isEmpty: String(localized: "Choose a compass. Add one in the Compass pane first.")
        case .menuItem where menuPath.isEmpty: String(localized: "Choose the menu item.")
        default: nil
        }
    }
}

extension RuleDraft.Modifier {
    static func generic(_ set: Set<Self>) -> GenericModifiers {
        var result: GenericModifiers = []
        for modifier in set {
            switch modifier {
            case .control: result.insert(.control)
            case .option: result.insert(.option)
            case .shift: result.insert(.shift)
            case .command: result.insert(.command)
            case .function: result.insert(.function)
            }
        }
        return result
    }
}

extension MediaKey {
    var localizedTitle: String {
        switch self {
        case .playPause: String(localized: "Play or pause")
        case .nextTrack: String(localized: "Next track")
        case .previousTrack: String(localized: "Previous track")
        case .volumeUp: String(localized: "Volume up")
        case .volumeDown: String(localized: "Volume down")
        case .mute: String(localized: "Mute")
        case .brightnessUp: String(localized: "Brightness up")
        case .brightnessDown: String(localized: "Brightness down")
        }
    }
}

// MARK: - JSON conversion

extension RuleDraft {
    static func key(_ code: UInt16) -> JSONValue {
        .object(["codeNamespace": .string("macVirtualKeyCode"), "code": .number(Double(code))])
    }

    static func code(_ value: JSONValue?) -> UInt16? {
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
        case .modifierClick where modifiers.isEmpty:
            trigger = .object(["kind": .string("mouseButton"), "mouseButton": .number(Double(button))])
            actionValue = actionJSON
        case .modifierClick:
            trigger = .object(["kind": .string("modifierChord"), "requiredModifiers": Self.modifierNames(modifiers),
                               "mouseButton": .number(Double(button))])
            actionValue = actionJSON
            if button <= 2 { behavior.allowProtectedButton = true }
        case .keyClick:
            trigger = .object([
                "kind": .string("keyMouseChord"), "leaderKey": Self.key(firstKey),
                "mouseButton": .number(Double(button)), "order": .string("leaderThenMouse"),
            ])
            actionValue = actionJSON
            behavior.leaderPolicy = policy.rawValue
            if policy == .boundedWindow { behavior.leaderWindowMs = windowMilliseconds }
        case .trackpadGesture, .trackpadClick:
            var object: [String: JSONValue] = ["requiredModifiers": Self.modifierNames(trackpadModifiers)]
            switch trackpadTrigger {
            case let .gesture(.tap(count)):
                object["kind"] = .string("trackpadGesture")
                object["gesture"] = .string("tap")
                object["fingers"] = .number(Double(count))
            case let .gesture(.tipTap(side)):
                object["kind"] = .string("trackpadGesture")
                object["gesture"] = .string("tipTap")
                object["side"] = .string(side.rawValue)
            case let .gesture(.swipe(count, direction)):
                object["kind"] = .string("trackpadGesture")
                object["gesture"] = .string("swipe")
                object["fingers"] = .number(Double(count))
                object["direction"] = .string(direction.rawValue)
            case let .gesture(.rotate(turn)):
                object["kind"] = .string("trackpadGesture")
                object["gesture"] = .string("rotate")
                object["direction"] = .string(turn.rawValue)
            case let .click(count):
                object["kind"] = .string("trackpadClick")
                object["fingers"] = .number(Double(count))
            case let .cornerClick(corner):
                object["kind"] = .string("trackpadClick")
                object["corner"] = .string(corner.rawValue)
            }
            if kind == .trackpadGesture, let zone { object["zone"] = .string(zone.rawValue) }
            trigger = .object(object)
            actionValue = actionJSON
        case .wheel, .trackpadScroll:
            preconditionFailure("scroll drafts are stored as device settings")
        }
        return ConfigDocument.Rule(
            id: id, name: displayName, enabled: enabled, priority: priority, profileId: profileID,
            trigger: trigger, conditions: conditionValues, action: actionValue, behavior: behavior,
            ui: .object(["order": .number(Double(order))])
        )
    }

    static func modifierNames(_ set: Set<Modifier>) -> JSONValue {
        .array(Modifier.allCases.filter { set.contains($0) }.map { .string($0.rawValue) })
    }

    var actionJSON: JSONValue {
        switch action {
        case .nextWorkspace, .previousWorkspace, .missionControl, .applicationWindows:
            .object(["kind": .string(action.rawValue)])
        case .middleClick: .object(["kind": .string("mouseClick"), "mouseButton": .number(3)])
        case .backClick: .object(["kind": .string("mouseClick"), "mouseButton": .number(4)])
        case .forwardClick: .object(["kind": .string("mouseClick"), "mouseButton": .number(5)])
        case .shortcut:
            .object(["kind": .string("sendShortcut"), "key": Self.key(shortcutKey), "modifiers": Self.modifierNames(shortcutModifiers)])
        case .launchApp: .object(["kind": .string("launchApp"), "bundleId": .string(appBundleID)])
        case .media: .object(["kind": .string("mediaKey"), "key": .string(mediaKey.rawValue)])
        case .openCompass: .object(["kind": .string("openCompass"), "compassId": .string(compassID)])
        case .menuItem: .object(["kind": .string("menuItem"), "path": .array(menuPath.map { .string($0) })])
        }
    }

    /// Reads an action the form can show; false when it cannot.
    mutating func readAction(_ value: JSONValue) -> Bool {
        guard let kind = value["kind"]?.string else { return false }
        if let simple = Action(rawValue: kind), simple.isSimple {
            action = simple
            return true
        }
        switch kind {
        case "mouseClick":
            switch value["mouseButton"]?.int {
            case 3: action = .middleClick
            case 4: action = .backClick
            case 5: action = .forwardClick
            default: return false
            }
        case "sendShortcut":
            guard let key = Self.code(value["key"]), let set = Self.modifierSet(value["modifiers"]) else { return false }
            action = .shortcut
            shortcutKey = key
            shortcutModifiers = set
        case "launchApp":
            guard let id = value["bundleId"]?.string, !id.isEmpty else { return false }
            action = .launchApp
            appBundleID = id
        case "mediaKey":
            guard let key = value["key"]?.string.flatMap(MediaKey.init(rawValue:)) else { return false }
            action = .media
            mediaKey = key
        case "openCompass":
            guard let id = value["compassId"]?.string, !id.isEmpty else { return false }
            action = .openCompass
            compassID = id
        case "menuItem":
            let path = (value["path"]?.array ?? []).compactMap(\.string)
            guard !path.isEmpty else { return false }
            action = .menuItem
            menuPath = path
        default:
            return false
        }
        return true
    }

    static func modifierSet(_ value: JSONValue?) -> Set<Modifier>? {
        var set: Set<Modifier> = []
        for item in value?.array ?? [] {
            guard let modifier = item.string.flatMap(Modifier.init(rawValue:)) else { return nil }
            set.insert(modifier)
        }
        return set
    }

    func makeDeviceSetting(id: String) -> JSONValue {
        var scope: [String: JSONValue] = ["deviceClass": .string(kind == .trackpadScroll ? "trackpad" : "mouse")]
        if let app = onlyApps.first { scope["appBundleId"] = .string(app) }
        let scrolling: JSONValue
        if kind == .trackpadScroll {
            let speed = trackpadScroll.speed
            func axis(_ reverse: Bool) -> JSONValue {
                var object: [String: JSONValue] = ["reverse": .bool(reverse), "mode": .string(speed == 1 ? "system" : "accelerated")]
                if speed != 1 { object["speedMultiplier"] = .number(speed) }
                return .object(object)
            }
            scrolling = .object([
                "vertical": axis(trackpadScroll.reverseVertical),
                "horizontal": axis(trackpadScroll.reverseHorizontal),
                "momentum": .bool(trackpadScroll.momentum),
            ])
        } else {
            scrolling = .object(["vertical": vertical.json, "horizontal": horizontal.json])
        }
        return .object([
            "id": .string(id), "name": .string(displayName), "enabled": .bool(enabled),
            "profileId": .string(profileID), "priority": .number(Double(priority)),
            "scope": .object(scope),
            "scrolling": scrolling,
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
        case ("mouseButton", _):
            guard let number = trigger["mouseButton"]?.int, number >= 3, readAction(rule.action),
                  trigger["phase"] == nil || trigger["phase"]?.string == "down",
                  let set = Self.modifierSet(trigger["requiredModifiers"]) else { return nil }
            kind = .modifierClick; modifiers = set; button = number
        case ("modifierChord", _):
            guard trigger["key"] == nil, let number = trigger["mouseButton"]?.int, readAction(rule.action),
                  let set = Self.modifierSet(trigger["requiredModifiers"]) else { return nil }
            kind = .modifierClick; modifiers = set; button = number
        case ("keyMouseChord", _):
            guard let leader = Self.code(trigger["leaderKey"]), let number = trigger["mouseButton"]?.int, readAction(rule.action),
                  let policy = rule.behavior.leaderPolicy.flatMap(Policy.init(rawValue:)) else { return nil }
            kind = .keyClick; firstKey = leader; button = number; self.policy = policy
            windowMilliseconds = rule.behavior.leaderWindowMs ?? LeaderPolicy.defaultWindowMilliseconds
        case ("trackpadGesture", _), ("trackpadClick", _):
            guard devices.isEmpty, readAction(rule.action), let set = Self.modifierSet(trigger["requiredModifiers"]),
                  readTrackpadTrigger(trigger) else { return nil }
            trackpadModifiers = set
        default:
            return nil
        }
    }

    private mutating func readTrackpadTrigger(_ trigger: JSONValue) -> Bool {
        let count = trigger["fingers"]?.int
        if trigger["kind"]?.string == "trackpadClick" {
            kind = .trackpadClick
            if let name = trigger["corner"]?.string {
                guard let corner = TrackpadCorner(rawValue: name) else { return false }
                clickPlace = .corner
                self.corner = corner
            } else {
                guard let count, TrackpadTrigger.clickFingers.contains(count) else { return false }
                clickPlace = .fingers
                fingers = count
            }
            return true
        }
        kind = .trackpadGesture
        guard let gesture = trigger["gesture"]?.string.flatMap(Gesture.init(rawValue:)) else { return false }
        self.gesture = gesture
        switch gesture {
        case .tap, .swipe:
            guard let count, gesture.fingerChoices.contains(count) else { return false }
            fingers = count
            if gesture == .swipe {
                guard let direction = trigger["direction"]?.string.flatMap(GestureEvent.Direction.init(rawValue:)) else { return false }
                self.direction = direction
            }
        case .tipTap:
            guard let side = trigger["side"]?.string.flatMap(GestureEvent.Side.init(rawValue:)) else { return false }
            self.side = side
        case .rotate:
            guard count == nil || count == 2,
                  let turn = trigger["direction"]?.string.flatMap(GestureEvent.Rotation.init(rawValue:)) else { return false }
            rotation = turn
            fingers = 2
        }
        if let name = trigger["zone"]?.string {
            guard let zone = TrackpadZone(rawValue: name) else { return false }
            self.zone = zone
        }
        return true
    }

    init?(deviceSetting value: JSONValue) {
        let deviceClass = value["scope"]?["deviceClass"]?.string
        guard deviceClass == "mouse" || deviceClass == "trackpad", value["pointer"] == nil,
              value["scope"]?["vendorId"] == nil, value["scope"]?["displayId"] == nil else { return nil }
        guard let vertical = Axis(json: value["scrolling"]?["vertical"]),
              let horizontal = Axis(json: value["scrolling"]?["horizontal"]) else { return nil }
        if deviceClass == "trackpad" {
            let modes: [Axis.Mode] = [.system, .accelerated]
            guard modes.contains(vertical.mode), modes.contains(horizontal.mode) else { return nil }
            let speeds = Set([vertical, horizontal].filter { $0.mode == .accelerated }.map(\.speed))
            guard speeds.count <= 1 else { return nil }
            kind = .trackpadScroll
            trackpadScroll = TrackpadScrollSettings(
                reverseVertical: vertical.reverse, reverseHorizontal: horizontal.reverse, speed: speeds.first ?? 1,
                momentum: value["scrolling"]?["momentum"] != .bool(false)
            )
        } else {
            guard value["scrolling"]?["momentum"] == nil else { return nil }
            kind = .wheel
        }
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
