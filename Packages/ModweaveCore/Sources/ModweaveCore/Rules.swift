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

/// A user-level rule before compilation.
public enum RuleDefinition: Equatable, Sendable {
    case remap(from: KeyCode, to: KeyCode)
    /// Bidirectional swap; compiles to two remaps.
    case swap(KeyCode, KeyCode)
    /// `allowProtectedButton` must be set explicitly for the primary or
    /// secondary button; only modifier leaders may use them.
    case mouseChord(
        id: String,
        leader: ChordLeader,
        button: MouseButton,
        action: ActionCommand,
        priority: Int,
        allowProtectedButton: Bool = false
    )
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
}

public struct ChordRule: Equatable, Sendable {
    public let id: String
    public let leader: ChordLeader
    public let button: MouseButton
    public let action: ActionCommand
    public let priority: Int
}

/// An immutable, validated rule snapshot optimized for lookups on the
/// event path: every lookup is a dictionary access keyed by the input.
public struct CompiledRules: Equatable, Sendable {
    public let keyRemaps: [KeyCode: KeyCode]
    /// Chord candidates per button, highest priority first; ties keep
    /// definition order so evaluation is deterministic.
    public let chordsByButton: [MouseButton: [ChordRule]]
    public let leaderPolicies: [KeyCode: LeaderPolicy]

    public static let empty = CompiledRules(keyRemaps: [:], chordsByButton: [:], leaderPolicies: [:])

    public var isEmpty: Bool {
        keyRemaps.isEmpty && chordsByButton.isEmpty
    }

    /// Whether any rule needs the primary or secondary mouse button, which
    /// are otherwise kept out of the event tap mask.
    public var observesProtectedButtons: Bool {
        chordsByButton.keys.contains { $0.isProtected }
    }

    public static func compile(_ definitions: [RuleDefinition]) -> Result<CompiledRules, CompileFailure> {
        var errors: [RuleValidationError] = []
        var remaps: [KeyCode: KeyCode] = [:]
        var chords: [ChordRule] = []
        var leaderPolicies: [KeyCode: LeaderPolicy] = [:]
        var seenIDs: Set<String> = []

        func addRemap(_ from: KeyCode, _ to: KeyCode) {
            if remaps[from] != nil {
                errors.append(.duplicateRemapSource(from))
            } else {
                remaps[from] = to
            }
        }

        for definition in definitions {
            switch definition {
            case let .remap(from, to):
                if from == to {
                    errors.append(.remapToItself(from))
                } else {
                    addRemap(from, to)
                }
            case let .swap(first, second):
                if first == second {
                    errors.append(.swapWithItself(first))
                } else {
                    addRemap(first, second)
                    addRemap(second, first)
                }
            case let .mouseChord(id, leader, button, action, priority, allowProtected):
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
                    if let existing = leaderPolicies[key], existing != policy {
                        errors.append(.conflictingLeaderPolicies(key))
                    } else {
                        leaderPolicies[key] = policy
                    }
                }
                chords.append(ChordRule(id: id, leader: leader, button: button, action: action, priority: priority))
            }
        }

        for key in leaderPolicies.keys where remaps[key] != nil {
            errors.append(.leaderAlsoRemapped(key))
        }

        var byButton: [MouseButton: [ChordRule]] = [:]
        for chord in chords {
            byButton[chord.button, default: []].append(chord)
        }
        for (button, list) in byButton {
            // Stable sort: equal priorities keep definition order.
            let sorted = list.enumerated()
                .sorted { lhs, rhs in
                    lhs.element.priority != rhs.element.priority
                        ? lhs.element.priority > rhs.element.priority
                        : lhs.offset < rhs.offset
                }
                .map(\.element)
            byButton[button] = sorted
            var seenLeaders: [ChordLeader: String] = [:]
            for chord in sorted {
                if let other = seenLeaders[chord.leader] {
                    errors.append(.duplicateChord(button: button, ids: [other, chord.id]))
                } else {
                    seenLeaders[chord.leader] = chord.id
                }
            }
        }

        if !errors.isEmpty {
            return .failure(CompileFailure(errors: errors))
        }
        return .success(CompiledRules(keyRemaps: remaps, chordsByButton: byButton, leaderPolicies: leaderPolicies))
    }
}

public struct CompileFailure: Error, Equatable, Sendable {
    public let errors: [RuleValidationError]
}

extension ChordLeader: Hashable {}
extension LeaderPolicy: Hashable {}
