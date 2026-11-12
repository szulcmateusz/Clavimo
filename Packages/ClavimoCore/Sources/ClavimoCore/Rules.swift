/// How a letter-style leader key behaves while the engine waits to learn
/// whether it starts a keyboard + mouse chord. The policies trade typing
/// latency against accidental characters, so they are never interchangeable.
public enum LeaderPolicy: Equatable, Sendable {
    /// Buffer the key for at most `milliseconds`. A chord can start only
    /// inside the window; afterwards the key is delivered and behaves
    /// normally, including autorepeat.
    case boundedWindow(milliseconds: Int)
    /// Buffer the key until it is released or another key needs it.
    /// No accidental character, but no autorepeat while it is held.
    case deferredUntilUp
    /// Deliver the key immediately; the chord still fires while it is
    /// held. The key's character may reach the focused application.
    case nonConsuming

    /// Matches `behavior.leaderWindowMs` in the v1 schema.
    public static let allowedWindow: ClosedRange<Int> = 50...500
    public static let defaultWindowMilliseconds = 120
}

public enum ChordLeader: Equatable, Sendable {
    /// The exact set of generic modifiers that must be physically held.
    case modifiers(GenericModifiers)
    /// A non-modifier key that must be held, with its buffering policy.
    case key(KeyCode, LeaderPolicy)
}

/// Identifies a physical device model by USB/Bluetooth vendor and product
/// IDs. Two identical devices share an ID; that limitation is documented.
public struct DeviceID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let vendorID: Int
    public let productID: Int

    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    /// Parses the config form `"<vendor>:<product>"` in decimal.
    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let vendor = Int(parts[0]), let product = Int(parts[1]),
              vendor >= 0, product >= 0 else { return nil }
        self.init(vendorID: vendor, productID: product)
    }

    public var description: String { "\(vendorID):\(productID)" }

    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool {
        (lhs.vendorID, lhs.productID) < (rhs.vendorID, rhs.productID)
    }
}

/// Conditions that must all hold for a rule to apply (AND semantics).
public struct RuleConditions: Hashable, Sendable {
    /// When non-empty, the frontmost app must be one of these bundle IDs.
    public var onlyApps: Set<String>
    /// The rule never applies while one of these apps is frontmost.
    public var exceptApps: Set<String>
    /// When non-empty, the triggering input must be attributed to one of
    /// these devices. Unknown attribution never matches.
    public var devices: Set<DeviceID>
    /// When non-empty, the selected keyboard input source (for example
    /// `com.apple.keylayout.Polish`) must be one of these.
    public var inputSources: Set<String>

    public init(onlyApps: Set<String> = [], exceptApps: Set<String> = [], devices: Set<DeviceID> = [], inputSources: Set<String> = []) {
        self.onlyApps = onlyApps
        self.exceptApps = exceptApps
        self.devices = devices
        self.inputSources = inputSources
    }

    public static let always = RuleConditions()

    public var isEmpty: Bool { onlyApps.isEmpty && exceptApps.isEmpty && devices.isEmpty && inputSources.isEmpty }

    /// More specific rules win over general ones with the same trigger.
    var specificity: Int {
        (onlyApps.isEmpty ? 0 : 2) + (exceptApps.isEmpty ? 0 : 1) + (devices.isEmpty ? 0 : 4) + (inputSources.isEmpty ? 0 : 8)
    }

    public func matches(app: String?, device: DeviceID?, inputSource: String? = nil) -> Bool {
        if !inputSources.isEmpty {
            guard let inputSource, inputSources.contains(inputSource) else { return false }
        }
        if !onlyApps.isEmpty {
            guard let app, onlyApps.contains(app) else { return false }
        }
        if let app, exceptApps.contains(app) { return false }
        if !devices.isEmpty {
            guard let device, devices.contains(device) else { return false }
        }
        return true
    }
}

/// A user-level rule before compilation.
public enum RuleDefinition: Equatable, Sendable {
    case remap(from: KeyCode, to: KeyCode, conditions: RuleConditions = .always)
    /// Bidirectional swap; compiles to two remaps.
    case swap(KeyCode, KeyCode, conditions: RuleConditions = .always)
    /// `allowProtectedButton` must be set explicitly for the primary or
    /// secondary button; only modifier leaders may use them.
    case mouseChord(
        id: String,
        leader: ChordLeader,
        button: MouseButton,
        action: ActionCommand,
        priority: Int,
        allowProtectedButton: Bool = false,
        conditions: RuleConditions = .always
    )
    /// Changes discrete (mouse wheel) scrolling per axis. Continuous
    /// scrolling from trackpads is never changed.
    case wheel(vertical: ScrollAxisSettings, horizontal: ScrollAxisSettings, conditions: RuleConditions = .always)
    /// Changes continuous scrolling from trackpads (and Magic Mouse).
    case trackpadScroll(TrackpadScrollSettings, conditions: RuleConditions = .always)
    /// A trackpad gesture or click, with the exact set of modifiers that
    /// must be held (empty means none).
    case trackpad(
        id: String,
        trigger: TrackpadTrigger,
        modifiers: GenericModifiers = [],
        action: ActionCommand,
        priority: Int = 100,
        conditions: RuleConditions = .always,
        zone: TrackpadZone? = nil
    )
    /// A key that does something other than send another key: a shortcut,
    /// modifiers, a layer, a one-shot modifier, a sequence or an action.
    case keyOutput(id: String, key: KeyCode, output: KeyOutput, conditions: RuleConditions = .always)
    /// A key with one output when tapped and another when held.
    case tapHold(
        id: String,
        key: KeyCode,
        tap: KeyOutput,
        hold: KeyOutput,
        doubleTap: KeyOutput? = nil,
        settings: TapHoldSettings = TapHoldSettings(),
        conditions: RuleConditions = .always
    )
    /// What a key does while a layer is active.
    case layerKey(id: String, layer: String, key: KeyCode, output: KeyOutput, conditions: RuleConditions = .always)
    /// Keys pressed together within a short window.
    case combo(id: String, keys: Set<KeyCode>, output: KeyOutput,
               windowMilliseconds: Int = ComboRule.defaultWindowMilliseconds, conditions: RuleConditions = .always)
    /// Keys typed one after another after a leader key.
    case sequence(id: String, keys: [KeyCode], output: KeyOutput, conditions: RuleConditions = .always)
}

/// What a trackpad rule reacts to.
public enum TrackpadTrigger: Hashable, Sendable {
    /// A recognized gesture: multi-finger tap, tip tap or swipe.
    case gesture(GestureEvent)
    /// A physical click while this many fingers touch the trackpad.
    case click(fingers: Int)
    /// A click, or a tap with tap to click, by one finger in a corner.
    case cornerClick(TrackpadCorner)

    public static let tapFingers = 2...5
    public static let swipeFingers = 3...5
    public static let clickFingers = 3...5
}

public struct TrackpadRule: Equatable, Sendable {
    public let id: String
    public let trigger: TrackpadTrigger
    public let modifiers: GenericModifiers
    public let action: ActionCommand
    public let priority: Int
    public let conditions: RuleConditions
    /// Nil for the whole surface.
    public var zone: TrackpadZone? = nil
}

extension RuleDefinition {
    /// Identifies what a rule reacts to, so a rule in a profile can replace
    /// an inherited rule with the same trigger and conditions.
    public var triggerSignatures: Set<String> {
        switch self {
        case let .remap(from, _, conditions):
            ["key:\(from.rawValue):\(conditions.signature)"]
        case let .swap(first, second, conditions):
            ["key:\(first.rawValue):\(conditions.signature)", "key:\(second.rawValue):\(conditions.signature)"]
        case let .mouseChord(_, leader, button, _, _, _, conditions):
            ["chord:\(leader.signature):\(button.rawValue):\(conditions.signature)"]
        case let .wheel(_, _, conditions):
            ["wheel:\(conditions.signature)"]
        case let .trackpadScroll(_, conditions):
            ["trackpadScroll:\(conditions.signature)"]
        case let .trackpad(_, trigger, modifiers, _, _, conditions, zone):
            ["trackpad:\(trigger.signature):\(modifiers.rawValue):\(conditions.signature):\(zone?.rawValue ?? "")"]
        case let .keyOutput(_, key, _, conditions), let .tapHold(_, key, _, _, _, _, conditions):
            ["key:\(key.rawValue):\(conditions.signature)"]
        case let .layerKey(_, layer, key, _, conditions):
            ["layer:\(layer):\(key.rawValue):\(conditions.signature)"]
        case let .combo(_, keys, _, _, conditions):
            ["combo:\(keys.map(\.rawValue).sorted()):\(conditions.signature)"]
        case let .sequence(_, keys, _, conditions):
            ["sequence:\(keys.map(\.rawValue)):\(conditions.signature)"]
        }
    }
}

extension RuleDefinition {
    /// The compasses this rule opens.
    public var openedCompasses: Set<String> {
        var actions: [ActionCommand] = []
        var outputs: [KeyOutput] = []
        switch self {
        case let .mouseChord(_, _, _, action, _, _, _), let .trackpad(_, _, _, action, _, _, _): actions.append(action)
        case let .keyOutput(_, _, output, _), let .layerKey(_, _, _, output, _), let .combo(_, _, output, _, _),
             let .sequence(_, _, output, _):
            outputs.append(output)
        case let .tapHold(_, _, tap, hold, doubleTap, _, _): outputs += [tap, hold] + (doubleTap.map { [$0] } ?? [])
        case .remap, .swap, .wheel, .trackpadScroll: break
        }
        for case let .action(action) in outputs { actions.append(action) }
        return Set(actions.compactMap { if case let .openCompass(id) = $0 { id } else { nil } })
    }
}

extension RuleConditions {
    var signature: String {
        [onlyApps.sorted().joined(separator: ","), exceptApps.sorted().joined(separator: ","),
         devices.sorted().map(\.description).joined(separator: ","),
         inputSources.sorted().joined(separator: ",")].joined(separator: "|")
    }
}

extension TrackpadTrigger {
    var signature: String {
        switch self {
        case let .gesture(.tap(fingers)): "tap\(fingers)"
        case let .gesture(.tipTap(side)): "tiptap-\(side.rawValue)"
        case let .gesture(.swipe(fingers, direction)): "swipe\(fingers)-\(direction.rawValue)"
        case let .gesture(.rotate(rotation)): "rotate-\(rotation.rawValue)"
        case let .click(fingers): "click\(fingers)"
        case let .cornerClick(corner): "corner-\(corner.rawValue)"
        }
    }
}

extension ChordLeader {
    var signature: String {
        switch self {
        case let .modifiers(modifiers): "mods:\(modifiers.rawValue)"
        case let .key(key, _): "key:\(key.rawValue)"
        }
    }
}

public enum RuleValidationError: Error, Equatable, Sendable {
    case duplicateRemapSource(KeyCode)
    case swapWithItself(KeyCode)
    case remapToItself(KeyCode)
    case leaderWindowOutOfRange(KeyCode, milliseconds: Int)
    case leaderIsModifierKey(KeyCode)
    case leaderAlsoRemapped(KeyCode)
    case conflictingLeaderPolicies(KeyCode)
    case emptyModifierLeader(id: String)
    case protectedMouseButton(MouseButton, id: String)
    case protectedMouseButtonNeedsModifierLeader(MouseButton, id: String)
    case duplicateChord(button: MouseButton, ids: [String])
    case duplicateRuleID(String)
    case deviceConditionOnLetterLeader(id: String)
    /// Caps Lock and Fn arrive as special flag changes that the Quartz
    /// backend forwards uninterpreted, so they cannot be remapped yet.
    case unsupportedKey(KeyCode)
    case duplicateWheelRule
    case wheelRuleWithoutChanges
    /// A trackpad gesture with a finger count it cannot have.
    case trackpadFingersOutOfRange(id: String)
    /// A two-finger tap is the macOS secondary click; it needs modifiers.
    case twoFingerTapNeedsModifiers(id: String)
    case duplicateTrackpadRule(ids: [String])
    case duplicateTrackpadScroll
    case trackpadScrollWithoutChanges
    /// Zones work for gestures only; clicks are matched by their fingers.
    case trackpadZoneOnClick(id: String)
    /// A tap-hold key needs a held output (modifiers or a layer) for its hold.
    case holdOutputNotHeld(id: String)
    /// Modifier keys can only add a tap output; their hold stays the modifier.
    case modifierTapHoldChangesHold(id: String)
    case tapHoldTimingOutOfRange(id: String)
    /// A layer key whose layer no rule can switch on.
    case layerNeverActivated(String)
    case emptyLayerName(id: String)
    case invalidCombo(id: String)
    case invalidSequence(id: String)
    /// A sequence that is the start of another one could never complete.
    case ambiguousSequence(ids: [String])
    case sequenceWithoutLeader(id: String)
    /// Modifier keys and Fn cannot be part of a combo, a sequence or a layer.
    case modifierKeyNotAllowed(KeyCode, id: String)
}

public struct ContinuousScrollRule: Equatable, Sendable {
    public let settings: TrackpadScrollSettings
    public let conditions: RuleConditions
}

public struct ChordRule: Equatable, Sendable {
    public let id: String
    public let leader: ChordLeader
    public let button: MouseButton
    public let action: ActionCommand
    public let priority: Int
    public let conditions: RuleConditions
}

public struct RemapCandidate: Equatable, Sendable {
    public let target: KeyCode
    public let conditions: RuleConditions
}

public struct WheelSettings: Equatable, Sendable {
    public let vertical: ScrollAxisSettings
    public let horizontal: ScrollAxisSettings
    public let conditions: RuleConditions
}

/// An immutable, validated rule snapshot optimized for lookups on the
/// event path: every lookup is a dictionary access keyed by the input,
/// followed by a short candidate list ordered by specificity.
public struct CompiledRules: Equatable, Sendable {
    /// Candidates per source key, most specific first.
    public let remapCandidates: [KeyCode: [RemapCandidate]]
    /// Chord candidates per button: higher priority first, then more
    /// specific conditions, then definition order.
    public let chordsByButton: [MouseButton: [ChordRule]]
    public let leaderPolicies: [KeyCode: LeaderPolicy]
    /// Wheel settings, most specific first.
    public let wheelSettings: [WheelSettings]
    /// Trackpad rules per trigger: higher priority first, then more
    /// specific conditions, then definition order.
    public let trackpadRules: [TrackpadTrigger: [TrackpadRule]]
    /// Continuous scroll settings, most specific first.
    public let trackpadScroll: [ContinuousScrollRule]
    /// Key behaviors other than plain remaps, most specific first. Caps
    /// Lock is stored as `KeyCode.capsLockProxy`.
    public let keyBindings: [KeyCode: [KeyBinding]]
    /// Per layer, per key, most specific first.
    public let layerBindings: [String: [KeyCode: [LayerBinding]]]
    public let combos: [ComboRule]
    public let comboKeys: Set<KeyCode>
    public let sequences: [SequenceRule]
    /// Whether any rule reacts to Caps Lock, which needs it moved to
    /// `KeyCode.capsLockProxy` at the HID level while rules are active.
    public let usesCapsLock: Bool

    public init(
        remapCandidates: [KeyCode: [RemapCandidate]],
        chordsByButton: [MouseButton: [ChordRule]],
        leaderPolicies: [KeyCode: LeaderPolicy],
        wheelSettings: [WheelSettings],
        trackpadRules: [TrackpadTrigger: [TrackpadRule]] = [:],
        trackpadScroll: [ContinuousScrollRule] = [],
        keyBindings: [KeyCode: [KeyBinding]] = [:],
        layerBindings: [String: [KeyCode: [LayerBinding]]] = [:],
        combos: [ComboRule] = [],
        sequences: [SequenceRule] = [],
        usesCapsLock: Bool = false
    ) {
        self.trackpadScroll = trackpadScroll
        self.keyBindings = keyBindings
        self.layerBindings = layerBindings
        self.combos = combos
        comboKeys = Set(combos.flatMap(\.keys))
        self.sequences = sequences
        self.usesCapsLock = usesCapsLock
        self.remapCandidates = remapCandidates
        self.chordsByButton = chordsByButton
        self.leaderPolicies = leaderPolicies
        self.wheelSettings = wheelSettings
        self.trackpadRules = trackpadRules
    }

    public static let empty = CompiledRules(remapCandidates: [:], chordsByButton: [:], leaderPolicies: [:], wheelSettings: [])

    public var isEmpty: Bool {
        remapCandidates.isEmpty && chordsByButton.isEmpty && wheelSettings.isEmpty && trackpadRules.isEmpty
            && trackpadScroll.isEmpty && keyBindings.isEmpty && layerBindings.isEmpty && combos.isEmpty && sequences.isEmpty
    }

    /// Whether any rule depends on the keyboard input source.
    public var usesInputSources: Bool {
        remapCandidates.values.contains { $0.contains { !$0.conditions.inputSources.isEmpty } }
            || keyBindings.values.contains { $0.contains { !$0.conditions.inputSources.isEmpty } }
            || layerBindings.values.contains { $0.values.contains { $0.contains { !$0.conditions.inputSources.isEmpty } } }
            || combos.contains { !$0.conditions.inputSources.isEmpty }
            || sequences.contains { !$0.conditions.inputSources.isEmpty }
    }

    public func keyBinding(for key: KeyCode, app: String?, device: DeviceID?, inputSource: String?) -> KeyBinding? {
        keyBindings[key]?.first { $0.conditions.matches(app: app, device: device, inputSource: inputSource) }
    }

    public func layerBinding(layer: String, key: KeyCode, app: String?, inputSource: String?) -> LayerBinding? {
        layerBindings[layer]?[key]?.first { $0.conditions.matches(app: app, device: nil, inputSource: inputSource) }
    }

    /// Whether any rule needs trackpad touches, so the touch backend runs.
    public var observesTrackpad: Bool { !trackpadRules.isEmpty }

    /// Whether any rule reacts to two-finger rotation, so trackpad
    /// scrolling must be held still while fingers turn.
    public var observesRotation: Bool {
        trackpadRules.keys.contains { if case .gesture(.rotate) = $0 { true } else { false } }
    }

    /// Whether any rule replaces physical trackpad clicks, which needs the
    /// primary and secondary buttons in the event tap mask.
    public var observesTrackpadClicks: Bool {
        trackpadRules.keys.contains { if case .gesture = $0 { false } else { true } }
    }

    /// The rule for a gesture under the held modifiers in `app`. A rule
    /// limited to a zone applies only when the gesture started there.
    public func trackpadRule(for trigger: TrackpadTrigger, modifiers: GenericModifiers, app: String?,
                             at point: TrackpadPoint? = nil) -> TrackpadRule? {
        trackpadRules[trigger]?.first { rule in
            guard rule.modifiers == modifiers, rule.conditions.matches(app: app, device: nil) else { return false }
            guard let zone = rule.zone else { return true }
            guard let point else { return false }
            return zone.contains(x: point.x, y: point.y)
        }
    }

    /// Unconditional remaps, for inspection and tests.
    public var keyRemaps: [KeyCode: KeyCode] {
        remapCandidates.compactMapValues { candidates in
            candidates.first { $0.conditions.isEmpty }?.target
        }
    }

    /// Whether any rule needs the primary or secondary mouse button, which
    /// are otherwise kept out of the event tap mask.
    public var observesProtectedButtons: Bool {
        chordsByButton.keys.contains { $0.isProtected }
    }

    public var observesScrollWheel: Bool { !wheelSettings.isEmpty || !trackpadScroll.isEmpty }

    /// Every action compass a rule opens.
    public var openedCompasses: Set<String> {
        var actions: [ActionCommand] = chordsByButton.values.flatMap { $0.map(\.action) }
            + trackpadRules.values.flatMap { $0.map(\.action) }
        var outputs: [KeyOutput] = combos.map(\.output) + sequences.map(\.output)
        for binding in keyBindings.values.flatMap({ $0 }) {
            switch binding.behavior {
            case let .output(_, output): outputs.append(output)
            case let .tapHold(tapHold): outputs += [tapHold.tap, tapHold.hold] + (tapHold.doubleTap.map { [$0] } ?? [])
            }
        }
        outputs += layerBindings.values.flatMap { $0.values.flatMap { $0.map(\.output) } }
        for case let .action(action) in outputs { actions.append(action) }
        return Set(actions.compactMap { if case let .openCompass(id) = $0 { id } else { nil } })
    }

    /// Whether any rule opens an action compass, which needs primary and
    /// secondary clicks in the event tap mask to confirm or cancel it.
    public var usesCompass: Bool { !openedCompasses.isEmpty }

    public func trackpadScrollSettings(app: String?) -> TrackpadScrollSettings? {
        trackpadScroll.first { $0.conditions.matches(app: app, device: nil) }?.settings
    }

    /// Whether any rule depends on knowing the physical device, which
    /// requires device attribution in the platform adapter.
    public var usesDeviceConditions: Bool {
        remapCandidates.values.contains { $0.contains { !$0.conditions.devices.isEmpty } }
            || chordsByButton.values.contains { $0.contains { !$0.conditions.devices.isEmpty } }
            || wheelSettings.contains { !$0.conditions.devices.isEmpty }
            || keyBindings.values.contains { $0.contains { !$0.conditions.devices.isEmpty } }
    }

    /// Keys whose rules have device conditions; only these need a device
    /// lookup on the event path.
    public var keysNeedingDevice: Set<KeyCode> {
        Set(remapCandidates.filter { $0.value.contains { !$0.conditions.devices.isEmpty } }.keys)
            .union(keyBindings.filter { $0.value.contains { !$0.conditions.devices.isEmpty } }.keys)
    }

    public var buttonsNeedingDevice: Set<MouseButton> {
        Set(chordsByButton.filter { $0.value.contains { !$0.conditions.devices.isEmpty } }.keys)
    }

    public func remapTarget(for key: KeyCode, app: String?, device: DeviceID?, inputSource: String? = nil) -> KeyCode? {
        guard let candidates = remapCandidates[key] else { return nil }
        return candidates.first { $0.conditions.matches(app: app, device: device, inputSource: inputSource) }?.target
    }

    /// The leader policy for `key` if any chord using it as leader can
    /// apply in `app`; otherwise the key is not buffered at all.
    public func leaderPolicy(for key: KeyCode, app: String?) -> LeaderPolicy? {
        guard let policy = leaderPolicies[key] else { return nil }
        let applies = chordsByButton.values.contains { chords in
            chords.contains { chord in
                if case .key(key, _) = chord.leader { chord.conditions.matches(app: app, device: nil) } else { false }
            }
        }
        return applies ? policy : nil
    }

    public func wheelSettings(app: String?, device: DeviceID?) -> WheelSettings? {
        wheelSettings.first { $0.conditions.matches(app: app, device: device) }
    }

    public static func compile(_ definitions: [RuleDefinition]) -> Result<CompiledRules, CompileFailure> {
        var errors: [RuleValidationError] = []
        var remaps: [KeyCode: [(RemapCandidate, Int)]] = [:]
        var chords: [ChordRule] = []
        var leaderPolicies: [KeyCode: LeaderPolicy] = [:]
        var wheel: [(WheelSettings, Int)] = []
        var trackpad: [(TrackpadRule, Int)] = []
        var continuous: [(ContinuousScrollRule, Int)] = []
        var bindings: [KeyCode: [(KeyBinding, Int)]] = [:]
        var layers: [String: [KeyCode: [(LayerBinding, Int)]]] = [:]
        var combos: [ComboRule] = []
        var sequences: [SequenceRule] = []
        var activatedLayers: Set<String> = []
        var startsSequence = false
        var usesCapsLock = false
        var seenIDs: Set<String> = []

        /// Caps Lock listens to its proxy key; it cannot be produced.
        func source(_ key: KeyCode) -> KeyCode {
            if key == .capsLock {
                usesCapsLock = true
                return .capsLockProxy
            }
            return key
        }

        func claim(_ id: String) {
            if !seenIDs.insert(id).inserted { errors.append(.duplicateRuleID(id)) }
        }

        func isTaken(_ key: KeyCode, _ conditions: RuleConditions) -> Bool {
            remaps[key]?.contains(where: { $0.0.conditions == conditions }) == true
                || bindings[key]?.contains(where: { $0.0.conditions == conditions }) == true
        }

        /// Checks an output; returns false when it is invalid.
        func checkOutput(_ output: KeyOutput, id: String) -> Bool {
            switch output {
            case let .key(code, _):
                if code == .capsLock || code == .function {
                    errors.append(.unsupportedKey(code))
                    return false
                }
            case let .layer(name), let .toggleLayer(name):
                if name.isEmpty {
                    errors.append(.emptyLayerName(id: id))
                    return false
                }
                activatedLayers.insert(name)
            case .startSequence:
                startsSequence = true
            default:
                break
            }
            return true
        }

        func addRemap(_ from: KeyCode, _ to: KeyCode, _ conditions: RuleConditions, _ order: Int) {
            if from == .function || to == .capsLock || to == .function {
                errors.append(.unsupportedKey(from == .function ? from : to))
                return
            }
            let from = source(from)
            if isTaken(from, conditions) {
                errors.append(.duplicateRemapSource(from == .capsLockProxy ? .capsLock : from))
            } else {
                remaps[from, default: []].append((RemapCandidate(target: to, conditions: conditions), order))
            }
        }

        func addBinding(_ key: KeyCode, _ behavior: KeyBehavior, _ conditions: RuleConditions, _ order: Int) {
            if key == .function {
                errors.append(.unsupportedKey(key))
                return
            }
            let key = source(key)
            if isTaken(key, conditions) {
                errors.append(.duplicateRemapSource(key == .capsLockProxy ? .capsLock : key))
            } else {
                bindings[key, default: []].append((KeyBinding(behavior: behavior, conditions: conditions), order))
            }
        }

        func plainKey(_ key: KeyCode, id: String) -> Bool {
            if key.modifierKey != nil || key == .function {
                errors.append(.modifierKeyNotAllowed(key, id: id))
                return false
            }
            return true
        }

        for (order, definition) in definitions.enumerated() {
            switch definition {
            case let .remap(from, to, conditions):
                if from == to {
                    errors.append(.remapToItself(from))
                } else {
                    addRemap(from, to, conditions, order)
                }
            case let .swap(first, second, conditions):
                if first == second {
                    errors.append(.swapWithItself(first))
                } else {
                    addRemap(first, second, conditions, order)
                    addRemap(second, first, conditions, order)
                }
            case let .wheel(vertical, horizontal, conditions):
                if wheel.contains(where: { $0.0.conditions == conditions }) {
                    errors.append(.duplicateWheelRule)
                } else if !vertical.changesEvents && !horizontal.changesEvents {
                    errors.append(.wheelRuleWithoutChanges)
                } else {
                    wheel.append((WheelSettings(vertical: vertical, horizontal: horizontal, conditions: conditions), order))
                }
            case let .trackpadScroll(settings, conditions):
                if continuous.contains(where: { $0.0.conditions == conditions }) {
                    errors.append(.duplicateTrackpadScroll)
                } else if !settings.changesEvents {
                    errors.append(.trackpadScrollWithoutChanges)
                } else {
                    continuous.append((ContinuousScrollRule(settings: settings, conditions: conditions), order))
                }
            case let .trackpad(id, trigger, modifiers, action, priority, conditions, zone):
                if !seenIDs.insert(id).inserted {
                    errors.append(.duplicateRuleID(id))
                }
                let fingersValid = switch trigger {
                case let .gesture(.tap(fingers)): TrackpadTrigger.tapFingers.contains(fingers)
                case let .gesture(.swipe(fingers, _)): TrackpadTrigger.swipeFingers.contains(fingers)
                case let .click(fingers): TrackpadTrigger.clickFingers.contains(fingers)
                case .gesture(.tipTap), .gesture(.rotate), .cornerClick: true
                }
                if !fingersValid {
                    errors.append(.trackpadFingersOutOfRange(id: id))
                } else if trigger == .gesture(.tap(fingers: 2)), modifiers.isEmpty {
                    errors.append(.twoFingerTapNeedsModifiers(id: id))
                }
                if zone != nil, case .gesture = trigger {} else if zone != nil {
                    errors.append(.trackpadZoneOnClick(id: id))
                }
                if let other = trackpad.first(where: {
                    $0.0.trigger == trigger && $0.0.modifiers == modifiers && $0.0.conditions == conditions && $0.0.zone == zone
                }) {
                    errors.append(.duplicateTrackpadRule(ids: [other.0.id, id]))
                }
                trackpad.append((TrackpadRule(id: id, trigger: trigger, modifiers: modifiers, action: action,
                                              priority: priority, conditions: conditions, zone: zone), order))
            case let .keyOutput(id, key, output, conditions):
                claim(id)
                if key.modifierKey != nil {
                    errors.append(.modifierKeyNotAllowed(key, id: id))
                } else if checkOutput(output, id: id) {
                    addBinding(key, .output(id: id, output), conditions, order)
                }
            case let .tapHold(id, key, tap, hold, doubleTap, settings, conditions):
                claim(id)
                var valid = checkOutput(tap, id: id) && checkOutput(hold, id: id)
                if let doubleTap, !checkOutput(doubleTap, id: id) { valid = false }
                if let modifier = key.modifierKey {
                    // A modifier key keeps working as itself; only a tap
                    // output on its own can be added.
                    if hold != .modifiers(modifier.set) || doubleTap != nil {
                        errors.append(.modifierTapHoldChangesHold(id: id))
                        valid = false
                    }
                } else {
                    switch hold {
                    case .modifiers, .layer, .key, .action(.openCompass): break
                    default:
                        errors.append(.holdOutputNotHeld(id: id))
                        valid = false
                    }
                }
                if !TapHoldSettings.holdRange.contains(settings.holdAfterMilliseconds)
                    || !TapHoldSettings.typingStreakRange.contains(settings.typingStreakMilliseconds)
                    || !TapHoldSettings.doubleTapRange.contains(settings.doubleTapMilliseconds) {
                    errors.append(.tapHoldTimingOutOfRange(id: id))
                    valid = false
                }
                if valid {
                    let binding = TapHoldBinding(id: id, tap: tap, hold: hold, doubleTap: doubleTap, settings: settings)
                    addBinding(key, .tapHold(binding), conditions, order)
                }
            case let .layerKey(id, layer, key, output, conditions):
                claim(id)
                if layer.isEmpty {
                    errors.append(.emptyLayerName(id: id))
                } else if plainKey(key, id: id), checkOutput(output, id: id) {
                    let key = source(key)
                    if layers[layer]?[key]?.contains(where: { $0.0.conditions == conditions }) == true {
                        errors.append(.duplicateRemapSource(key == .capsLockProxy ? .capsLock : key))
                    } else {
                        layers[layer, default: [:]][key, default: []]
                            .append((LayerBinding(id: id, output: output, conditions: conditions), order))
                    }
                }
            case let .combo(id, keys, output, window, conditions):
                claim(id)
                if !ComboRule.keyCount.contains(keys.count) || !ComboRule.windowRange.contains(window) {
                    errors.append(.invalidCombo(id: id))
                } else if keys.allSatisfy({ plainKey($0, id: id) }), checkOutput(output, id: id) {
                    if combos.contains(where: { $0.keys == Set(keys.map(source)) && $0.conditions == conditions }) {
                        errors.append(.invalidCombo(id: id))
                    } else {
                        combos.append(ComboRule(id: id, keys: Set(keys.map(source)), output: output,
                                                windowMilliseconds: window, conditions: conditions))
                    }
                }
            case let .sequence(id, keys, output, conditions):
                claim(id)
                if !SequenceRule.keyCount.contains(keys.count) {
                    errors.append(.invalidSequence(id: id))
                } else if keys.allSatisfy({ plainKey($0, id: id) && $0 != .escape }), checkOutput(output, id: id) {
                    sequences.append(SequenceRule(id: id, keys: keys.map(source), output: output, conditions: conditions))
                } else if keys.contains(.escape) {
                    errors.append(.invalidSequence(id: id))
                }
            case let .mouseChord(id, leader, button, action, priority, allowProtected, conditions):
                if !seenIDs.insert(id).inserted {
                    errors.append(.duplicateRuleID(id))
                }
                if button.isProtected {
                    if !allowProtected {
                        errors.append(.protectedMouseButton(button, id: id))
                    } else if case .key = leader {
                        errors.append(.protectedMouseButtonNeedsModifierLeader(button, id: id))
                    }
                }
                switch leader {
                case let .modifiers(required):
                    // Buttons 3 and up can act alone; the primary and
                    // secondary buttons always need a modifier.
                    if required.isEmpty, button.isProtected { errors.append(.emptyModifierLeader(id: id)) }
                case let .key(key, policy):
                    if key.modifierKey != nil || key == .capsLock || key == .function {
                        errors.append(.leaderIsModifierKey(key))
                    }
                    if case let .boundedWindow(ms) = policy, !LeaderPolicy.allowedWindow.contains(ms) {
                        errors.append(.leaderWindowOutOfRange(key, milliseconds: ms))
                    }
                    if !conditions.devices.isEmpty {
                        // The leader is buffered before the mouse device is
                        // known, so device scoping would be ambiguous.
                        errors.append(.deviceConditionOnLetterLeader(id: id))
                    }
                    if let existing = leaderPolicies[key], existing != policy {
                        errors.append(.conflictingLeaderPolicies(key))
                    } else {
                        leaderPolicies[key] = policy
                    }
                }
                chords.append(ChordRule(id: id, leader: leader, button: button, action: action, priority: priority, conditions: conditions))
            }
        }

        for key in leaderPolicies.keys where remaps[key] != nil || bindings[key] != nil {
            errors.append(.leaderAlsoRemapped(key))
        }
        for layer in layers.keys.sorted() where !activatedLayers.contains(layer) {
            errors.append(.layerNeverActivated(layer))
        }
        if !startsSequence, let first = sequences.first {
            errors.append(.sequenceWithoutLeader(id: first.id))
        }
        for (index, sequence) in sequences.enumerated() {
            for other in sequences[(index + 1)...] where other.conditions == sequence.conditions {
                let shorter = sequence.keys.count <= other.keys.count ? sequence : other
                let longer = sequence.keys.count <= other.keys.count ? other : sequence
                if Array(longer.keys.prefix(shorter.keys.count)) == shorter.keys {
                    errors.append(.ambiguousSequence(ids: [sequence.id, other.id]))
                }
            }
        }

        func bySpecificity<T>(_ items: [(T, Int)], _ conditions: (T) -> RuleConditions) -> [T] {
            items.sorted { lhs, rhs in
                let left = conditions(lhs.0).specificity
                let right = conditions(rhs.0).specificity
                return left != right ? left > right : lhs.1 < rhs.1
            }.map(\.0)
        }

        var byButton: [MouseButton: [ChordRule]] = [:]
        for chord in chords {
            byButton[chord.button, default: []].append(chord)
        }
        for (button, list) in byButton {
            let sorted = list.enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.priority != rhs.element.priority { return lhs.element.priority > rhs.element.priority }
                    let left = lhs.element.conditions.specificity
                    let right = rhs.element.conditions.specificity
                    return left != right ? left > right : lhs.offset < rhs.offset
                }
                .map(\.element)
            byButton[button] = sorted
            struct Signature: Hashable {
                let leader: ChordLeader
                let conditions: RuleConditions
            }
            var seen: [Signature: String] = [:]
            for chord in sorted {
                let signature = Signature(leader: chord.leader, conditions: chord.conditions)
                if let other = seen[signature] {
                    errors.append(.duplicateChord(button: button, ids: [other, chord.id]))
                } else {
                    seen[signature] = chord.id
                }
            }
        }

        if !errors.isEmpty {
            return .failure(CompileFailure(errors: errors))
        }
        return .success(CompiledRules(
            remapCandidates: remaps.mapValues { bySpecificity($0) { $0.conditions } },
            chordsByButton: byButton,
            leaderPolicies: leaderPolicies,
            wheelSettings: bySpecificity(wheel) { $0.conditions },
            trackpadRules: Dictionary(grouping: trackpad.sorted { lhs, rhs in
                if lhs.0.priority != rhs.0.priority { return lhs.0.priority > rhs.0.priority }
                // A rule for one zone wins over the same gesture anywhere.
                if (lhs.0.zone != nil) != (rhs.0.zone != nil) { return lhs.0.zone != nil }
                let left = lhs.0.conditions.specificity
                let right = rhs.0.conditions.specificity
                return left != right ? left > right : lhs.1 < rhs.1
            }.map(\.0), by: \.trigger),
            trackpadScroll: bySpecificity(continuous) { $0.conditions },
            keyBindings: bindings.mapValues { bySpecificity($0) { $0.conditions } },
            layerBindings: layers.mapValues { $0.mapValues { bySpecificity($0) { $0.conditions } } },
            combos: combos.sorted { $0.keys.count > $1.keys.count },
            sequences: sequences,
            usesCapsLock: usesCapsLock
        ))
    }
}

public struct CompileFailure: Error, Equatable, Sendable {
    public let errors: [RuleValidationError]
}

extension ChordLeader: Hashable {}
extension LeaderPolicy: Hashable {}
