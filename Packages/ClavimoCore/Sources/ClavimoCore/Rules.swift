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

    public init(onlyApps: Set<String> = [], exceptApps: Set<String> = [], devices: Set<DeviceID> = []) {
        self.onlyApps = onlyApps
        self.exceptApps = exceptApps
        self.devices = devices
    }

    public static let always = RuleConditions()

    public var isEmpty: Bool { onlyApps.isEmpty && exceptApps.isEmpty && devices.isEmpty }

    /// More specific rules win over general ones with the same trigger.
    var specificity: Int {
        (onlyApps.isEmpty ? 0 : 2) + (exceptApps.isEmpty ? 0 : 1) + (devices.isEmpty ? 0 : 4)
    }

    public func matches(app: String?, device: DeviceID?) -> Bool {
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
        conditions: RuleConditions = .always
    )
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
        case let .trackpad(_, trigger, modifiers, _, _, conditions):
            ["trackpad:\(trigger.signature):\(modifiers.rawValue):\(conditions.signature)"]
        }
    }
}

extension RuleConditions {
    var signature: String {
        [onlyApps.sorted().joined(separator: ","), exceptApps.sorted().joined(separator: ","),
         devices.sorted().map(\.description).joined(separator: ",")].joined(separator: "|")
    }
}

extension TrackpadTrigger {
    var signature: String {
        switch self {
        case let .gesture(.tap(fingers)): "tap\(fingers)"
        case let .gesture(.tipTap(side)): "tiptap-\(side.rawValue)"
        case let .gesture(.swipe(fingers, direction)): "swipe\(fingers)-\(direction.rawValue)"
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

    public init(
        remapCandidates: [KeyCode: [RemapCandidate]],
        chordsByButton: [MouseButton: [ChordRule]],
        leaderPolicies: [KeyCode: LeaderPolicy],
        wheelSettings: [WheelSettings],
        trackpadRules: [TrackpadTrigger: [TrackpadRule]] = [:],
        trackpadScroll: [ContinuousScrollRule] = []
    ) {
        self.trackpadScroll = trackpadScroll
        self.remapCandidates = remapCandidates
        self.chordsByButton = chordsByButton
        self.leaderPolicies = leaderPolicies
        self.wheelSettings = wheelSettings
        self.trackpadRules = trackpadRules
    }

    public static let empty = CompiledRules(remapCandidates: [:], chordsByButton: [:], leaderPolicies: [:], wheelSettings: [])

    public var isEmpty: Bool {
        remapCandidates.isEmpty && chordsByButton.isEmpty && wheelSettings.isEmpty && trackpadRules.isEmpty
            && trackpadScroll.isEmpty
    }

    /// Whether any rule needs trackpad touches, so the touch backend runs.
    public var observesTrackpad: Bool { !trackpadRules.isEmpty }

    /// Whether any rule replaces physical trackpad clicks, which needs the
    /// primary and secondary buttons in the event tap mask.
    public var observesTrackpadClicks: Bool {
        trackpadRules.keys.contains { if case .gesture = $0 { false } else { true } }
    }

    /// The rule for a gesture under the held modifiers in `app`.
    public func trackpadRule(for trigger: TrackpadTrigger, modifiers: GenericModifiers, app: String?) -> TrackpadRule? {
        trackpadRules[trigger]?.first { $0.modifiers == modifiers && $0.conditions.matches(app: app, device: nil) }
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

    public func trackpadScrollSettings(app: String?) -> TrackpadScrollSettings? {
        trackpadScroll.first { $0.conditions.matches(app: app, device: nil) }?.settings
    }

    /// Whether any rule depends on knowing the physical device, which
    /// requires device attribution in the platform adapter.
    public var usesDeviceConditions: Bool {
        remapCandidates.values.contains { $0.contains { !$0.conditions.devices.isEmpty } }
            || chordsByButton.values.contains { $0.contains { !$0.conditions.devices.isEmpty } }
            || wheelSettings.contains { !$0.conditions.devices.isEmpty }
    }

    /// Keys whose rules have device conditions; only these need a device
    /// lookup on the event path.
    public var keysNeedingDevice: Set<KeyCode> {
        Set(remapCandidates.filter { $0.value.contains { !$0.conditions.devices.isEmpty } }.keys)
    }

    public var buttonsNeedingDevice: Set<MouseButton> {
        Set(chordsByButton.filter { $0.value.contains { !$0.conditions.devices.isEmpty } }.keys)
    }

    public func remapTarget(for key: KeyCode, app: String?, device: DeviceID?) -> KeyCode? {
        guard let candidates = remapCandidates[key] else { return nil }
        return candidates.first { $0.conditions.matches(app: app, device: device) }?.target
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
        var seenIDs: Set<String> = []

        func addRemap(_ from: KeyCode, _ to: KeyCode, _ conditions: RuleConditions, _ order: Int) {
            for key in [from, to] where key == .capsLock || key == .function {
                errors.append(.unsupportedKey(key))
                return
            }
            if remaps[from]?.contains(where: { $0.0.conditions == conditions }) == true {
                errors.append(.duplicateRemapSource(from))
            } else {
                remaps[from, default: []].append((RemapCandidate(target: to, conditions: conditions), order))
            }
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
            case let .trackpad(id, trigger, modifiers, action, priority, conditions):
                if !seenIDs.insert(id).inserted {
                    errors.append(.duplicateRuleID(id))
                }
                let fingersValid = switch trigger {
                case let .gesture(.tap(fingers)): TrackpadTrigger.tapFingers.contains(fingers)
                case let .gesture(.swipe(fingers, _)): TrackpadTrigger.swipeFingers.contains(fingers)
                case let .click(fingers): TrackpadTrigger.clickFingers.contains(fingers)
                case .gesture(.tipTap), .cornerClick: true
                }
                if !fingersValid {
                    errors.append(.trackpadFingersOutOfRange(id: id))
                } else if trigger == .gesture(.tap(fingers: 2)), modifiers.isEmpty {
                    errors.append(.twoFingerTapNeedsModifiers(id: id))
                }
                if let other = trackpad.first(where: {
                    $0.0.trigger == trigger && $0.0.modifiers == modifiers && $0.0.conditions == conditions
                }) {
                    errors.append(.duplicateTrackpadRule(ids: [other.0.id, id]))
                }
                trackpad.append((TrackpadRule(id: id, trigger: trigger, modifiers: modifiers, action: action,
                                              priority: priority, conditions: conditions), order))
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
                    if required.isEmpty { errors.append(.emptyModifierLeader(id: id)) }
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

        for key in leaderPolicies.keys where remaps[key] != nil {
            errors.append(.leaderAlsoRemapped(key))
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
                let left = lhs.0.conditions.specificity
                let right = rhs.0.conditions.specificity
                return left != right ? left > right : lhs.1 < rhs.1
            }.map(\.0), by: \.trigger),
            trackpadScroll: bySpecificity(continuous) { $0.conditions }
        ))
    }
}

public struct CompileFailure: Error, Equatable, Sendable {
    public let errors: [RuleValidationError]
}

extension ChordLeader: Hashable {}
extension LeaderPolicy: Hashable {}
