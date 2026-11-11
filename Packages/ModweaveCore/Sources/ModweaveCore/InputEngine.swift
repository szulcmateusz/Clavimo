/// What the platform adapter must do in response to one input event.
public struct EngineOutput: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        /// Forward the incoming event. When `flags` is non-nil, its
        /// modifier flags must be replaced with this logical state.
        case original(flags: ModifierSet?)
        /// Emit a key event. Modifier key codes are emitted as
        /// `flagsChanged` events by the adapter.
        case key(KeyCode, isDown: Bool, isRepeat: Bool, flags: ModifierSet)
    }

    /// Ordered output. An empty list consumes the incoming event.
    public var items: [Item] = []
    /// Side effects to run outside the event callback, in order.
    public var actions: [ActionCommand] = []
    /// When non-nil, the adapter must call `handleDeadline(now:)` at or
    /// after this monotonic time (nanoseconds).
    public var nextDeadline: UInt64?

    public init(items: [Item] = [], actions: [ActionCommand] = [], nextDeadline: UInt64? = nil) {
        self.items = items
        self.actions = actions
        self.nextDeadline = nextDeadline
    }

    public var consumesOriginal: Bool {
        !items.contains { if case .original = $0 { true } else { false } }
    }
}

/// Deterministic, platform-independent input state machine.
///
/// Invariants (see docs/04-RULE-ENGINE in the planning spec):
/// - Every consumed or remapped key down is matched by exactly one
///   resolution of its key up, using the mapping that was active at key
///   down time, even after `install(_:)` swaps the rule snapshot.
/// - Output keys held by several physical keys are reference counted and
///   released only when the last holder is released.
/// - Events the engine cannot interpret are forwarded unchanged.
/// - The engine performs no I/O and never blocks; time is injected.
public struct InputEngine: Sendable {
    private struct PendingLeader: Sendable {
        let key: KeyCode
        var deadline: UInt64?
        var chorded: Bool
    }

    public private(set) var rules: CompiledRules

    private var physicalModifiers: ModifierSet = []
    /// Physical source key -> output key for remaps that are currently held.
    private var activeRemaps: [KeyCode: KeyCode] = [:]
    /// Reference counts for held non-modifier output keys.
    private var outputHolds: [KeyCode: Int] = [:]
    private var leader: PendingLeader?
    private var heldNonConsumingLeaders: Set<KeyCode> = []
    /// Buttons whose down was consumed; their up must be consumed too.
    private var consumedButtons: Set<MouseButton> = []
    /// Physical keys whose down was consumed but whose mapping no longer
    /// exists (after a reset); their repeats and up are swallowed.
    private var orphanedKeys: Set<KeyCode> = []

    public init(rules: CompiledRules = .empty) {
        self.rules = rules
    }

    /// Replaces the rule snapshot. Held activations keep the mapping they
    /// started with, so a later key up still releases the right output.
    public mutating func install(_ newRules: CompiledRules) {
        rules = newRules
    }

    /// True while any key, button, or leader is in a non-idle state.
    public var hasTransientState: Bool {
        !activeRemaps.isEmpty || leader != nil || !consumedButtons.isEmpty
            || !orphanedKeys.isEmpty || !heldNonConsumingLeaders.isEmpty
    }

    // MARK: - Event handling

    public mutating func handle(_ event: InputEvent) -> EngineOutput {
        var output = EngineOutput()
        if let pending = leader, !pending.chorded, let deadline = pending.deadline, event.time >= deadline {
            flushLeader(into: &output)
        }

        switch event.kind {
        case let .key(code, isDown, isRepeat):
            if let modifier = code.modifierKey {
                handleModifier(modifier, isDown: isDown, physical: event.modifiers, into: &output)
            } else {
                handleKey(code, isDown: isDown, isRepeat: isRepeat, physical: event.modifiers, time: event.time, into: &output)
            }
        case let .mouseButton(button, isDown):
            handleMouse(button, isDown: isDown, physical: event.modifiers, into: &output)
        }

        output.nextDeadline = pendingDeadline
        return output
    }

    /// Called by the adapter's timer. Delivers a buffered leader whose
    /// chord window has expired.
    public mutating func handleDeadline(now: UInt64) -> EngineOutput {
        var output = EngineOutput()
        if let pending = leader, !pending.chorded, let deadline = pending.deadline, now >= deadline {
            flushLeader(into: &output)
        }
        output.nextDeadline = pendingDeadline
        return output
    }

    /// Cancels all transient state, e.g. on pause, panic, session switch,
    /// or event tap loss. The returned items move the logical key state
    /// back to the physical state: remapped outputs are released and
    /// physically held modifiers are re-asserted. Buffered leaders are
    /// dropped without being typed.
    public mutating func reset() -> EngineOutput {
        var output = EngineOutput()
        let logicalBefore = logicalModifiers(for: physicalModifiers)

        if let pending = leader {
            // Never typed, or already used by a chord: swallow its up.
            orphanedKeys.insert(pending.key)
        }
        leader = nil
        heldNonConsumingLeaders.removeAll()

        for (source, target) in activeRemaps.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if source.modifierKey == nil {
                orphanedKeys.insert(source)
            }
            if target.modifierKey == nil, outputHolds[target] != nil {
                outputHolds[target] = nil
                output.items.append(.key(target, isDown: false, isRepeat: false, flags: logicalBefore))
            }
        }
        activeRemaps.removeAll()
        outputHolds.removeAll()

        appendModifierTransitions(from: logicalBefore, to: physicalModifiers, into: &output)
        // `consumedButtons` is intentionally kept: the matching button up
        // must still be swallowed if the tap remains installed.
        return output
    }

    // MARK: - Modifiers

    private mutating func handleModifier(
        _ modifier: ModifierKey,
        isDown: Bool,
        physical: ModifierSet,
        into output: inout EngineOutput
    ) {
        // A modifier change while a letter leader is buffered would make
        // the buffered key's flags ambiguous; deliver the leader first.
        if let pending = leader, !pending.chorded {
            flushLeader(into: &output)
        }

        let code = modifier.keyCode
        let logicalBefore = logicalModifiers(for: physicalModifiers)
        let unchangedFastPath = activeRemaps.isEmpty && rules.keyRemaps[code] == nil

        if isDown {
            if activeRemaps[code] == nil, let target = rules.keyRemaps[code] {
                activeRemaps[code] = target
                if target.modifierKey == nil {
                    holdOutput(target, flags: logicalModifiers(for: physical), into: &output)
                }
            }
        } else if let target = activeRemaps.removeValue(forKey: code), target.modifierKey == nil {
            releaseOutput(target, flags: logicalModifiers(for: physical), into: &output)
        }

        physicalModifiers = physical
        if unchangedFastPath {
            output.items.append(.original(flags: nil))
            return
        }
        let logicalAfter = logicalModifiers(for: physical)
        appendModifierTransitions(from: logicalBefore, to: logicalAfter, into: &output)
    }

    /// Logical modifiers = physical modifiers, minus physical modifier keys
    /// that are currently remapped, plus modifier outputs of active remaps.
    private func logicalModifiers(for physical: ModifierSet) -> ModifierSet {
        if activeRemaps.isEmpty { return physical }
        // Two passes: with a held swap (A->B and B->A) a single pass would
        // remove an output that the other half just inserted.
        var removed: ModifierSet = []
        var added: ModifierSet = []
        for (source, target) in activeRemaps {
            if let sourceModifier = source.modifierKey { removed.insert(sourceModifier.set) }
            if let targetModifier = target.modifierKey { added.insert(targetModifier.set) }
        }
        return physical.subtracting(removed).union(added)
    }

    private func appendModifierTransitions(
        from before: ModifierSet,
        to after: ModifierSet,
        into output: inout EngineOutput
    ) {
        // Fn is tracked for chord matching only; it is never emitted.
        let before = before.subtracting(.function)
        let after = after.subtracting(.function)
        guard before != after else { return }
        var current = before
        // Releases first, then presses, so a swap never shows both
        // modifiers down at once in the emitted stream.
        for key in before.subtracting(after).keys {
            current.remove(key.set)
            output.items.append(.key(key.keyCode, isDown: false, isRepeat: false, flags: current))
        }
        for key in after.subtracting(before).keys {
            current.insert(key.set)
            output.items.append(.key(key.keyCode, isDown: true, isRepeat: false, flags: current))
        }
    }

    // MARK: - Ordinary keys

    private mutating func handleKey(
        _ code: KeyCode,
        isDown: Bool,
        isRepeat: Bool,
        physical: ModifierSet,
        time: UInt64,
        into output: inout EngineOutput
    ) {
        physicalModifiers = physical
        let flags = logicalModifiers(for: physical)

        if isDown {
            if let pending = leader, pending.key != code, !pending.chorded {
                flushLeader(into: &output)
            }
            if leader?.key == code || orphanedKeys.contains(code) {
                return // swallow repeats of a buffered or orphaned key
            }
            if let target = activeRemaps[code] {
                if target.modifierKey == nil {
                    output.items.append(.key(target, isDown: true, isRepeat: true, flags: flags))
                }
                return
            }
            if !isRepeat, let target = rules.keyRemaps[code] {
                activeRemaps[code] = target
                if target.modifierKey == nil {
                    holdOutput(target, flags: flags, into: &output)
                } else {
                    appendModifierTransitions(from: flags, to: logicalModifiers(for: physical), into: &output)
                }
                return
            }
            if !isRepeat, let policy = rules.leaderPolicies[code] {
                switch policy {
                case .nonConsuming:
                    heldNonConsumingLeaders.insert(code)
                    output.items.append(.original(flags: overrideFlags(flags)))
                case let .boundedWindow(milliseconds):
                    leader = PendingLeader(key: code, deadline: time &+ UInt64(milliseconds) * 1_000_000, chorded: false)
                case .deferredUntilUp:
                    leader = PendingLeader(key: code, deadline: nil, chorded: false)
                }
                return
            }
            output.items.append(.original(flags: overrideFlags(flags)))
            return
        }

        // Key up.
        if let pending = leader, pending.key == code {
            leader = nil
            if !pending.chorded {
                // Released without a chord: deliver it as a tap.
                output.items.append(.key(code, isDown: true, isRepeat: false, flags: flags))
                output.items.append(.key(code, isDown: false, isRepeat: false, flags: flags))
            }
            return
        }
        if orphanedKeys.remove(code) != nil {
            return
        }
        if let target = activeRemaps.removeValue(forKey: code) {
            if target.modifierKey == nil {
                releaseOutput(target, flags: flags, into: &output)
            } else {
                appendModifierTransitions(from: flags, to: logicalModifiers(for: physical), into: &output)
            }
            return
        }
        heldNonConsumingLeaders.remove(code)
        output.items.append(.original(flags: overrideFlags(flags)))
    }

    private mutating func holdOutput(_ key: KeyCode, flags: ModifierSet, into output: inout EngineOutput) {
        let count = outputHolds[key, default: 0]
        outputHolds[key] = count + 1
        if count == 0 {
            output.items.append(.key(key, isDown: true, isRepeat: false, flags: flags))
        }
    }

    private mutating func releaseOutput(_ key: KeyCode, flags: ModifierSet, into output: inout EngineOutput) {
        guard let count = outputHolds[key] else { return }
        if count <= 1 {
            outputHolds[key] = nil
            output.items.append(.key(key, isDown: false, isRepeat: false, flags: flags))
        } else {
            outputHolds[key] = count - 1
        }
    }

    // MARK: - Leaders

    private var pendingDeadline: UInt64? {
        guard let pending = leader, !pending.chorded else { return nil }
        return pending.deadline
    }

    /// Delivers a buffered leader key down; the leader then behaves as an
    /// ordinary held key and can no longer start a chord.
    private mutating func flushLeader(into output: inout EngineOutput) {
        guard let pending = leader, !pending.chorded else { return }
        leader = nil
        output.items.append(.key(pending.key, isDown: true, isRepeat: false, flags: logicalModifiers(for: physicalModifiers)))
    }

    // MARK: - Mouse buttons

    private mutating func handleMouse(
        _ button: MouseButton,
        isDown: Bool,
        physical: ModifierSet,
        into output: inout EngineOutput
    ) {
        physicalModifiers = physical
        let flags = logicalModifiers(for: physical)

        guard isDown else {
            if consumedButtons.remove(button) == nil {
                output.items.append(.original(flags: overrideFlags(flags)))
            }
            return
        }

        if consumedButtons.contains(button) {
            return // a second down without an up; keep it consumed
        }

        for chord in rules.chordsByButton[button] ?? [] where chordLeaderIsHeld(chord.leader, physical: physical) {
            if case let .key(key, _) = chord.leader, leader?.key == key {
                leader?.chorded = true
                leader?.deadline = nil
            }
            consumedButtons.insert(button)
            output.actions.append(chord.action)
            return
        }
        output.items.append(.original(flags: overrideFlags(flags)))
    }

    private func chordLeaderIsHeld(_ chordLeader: ChordLeader, physical: ModifierSet) -> Bool {
        switch chordLeader {
        case let .modifiers(required):
            return physical.generic == required
        case let .key(key, _):
            return leader?.key == key || heldNonConsumingLeaders.contains(key)
        }
    }

    /// Returns nil when the event's own flags are already correct.
    private func overrideFlags(_ logical: ModifierSet) -> ModifierSet? {
        logical == physicalModifiers ? nil : logical
    }
}
