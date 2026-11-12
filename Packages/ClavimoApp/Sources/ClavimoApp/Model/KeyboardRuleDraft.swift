import ClavimoCore
import Foundation

/// The action of an output: only the fields of `RuleDraft` that describe
/// an action, so keyboard drafts stay small.
struct ActionChoice: Equatable {
    var action: RuleDraft.Action = .missionControl
    var shortcutKey: UInt16 = 0x11
    var shortcutModifiers: Set<RuleDraft.Modifier> = [.command]
    var appBundleID = ""
    var mediaKey: MediaKey = .playPause
    var compassID = ""
    var menuPath: [String] = []

    init() {}

    init(_ draft: RuleDraft) {
        action = draft.action
        shortcutKey = draft.shortcutKey
        shortcutModifiers = draft.shortcutModifiers
        appBundleID = draft.appBundleID
        mediaKey = draft.mediaKey
        compassID = draft.compassID
        menuPath = draft.menuPath
    }

    /// A rule draft carrying this action, for the shared action editor
    /// and for reading and writing JSON.
    var ruleDraft: RuleDraft {
        var draft = RuleDraft()
        draft.action = action
        draft.shortcutKey = shortcutKey
        draft.shortcutModifiers = shortcutModifiers
        draft.appBundleID = appBundleID
        draft.mediaKey = mediaKey
        draft.compassID = compassID
        draft.menuPath = menuPath
        return draft
    }
}

/// What a keyboard rule produces, as the editor shows it.
struct OutputDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case key, shortcut, modifiers, holdLayer, toggleLayer, oneShot, startSequence, capsLock, compass, action, none
        var id: String { rawValue }

        var title: String {
            switch self {
            case .key: String(localized: "Type a key")
            case .shortcut: String(localized: "Keyboard shortcut")
            case .modifiers: String(localized: "Hold modifiers")
            case .holdLayer: String(localized: "Turn on a layer while held")
            case .toggleLayer: String(localized: "Turn a layer on or off")
            case .oneShot: String(localized: "Modifiers for the next key")
            case .startSequence: String(localized: "Start a key sequence")
            case .capsLock: String(localized: "Caps Lock")
            case .compass: String(localized: "Open a compass")
            case .action: String(localized: "Action")
            case .none: String(localized: "Nothing")
            }
        }

        /// Outputs that last while their key is held.
        var isHeld: Bool { [.key, .shortcut, .modifiers, .holdLayer, .compass].contains(self) }
    }

    var kind: Kind = .key
    var key: UInt16 = KeyCode.escape.rawValue
    var modifiers: Set<RuleDraft.Modifier> = [.command]
    /// Side-specific names read from the file, kept while the modifiers
    /// are not changed in the editor (the editor offers generic ones).
    var sideNames: [String]?
    var layer = "nav"
    /// The action and its details (shortcut, app, media key).
    var action = ActionChoice()

    static func key(_ code: UInt16) -> OutputDraft {
        var draft = OutputDraft()
        draft.kind = .key
        draft.key = code
        return draft
    }

    static func modifiers(_ set: Set<RuleDraft.Modifier>) -> OutputDraft {
        var draft = OutputDraft()
        draft.kind = .modifiers
        draft.modifiers = set
        return draft
    }

    static func layer(_ name: String, toggle: Bool = false) -> OutputDraft {
        var draft = OutputDraft()
        draft.kind = toggle ? .toggleLayer : .holdLayer
        draft.layer = name
        return draft
    }

    static func of(_ kind: Kind) -> OutputDraft {
        var draft = OutputDraft()
        draft.kind = kind
        return draft
    }

    static let hyper: Set<RuleDraft.Modifier> = [.control, .option, .shift, .command]

    var json: JSONValue {
        switch kind {
        case .key:
            return .object(["kind": .string("sendKey"), "key": RuleDraft.key(key)])
        case .shortcut:
            return .object(["kind": .string("sendShortcut"), "key": RuleDraft.key(key), "modifiers": RuleDraft.modifierNames(modifiers)])
        case .modifiers, .oneShot:
            return .object(["kind": .string(kind == .modifiers ? "holdModifiers" : "oneShotModifiers"), "modifiers": modifierJSON])
        case .holdLayer, .toggleLayer:
            return .object(["kind": .string(kind.rawValue), "layerId": .string(layer)])
        case .startSequence:
            return .object(["kind": .string("startSequence")])
        case .capsLock:
            return .object(["kind": .string("toggleCapsLock")])
        case .compass:
            return .object(["kind": .string("openCompass"), "compassId": .string(action.compassID)])
        case .action:
            return action.ruleDraft.actionJSON
        case .none:
            return .object(["kind": .string("none")])
        }
    }

    private var modifierJSON: JSONValue {
        if let sideNames, Self.generic(sideNames) == modifiers { return .array(sideNames.map(JSONValue.string)) }
        return .array(RuleDraft.Modifier.allCases.filter { modifiers.contains($0) && $0 != .function }.map { .string($0.rawValue) })
    }

    private static func generic(_ names: [String]) -> Set<RuleDraft.Modifier> {
        Set(names.compactMap { name in
            switch name {
            case "control", "leftControl", "rightControl": .control
            case "option", "leftOption", "rightOption": .option
            case "shift", "leftShift", "rightShift": .shift
            case "command", "leftCommand", "rightCommand": .command
            default: nil
            }
        })
    }

    init() {}

    /// Nil when the output is something the editor cannot show.
    init?(json value: JSONValue) {
        switch value["kind"]?.string {
        case "sendKey":
            guard let code = RuleDraft.code(value["key"]) else { return nil }
            kind = .key
            key = code
        case "sendShortcut" where value["modifiers"] != nil:
            guard let code = RuleDraft.code(value["key"]), let set = RuleDraft.modifierSet(value["modifiers"]) else { return nil }
            kind = .shortcut
            key = code
            modifiers = set
        case "holdModifiers", "oneShotModifiers":
            let names = (value["modifiers"]?.array ?? []).compactMap(\.string)
            let set = Self.generic(names)
            guard !set.isEmpty, names.allSatisfy({ !Self.generic([$0]).isEmpty }) else { return nil }
            kind = value["kind"]?.string == "holdModifiers" ? .modifiers : .oneShot
            modifiers = set
            sideNames = names
        case "holdLayer", "toggleLayer":
            guard let name = value["layerId"]?.string, !name.isEmpty else { return nil }
            kind = value["kind"]?.string == "holdLayer" ? .holdLayer : .toggleLayer
            layer = name
        case "startSequence":
            kind = .startSequence
        case "toggleCapsLock":
            kind = .capsLock
        case "openCompass":
            guard let id = value["compassId"]?.string, !id.isEmpty else { return nil }
            kind = .compass
            action.compassID = id
        case "none", "disableInput":
            kind = .none
        default:
            var draft = RuleDraft()
            guard draft.readAction(value) else { return nil }
            kind = .action
            action = ActionChoice(draft)
        }
    }

    /// A short description, e.g. "Escape", "⌘C", "Hyper", "Layer nav".
    var title: String {
        switch kind {
        case .key: KeyNames.name(for: key)
        case .shortcut: modifierSymbols + KeyNames.keyCap(for: key).label
        case .modifiers: modifiers == Self.hyper ? String(localized: "Hyper (⌃⌥⇧⌘)") : modifierSymbols
        case .oneShot: String(localized: "\(modifierSymbols) for the next key")
        case .holdLayer: String(localized: "Layer \(layer)")
        case .toggleLayer: String(localized: "Switch layer \(layer)")
        case .startSequence: String(localized: "Key sequence")
        case .capsLock: String(localized: "Caps Lock")
        case .compass: String(localized: "Compass")
        case .action: action.ruleDraft.actionTitle
        case .none: String(localized: "Nothing")
        }
    }

    private var modifierSymbols: String {
        RuleDraft.Modifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined()
    }

    var validationMessage: String? {
        switch kind {
        case .modifiers, .oneShot:
            if modifiers.subtracting([.function]).isEmpty { return String(localized: "Choose at least one modifier.") }
        case .holdLayer, .toggleLayer:
            if layer.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Name the layer.") }
        case .key, .shortcut:
            if key == KeyCode.capsLock.rawValue || key == KeyCode.function.rawValue {
                return String(localized: "Caps Lock and Fn cannot be typed by a rule. Use the Caps Lock output instead.")
            }
        case .action:
            if let message = action.ruleDraft.actionValidationMessage { return message }
        case .compass:
            if action.compassID.isEmpty { return String(localized: "Choose a compass. Add one in the Compass pane first.") }
        default:
            break
        }
        return nil
    }
}

/// The editable form of tap-hold keys, key outputs, layer keys, combos and
/// sequences.
struct KeyboardRuleDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case tapHold, keyOutput, layerKey, combo, sequence
        var id: String { rawValue }

        var title: String {
            switch self {
            case .tapHold: String(localized: "Tap or hold a key")
            case .keyOutput: String(localized: "Key does something else")
            case .layerKey: String(localized: "Key on a layer")
            case .combo: String(localized: "Keys pressed together")
            case .sequence: String(localized: "Key sequence")
            }
        }

        var symbol: String {
            switch self {
            case .tapHold: "hand.tap"
            case .keyOutput: "keyboard"
            case .layerKey: "square.3.layers.3d"
            case .combo: "rectangle.on.rectangle"
            case .sequence: "arrow.right.to.line"
            }
        }
    }

    var kind: Kind = .tapHold
    var name = ""
    var profileID = "default"
    var enabled = true
    var key: UInt16 = KeyCode.capsLock.rawValue
    var keys: [UInt16] = [0x26, 0x28]
    var layer = "nav"
    /// The output; for tap-hold keys, the tap.
    var output = OutputDraft.key(KeyCode.escape.rawValue)
    var hold = OutputDraft.modifiers(OutputDraft.hyper)
    var doubleTapEnabled = false
    var doubleTap = OutputDraft.of(.capsLock)
    var holdAfterMilliseconds = 200
    var interrupt: TapHoldSettings.Interrupt = .holdOnOtherKey
    var oppositeHandsOnly = false
    var typingStreakMilliseconds = 0
    var windowMilliseconds = ComboRule.defaultWindowMilliseconds
    var onlyApps: [String] = []
    var exceptApps: [String] = []
    var inputSources: [String] = []

    init() {}

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .keyOutput:
            key = 0x69 // F13
            output = OutputDraft.of(.action)
        case .layerKey:
            key = 0x04 // H
            output = .key(KeyCode.leftArrow.rawValue)
        case .combo:
            keys = [0x26, 0x28] // J K
            output = .key(KeyCode.escape.rawValue)
        case .sequence:
            keys = [0x1F] // O
            output = OutputDraft.of(.action)
        case .tapHold:
            break
        }
    }

    /// A home row modifier: the letter when tapped, a modifier when held.
    static func homeRow(key: UInt16, modifier: RuleDraft.Modifier, holdAfter: Int, profileID: String) -> KeyboardRuleDraft {
        var draft = KeyboardRuleDraft()
        draft.kind = .tapHold
        draft.key = key
        draft.output = .key(key)
        draft.hold = .modifiers([modifier])
        draft.holdAfterMilliseconds = holdAfter
        draft.interrupt = .permissive
        draft.oppositeHandsOnly = true
        draft.typingStreakMilliseconds = TapHoldSettings.homeRow.typingStreakMilliseconds
        draft.profileID = profileID
        draft.name = String(localized: "Home row: \(KeyNames.name(for: key)) / \(modifier.symbol)")
        return draft
    }

    // MARK: Names

    var keysTitle: String { keys.map { KeyNames.name(for: $0) }.joined(separator: " + ") }

    var triggerTitle: String {
        switch kind {
        case .tapHold, .keyOutput: KeyNames.name(for: key)
        case .layerKey: String(localized: "\(KeyNames.name(for: key)) on layer \(layer)")
        case .combo: keysTitle
        case .sequence: keys.map { KeyNames.name(for: $0) }.joined(separator: " → ")
        }
    }

    var resultTitle: String {
        switch kind {
        case .tapHold:
            var parts = [String(localized: "tap: \(output.title)"), String(localized: "hold: \(hold.title)")]
            if doubleTapEnabled { parts.append(String(localized: "double tap: \(doubleTap.title)")) }
            return parts.joined(separator: ", ")
        default:
            return output.title
        }
    }

    var suggestedName: String {
        switch kind {
        case .tapHold: String(localized: "\(KeyNames.name(for: key)): \(resultTitle)")
        case .sequence: String(localized: "Leader → \(triggerTitle): \(output.title)")
        default: String(localized: "\(triggerTitle): \(output.title)")
        }
    }

    var displayName: String { name.isEmpty ? suggestedName : name }

    var validationMessage: String? {
        switch kind {
        case .tapHold:
            if KeyCode(key) == .function { return String(localized: "Fn cannot be changed.") }
            if KeyCode(key).modifierKey != nil {
                if hold.kind != .modifiers || !isOwnModifier(hold) {
                    return String(localized: "A modifier key keeps working as itself when held; only its tap can be changed.")
                }
                if doubleTapEnabled { return String(localized: "A modifier key cannot have a double tap.") }
            } else if !hold.kind.isHeld {
                return String(localized: "The hold must be a key, modifiers or a layer.")
            }
            return output.validationMessage ?? hold.validationMessage ?? (doubleTapEnabled ? doubleTap.validationMessage : nil)
        case .keyOutput:
            if KeyCode(key).modifierKey != nil || KeyCode(key) == .function {
                return String(localized: "Choose a key that is not a modifier. To add a tap to a modifier key, use Tap or hold a key.")
            }
        case .layerKey:
            if layer.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Name the layer.") }
            if KeyCode(key).modifierKey != nil || KeyCode(key) == .function { return String(localized: "Modifier keys cannot be on a layer.") }
        case .combo:
            if !ComboRule.keyCount.contains(keys.count) || Set(keys).count != keys.count {
                return String(localized: "Choose two or three different keys.")
            }
            if keys.contains(where: { KeyCode($0).modifierKey != nil || KeyCode($0) == .function }) {
                return String(localized: "Modifier keys cannot be part of a combo.")
            }
        case .sequence:
            if !SequenceRule.keyCount.contains(keys.count) { return String(localized: "Choose one to four keys.") }
            if keys.contains(KeyCode.escape.rawValue) { return String(localized: "Escape cancels a sequence, so it cannot be part of one.") }
            if keys.contains(where: { KeyCode($0).modifierKey != nil || KeyCode($0) == .function }) {
                return String(localized: "Modifier keys cannot be part of a sequence.")
            }
        }
        return output.validationMessage
    }

    private func isOwnModifier(_ output: OutputDraft) -> Bool {
        guard let modifier = KeyCode(key).modifierKey else { return false }
        let generic: RuleDraft.Modifier = switch modifier {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        case .leftCommand, .rightCommand: .command
        }
        return output.modifiers == [generic]
    }

    // MARK: JSON

    func makeRule(id: String, order: Int) -> ConfigDocument.Rule {
        let trigger: JSONValue
        var actionValue = output.json
        switch kind {
        case .tapHold:
            var object: [String: JSONValue] = [
                "kind": .string("tapHold"), "key": RuleDraft.key(key),
                "thresholdMs": .number(Double(holdAfterMilliseconds)),
                "interruptPolicy": .string(interruptName),
            ]
            if oppositeHandsOnly { object["oppositeHandsOnly"] = .bool(true) }
            if typingStreakMilliseconds > 0 { object["typingStreakMs"] = .number(Double(typingStreakMilliseconds)) }
            trigger = .object(object)
            var action: [String: JSONValue] = ["kind": .string("tapHold"), "tap": output.json, "hold": holdJSON]
            if doubleTapEnabled { action["doubleTap"] = doubleTap.json }
            actionValue = .object(action)
        case .keyOutput:
            trigger = .object(["kind": .string("key"), "key": RuleDraft.key(key)])
        case .layerKey:
            trigger = .object(["kind": .string("layerKey"), "layerId": .string(layer), "key": RuleDraft.key(key)])
        case .combo:
            var object: [String: JSONValue] = ["kind": .string("keyCombo"), "keys": .array(keys.map(RuleDraft.key))]
            if windowMilliseconds != ComboRule.defaultWindowMilliseconds { object["windowMs"] = .number(Double(windowMilliseconds)) }
            trigger = .object(object)
        case .sequence:
            trigger = .object(["kind": .string("keySequence"), "keys": .array(keys.map(RuleDraft.key))])
        }
        let conditions: [JSONValue] = onlyApps.map { .object(["kind": .string("appIs"), "bundleId": .string($0)]) }
            + exceptApps.map { .object(["kind": .string("appIsNot"), "bundleId": .string($0)]) }
            + inputSources.map { .object(["kind": .string("inputSourceIs"), "inputSourceId": .string($0)]) }
        return ConfigDocument.Rule(
            id: id, name: displayName, enabled: enabled, priority: 50, profileId: profileID,
            trigger: trigger, conditions: conditions, action: actionValue,
            behavior: ConfigDocument.Behavior(consumeTrigger: true, fireOn: "down", repeat: "onAutorepeat"),
            ui: .object(["order": .number(Double(order))])
        )
    }

    /// A modifier key's own hold is written with its side.
    private var holdJSON: JSONValue {
        if let modifier = KeyCode(key).modifierKey {
            let name = switch modifier {
            case .leftControl: "leftControl"
            case .rightControl: "rightControl"
            case .leftShift: "leftShift"
            case .rightShift: "rightShift"
            case .leftOption: "leftOption"
            case .rightOption: "rightOption"
            case .leftCommand: "leftCommand"
            case .rightCommand: "rightCommand"
            }
            return .object(["kind": .string("holdModifiers"), "modifiers": .array([.string(name)])])
        }
        return hold.json
    }

    private var interruptName: String {
        switch interrupt {
        case .holdOnOtherKey: "anyOtherKey"
        case .permissive: "permissiveHold"
        case .timeOnly: "none"
        }
    }

    /// Nil for rules the form cannot represent.
    init?(rule: ConfigDocument.Rule) {
        name = rule.name
        profileID = rule.profileId
        enabled = rule.enabled
        for condition in rule.conditions {
            switch condition["kind"]?.string {
            case "appIs": guard let id = condition["bundleId"]?.string else { return nil }; onlyApps.append(id)
            case "appIsNot": guard let id = condition["bundleId"]?.string else { return nil }; exceptApps.append(id)
            case "inputSourceIs": guard let id = condition["inputSourceId"]?.string else { return nil }; inputSources.append(id)
            default: return nil
            }
        }
        let trigger = rule.trigger
        switch (trigger["kind"]?.string, rule.action["kind"]?.string) {
        case ("key", "sendKey"), ("keyPair", _):
            return nil // plain remaps and swaps belong to RuleDraft
        case ("key", _):
            guard let code = RuleDraft.code(trigger["key"]), let parsed = OutputDraft(json: rule.action) else { return nil }
            kind = .keyOutput
            key = code
            output = parsed
        case ("tapHold", "tapHold"):
            guard let code = RuleDraft.code(trigger["key"]), let threshold = trigger["thresholdMs"]?.int,
                  let tapValue = rule.action["tap"], let holdValue = rule.action["hold"],
                  let tap = OutputDraft(json: tapValue), let holdOutput = OutputDraft(json: holdValue) else { return nil }
            kind = .tapHold
            key = code
            output = tap
            hold = holdOutput
            holdAfterMilliseconds = threshold
            if let value = rule.action["doubleTap"] {
                guard let parsed = OutputDraft(json: value) else { return nil }
                doubleTapEnabled = true
                doubleTap = parsed
            }
            switch trigger["interruptPolicy"]?.string ?? "anyOtherKey" {
            case "anyOtherKey": interrupt = .holdOnOtherKey
            case "permissiveHold": interrupt = .permissive
            case "none": interrupt = .timeOnly
            default: return nil
            }
            oppositeHandsOnly = trigger["oppositeHandsOnly"] == .bool(true)
            typingStreakMilliseconds = trigger["typingStreakMs"]?.int ?? 0
        case ("layerKey", _):
            guard let code = RuleDraft.code(trigger["key"]), let name = trigger["layerId"]?.string,
                  let parsed = OutputDraft(json: rule.action) else { return nil }
            kind = .layerKey
            key = code
            layer = name
            output = parsed
        case ("keyCombo", _), ("keySequence", _):
            let codes = (trigger["keys"]?.array ?? []).compactMap(RuleDraft.code)
            guard codes.count == trigger["keys"]?.array?.count, let parsed = OutputDraft(json: rule.action) else { return nil }
            kind = trigger["kind"]?.string == "keyCombo" ? .combo : .sequence
            keys = codes
            output = parsed
            windowMilliseconds = trigger["windowMs"]?.int ?? ComboRule.defaultWindowMilliseconds
        default:
            return nil
        }
    }
}
