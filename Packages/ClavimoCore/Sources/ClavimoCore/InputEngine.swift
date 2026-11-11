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
/// - Keys held back while a decision is pending (tap-hold, combos) are
///   delivered in their original order once it is made, and never later
///   than their deadline.
/// - The engine performs no I/O and never blocks; time is injected.
public struct InputEngine: Sendable {
    private struct PendingLeader: Sendable {
        let key: KeyCode
        var deadline: UInt64?
        var chorded: Bool
    }

    /// A tap-hold key waiting to learn whether it is a tap or a hold.
    private struct PendingTapHold: Sendable {
        let key: KeyCode
        let binding: TapHoldBinding
        let deadline: UInt64
        /// Events that arrived meanwhile, delivered after the decision.
        var buffered: [InputEvent] = []

        func hasBufferedDown(_ code: KeyCode) -> Bool {
            buffered.contains { if case .key(code, true, false) = $0.kind { true } else { false } }
        }
    }

    private struct PendingCombo: Sendable {
        var events: [InputEvent]
        var keys: Set<KeyCode>
        let deadline: UInt64
    }

    private struct PendingDoubleTap: Sendable {
        let key: KeyCode
        let binding: TapHoldBinding
        let deadline: UInt64
    }

    private struct SequenceState: Sendable {
        var path: [KeyCode]
        var deadline: UInt64
    }

    /// A modifier key with a tap output, pressed with nothing else yet.
    private struct AloneCandidate: Sendable {
        let key: KeyCode
        let output: KeyOutput
        let deadline: UInt64
    }

    /// Who holds an output: a physical key, or a combo or one-off output.
    private enum Owner: Hashable, Sendable {
        case key(KeyCode)
        case group(Int)
    }

    /// What an owner is doing after its press was handled by a key behavior.
    private enum Held: Equatable, Sendable {
        case key(KeyCode, extra: ModifierSet)
        case modifiers(ModifierSet)
        case layer(String)
        /// Swallow repeats and the release.
        case nothing
        /// One key of a combo; the combo's output lives in this group.
        case comboPart(Int)
    }

    private struct ActiveLayer: Sendable {
        /// Nil for a toggled layer.
        let owner: Owner?
        let name: String
    }

    public private(set) var rules: CompiledRules
    /// Bundle ID of the frontmost app, updated by the adapter from
    /// workspace notifications (never looked up on the event path).
    public private(set) var frontmostApp: String?
    /// The selected keyboard input source, updated by the adapter.
    public private(set) var inputSource: String?

    private var physicalModifiers: ModifierSet = []
    /// The physical state of the most recent event, including events that
    /// are still held back.
    private var latestPhysical: ModifierSet = []
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

    private var held: [Owner: Held] = [:]
    private var nextGroup = 0
    private var layers: [ActiveLayer] = []
    private var oneShot: ModifierSet = []
    private var oneShotDeadline: UInt64?
    /// Keys (or one-off outputs) that took the one-shot modifiers, until
    /// they are released. These modifiers only change the flags of the
    /// holder's own events; no modifier key is pressed for them.
    private var oneShotHolders: [Owner: ModifierSet] = [:]
    private var pendingTapHold: PendingTapHold?
    private var pendingCombo: PendingCombo?
    private var pendingDoubleTap: PendingDoubleTap?
    private var sequence: SequenceState?
    private var aloneCandidate: AloneCandidate?
    /// The last ordinary key press, for the typing streak check, and the
    /// time of the press before it (a replayed press must not count itself).
    private var lastKeyDown: (key: KeyCode, time: UInt64)?
    private var keyDownBeforeLast: UInt64?
    private var lastTap: (key: KeyCode, time: UInt64)?
    /// Set while held-back events are replayed after a combo did not form.
    private var suppressCombos = false

    /// One-shot modifiers expire after this long without a key.
    public static let oneShotTimeoutMilliseconds = 3000

    public init(rules: CompiledRules = .empty) {
        self.rules = rules
    }

    public mutating func setFrontmostApp(_ bundleID: String?) {
        frontmostApp = bundleID
    }

    public mutating func setInputSource(_ identifier: String?) {
        inputSource = identifier
    }

    /// Wheel settings for a scroll event, or nil to leave it unchanged.
    /// Continuous (trackpad and Magic Mouse) scrolling is never changed.
    public func wheelSettings(isContinuous: Bool, device: DeviceID?) -> WheelSettings? {
        guard !isContinuous else { return nil }
        return rules.wheelSettings(app: frontmostApp, device: device)
    }

    /// Settings for continuous (trackpad) scrolling in the frontmost app,
    /// or nil to leave it unchanged.
    public func trackpadScrollSettings() -> TrackpadScrollSettings? {
        rules.trackpadScrollSettings(app: frontmostApp)
    }

    /// Replaces the rule snapshot. Held activations keep the mapping they
    /// started with, so a later key up still releases the right output.
    public mutating func install(_ newRules: CompiledRules) {
        rules = newRules
    }

    /// True while any key, button, or leader is in a non-idle state.
    /// Toggled layers are a mode the user chose, not transient state.
    public var hasTransientState: Bool {
        !activeRemaps.isEmpty || leader != nil || !consumedButtons.isEmpty
            || !orphanedKeys.isEmpty || !heldNonConsumingLeaders.isEmpty
            || !held.isEmpty || layers.contains { $0.owner != nil } || !oneShot.isEmpty || !oneShotHolders.isEmpty
            || pendingTapHold != nil || pendingCombo != nil || pendingDoubleTap != nil || sequence != nil
    }

    /// Active layers, a sequence in progress and pending one-shot modifiers.
    public var overlay: KeyboardOverlay {
        var result = KeyboardOverlay()
        for layer in layers where !result.layers.contains(layer.name) {
            result.layers.append(layer.name)
        }
        if let sequence {
            result.sequence = sequence.path
            result.sequenceOptions = rules.sequences
                .filter { $0.keys.starts(with: sequence.path) && matches($0.conditions) }
                .map { (keys: Array($0.keys.dropFirst(sequence.path.count)), output: $0.output) }
        }
        result.oneShot = oneShot
        return result
    }

    // MARK: - Event handling

    public mutating func handle(_ event: InputEvent) -> EngineOutput {
        var output = EngineOutput()
        latestPhysical = event.modifiers
        expireDeadlines(now: event.time, into: &output)
        process(event, into: &output)
        output.nextDeadline = pendingDeadline
        return output
    }

    /// Called by the adapter's timer. Makes every decision whose deadline
    /// has passed: buffered leaders, tap-hold keys, combos and sequences.
    public mutating func handleDeadline(now: UInt64) -> EngineOutput {
        var output = EngineOutput()
        expireDeadlines(now: now, into: &output)
        output.nextDeadline = pendingDeadline
        return output
    }

    /// Cancels all transient state, e.g. on pause, panic, session switch,
    /// or event tap loss. The returned items move the logical key state
    /// back to the physical state: remapped outputs are released and
    /// physically held modifiers are re-asserted. Buffered and held-back
    /// keys are dropped without being typed.
    public mutating func reset() -> EngineOutput {
        var output = EngineOutput()

        // Held-back presses are dropped (their releases are swallowed
        // later), but held-back releases still release what they held.
        var heldBack = pendingCombo?.events ?? []
        if let pending = pendingTapHold {
            orphanedKeys.insert(pending.key)
            heldBack += pending.buffered
        }
        pendingTapHold = nil
        pendingCombo = nil
        for event in heldBack {
            guard case let .key(code, isDown, isRepeat) = event.kind, code.modifierKey == nil else { continue }
            if isDown {
                if !isRepeat { orphanedKeys.insert(code) }
            } else {
                // Held-back modifier changes are applied below, so the
                // release carries the modifiers apps have seen so far.
                var release = event
                release.modifiers = physicalModifiers
                replay([release], into: &output)
            }
        }

        let logicalBefore = logicalModifiers(for: physicalModifiers)

        if let pending = leader {
            // Never typed, or already used by a chord: swallow its up.
            orphanedKeys.insert(pending.key)
        }
        leader = nil
        heldNonConsumingLeaders.removeAll()

        pendingDoubleTap = nil
        sequence = nil
        aloneCandidate = nil
        oneShot = []
        oneShotDeadline = nil
        oneShotHolders.removeAll()
        for case let .key(code) in held.keys where code.modifierKey == nil {
            orphanedKeys.insert(code)
        }
        held.removeAll()
        layers.removeAll()

        for source in activeRemaps.keys where source.modifierKey == nil {
            orphanedKeys.insert(source)
        }
        activeRemaps.removeAll()
        for key in outputHolds.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            output.items.append(.key(key, isDown: false, isRepeat: false, flags: logicalBefore))
        }
        outputHolds.removeAll()

        physicalModifiers = latestPhysical
        appendModifierTransitions(from: logicalBefore, to: physicalModifiers, into: &output)
        // `consumedButtons` is intentionally kept: the matching button up
        // must still be swallowed if the tap remains installed.
        return output
    }

    /// Routes one event, after any pending decision had a chance to take it.
    private mutating func process(_ event: InputEvent, into output: inout EngineOutput) {
        switch event.kind {
        case let .key(code, isDown, isRepeat):
            if isDown, !isRepeat, let pending = pendingDoubleTap, pending.key != code || !isDoubleTapPress(code) {
                pendingDoubleTap = nil
                tapOnce(pending.binding.tap, time: event.time, into: &output)
            }
            // A decision that replays held-back keys can start a new one;
            // the event must then be offered to that one as well.
            for _ in 0..<16 {
                if let pending = pendingTapHold {
                    if takenByPendingTapHold(event, into: &output) { return }
                    if let current = pendingTapHold, current.key != pending.key || current.deadline != pending.deadline { continue }
                }
                if pendingCombo != nil, !suppressCombos {
                    if takenByPendingCombo(event, into: &output) { return }
                    if pendingTapHold != nil { continue }
                }
                break
            }
            if let modifier = code.modifierKey {
                handleModifier(modifier, isDown: isDown, physical: event.modifiers, time: event.time, device: event.device, into: &output)
            } else {
                handleKey(code, isDown: isDown, isRepeat: isRepeat, physical: event.modifiers, time: event.time, device: event.device, into: &output)
            }
        case let .mouseButton(button, isDown):
            // Mouse events cannot be held back with the keys, so held-back
            // keys go first: their modifiers must reach apps before the click.
            if isDown || pendingTapHold?.buffered.isEmpty == false || pendingCombo != nil {
                settleBeforeClick(time: event.time, into: &output)
            }
            handleMouse(button, isDown: isDown, physical: event.modifiers, device: event.device, touch: event.touch, into: &output)
        }
    }

    /// Whether pressing `code` now reaches its tap-hold double tap, rather
    /// than a sequence, combo, layer or a reloaded rule.
    private func isDoubleTapPress(_ code: KeyCode) -> Bool {
        guard sequence == nil, !orphanedKeys.contains(code), held[.key(code)] == nil else { return false }
        if rules.comboKeys.contains(code), rules.combos.contains(where: { $0.keys.contains(code) && matches($0.conditions) }) {
            return false
        }
        if layers.contains(where: { rules.layerBinding(layer: $0.name, key: code, app: frontmostApp, inputSource: inputSource) != nil }) {
            return false
        }
        if case let .tapHold(binding)? = rules.keyBinding(for: code, app: frontmostApp, device: nil, inputSource: inputSource)?.behavior {
            return binding.doubleTap != nil
        }
        return false
    }

    /// Re-runs held-back events. Their originals were consumed when they
    /// were held back, so forwarding one means emitting a copy.
    private mutating func replay(_ events: [InputEvent], into output: inout EngineOutput) {
        for event in events {
            var step = EngineOutput()
            process(event, into: &step)
            for item in step.items {
                if case let .original(flags) = item {
                    if case let .key(code, isDown, isRepeat) = event.kind {
                        output.items.append(.key(code, isDown: isDown, isRepeat: isRepeat, flags: flags ?? event.modifiers))
                    }
                } else {
                    output.items.append(item)
                }
            }
            output.actions += step.actions
        }
    }

    private mutating func expireDeadlines(now: UInt64, into output: inout EngineOutput) {
        // Replayed events can start new decisions with deadlines that have
        // passed already, so repeat until nothing is due.
        for _ in 0..<16 {
            if let pending = pendingCombo, now >= pending.deadline {
                flushCombo(into: &output)
            } else if let pending = pendingTapHold, now >= pending.deadline {
                pendingTapHold = nil
                press(pending.binding.hold, owner: .key(pending.key), time: now, into: &output)
                replay(pending.buffered, into: &output)
            } else if let pending = pendingDoubleTap, now >= pending.deadline {
                pendingDoubleTap = nil
                tapOnce(pending.binding.tap, time: now, into: &output)
            } else {
                break
            }
        }
        if let current = sequence, now >= current.deadline {
            sequence = nil
        }
        if let deadline = oneShotDeadline, now >= deadline {
            oneShot = []
            oneShotDeadline = nil
        }
        if let pending = leader, !pending.chorded, let deadline = pending.deadline, now >= deadline {
            flushLeader(into: &output)
        }
    }

    private var pendingDeadline: UInt64? {
        var deadlines: [UInt64] = []
        if let pending = leader, !pending.chorded, let deadline = pending.deadline { deadlines.append(deadline) }
        if let pending = pendingTapHold { deadlines.append(pending.deadline) }
        if let pending = pendingCombo { deadlines.append(pending.deadline) }
        if let pending = pendingDoubleTap { deadlines.append(pending.deadline) }
        if let sequence { deadlines.append(sequence.deadline) }
        if let oneShotDeadline { deadlines.append(oneShotDeadline) }
        return deadlines.min()
    }

    private func matches(_ conditions: RuleConditions, device: DeviceID? = nil) -> Bool {
        conditions.matches(app: frontmostApp, device: device, inputSource: inputSource)
    }

    // MARK: - Modifiers

    private mutating func handleModifier(
        _ modifier: ModifierKey,
        isDown: Bool,
        physical: ModifierSet,
        time: UInt64,
        device: DeviceID?,
        into output: inout EngineOutput
    ) {
        // A modifier change while a letter leader is buffered would make
        // the buffered key's flags ambiguous; deliver the leader first.
        if let pending = leader, !pending.chorded {
            flushLeader(into: &output)
        }

        let code = modifier.keyCode
        let logicalBefore = logicalModifiers(for: physicalModifiers)
        let hadActiveRemaps = !activeRemaps.isEmpty
        var tapAlone: KeyOutput?

        if isDown {
            aloneCandidate = nil
            if case let .tapHold(binding)? = rules.keyBinding(for: code, app: frontmostApp, device: device, inputSource: inputSource)?.behavior {
                aloneCandidate = AloneCandidate(
                    key: code, output: binding.tap,
                    deadline: time &+ UInt64(binding.settings.holdAfterMilliseconds) * 1_000_000
                )
            }
            if activeRemaps[code] == nil, let target = rules.remapTarget(for: code, app: frontmostApp, device: device, inputSource: inputSource) {
                activeRemaps[code] = target
                if target.modifierKey == nil {
                    holdOutput(target, flags: logicalModifiers(for: physical), into: &output)
                }
            }
        } else {
            if let candidate = aloneCandidate, candidate.key == code, time <= candidate.deadline {
                tapAlone = candidate.output
            }
            aloneCandidate = nil
            if let target = activeRemaps.removeValue(forKey: code), target.modifierKey == nil {
                releaseOutput(target, flags: logicalModifiers(for: physical), into: &output)
            }
        }

        physicalModifiers = physical
        if !hadActiveRemaps && activeRemaps.isEmpty && heldModifiers.isEmpty {
            // No remap before or after this event (including a device- or
            // app-scoped rule that did not match): forward it untouched.
            output.items.append(passThroughOriginal)
        } else {
            // Emit only what changed logically: a physical Shift released
            // while a Hyper hold still holds Shift changes nothing.
            appendModifierTransitions(from: logicalBefore, to: logicalModifiers(for: physical), into: &output)
        }
        if let tapAlone {
            tapOnce(tapAlone, time: time, into: &output)
        }
    }

    /// Logical modifiers = physical modifiers, minus physical modifier keys
    /// that are currently remapped, plus modifier outputs of active remaps,
    /// plus modifiers held by tap-hold keys, layers and combos.
    private func logicalModifiers(for physical: ModifierSet) -> ModifierSet {
        var result = physical
        if !activeRemaps.isEmpty {
            // Two passes: with a held swap (A->B and B->A) a single pass would
            // remove an output that the other half just inserted.
            var removed: ModifierSet = []
            var added: ModifierSet = []
            for (source, target) in activeRemaps {
                if let sourceModifier = source.modifierKey { removed.insert(sourceModifier.set) }
                if let targetModifier = target.modifierKey { added.insert(targetModifier.set) }
            }
            result = physical.subtracting(removed).union(added)
        }
        return result.union(heldModifiers)
    }

    /// Modifiers held by key behaviors rather than by modifier keys.
    private var heldModifiers: ModifierSet {
        var result: ModifierSet = []
        for case let .modifiers(modifiers) in held.values {
            result.formUnion(modifiers)
        }
        return result
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
        device: DeviceID?,
        into output: inout EngineOutput
    ) {
        physicalModifiers = physical
        let flags = logicalModifiers(for: physical)

        if isDown {
            aloneCandidate = nil
            if let pending = leader, pending.key != code, !pending.chorded {
                flushLeader(into: &output)
            }
            if leader?.key == code || orphanedKeys.contains(code) {
                return // swallow repeats of a buffered or orphaned key
            }
            if let current = held[.key(code)] {
                if case let .key(target, extra) = current {
                    output.items.append(.key(target, isDown: true, isRepeat: true, flags: flags.union(extra)))
                }
                return
            }
            if let target = activeRemaps[code] {
                if target.modifierKey == nil {
                    output.items.append(.key(target, isDown: true, isRepeat: true, flags: flags.union(oneShotHolders[.key(code)] ?? [])))
                }
                return
            }
            if !isRepeat {
                let previousKeyDown: UInt64?
                if let last = lastKeyDown, last.key == code, last.time == time {
                    previousKeyDown = keyDownBeforeLast
                } else {
                    previousKeyDown = lastKeyDown?.time
                    keyDownBeforeLast = previousKeyDown
                    lastKeyDown = (code, time)
                }
                if handleKeyBehavior(code, time: time, previousKeyDown: previousKeyDown, device: device, into: &output) {
                    return
                }
            }
            if !isRepeat, let target = rules.remapTarget(for: code, app: frontmostApp, device: device, inputSource: inputSource) {
                takeOneShot(for: .key(code))
                activeRemaps[code] = target
                if target.modifierKey == nil {
                    holdOutput(target, flags: flags.union(oneShotHolders[.key(code)] ?? []), into: &output)
                } else {
                    appendModifierTransitions(from: flags, to: logicalModifiers(for: physical), into: &output)
                }
                return
            }
            if !isRepeat, let policy = rules.leaderPolicy(for: code, app: frontmostApp) {
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
            if code == .capsLockProxy, rules.usesCapsLock {
                // Caps Lock without a rule in this app keeps its toggle.
                if !isRepeat {
                    held[.key(code)] = .nothing
                    output.actions.append(.toggleCapsLock)
                }
                return
            }
            if !isRepeat { takeOneShot(for: .key(code)) }
            output.items.append(.original(flags: overrideFlags(logicalModifiers(for: physical).union(oneShotHolders[.key(code)] ?? []))))
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
        let oneShotFlags = oneShotHolders.removeValue(forKey: .key(code)) ?? []
        if held[.key(code)] != nil {
            end(.key(code), into: &output)
            return
        }
        if let target = activeRemaps.removeValue(forKey: code) {
            if target.modifierKey == nil {
                releaseOutput(target, flags: flags.union(oneShotFlags), into: &output)
            } else {
                appendModifierTransitions(from: flags, to: logicalModifiers(for: physical), into: &output)
            }
            return
        }
        heldNonConsumingLeaders.remove(code)
        output.items.append(.original(flags: overrideFlags(flags.union(oneShotFlags))))
    }

    /// Sequences, combos, layers and key bindings, in that order. Returns
    /// true when the key press was handled.
    private mutating func handleKeyBehavior(
        _ code: KeyCode,
        time: UInt64,
        previousKeyDown: UInt64?,
        device: DeviceID?,
        into output: inout EngineOutput
    ) -> Bool {
        if sequence != nil {
            continueSequence(with: code, time: time, into: &output)
            return true
        }
        if !suppressCombos, rules.comboKeys.contains(code) {
            let windows = rules.combos.filter { $0.keys.contains(code) && matches($0.conditions) }.map(\.windowMilliseconds)
            if let window = windows.max() {
                let event = InputEvent(kind: .key(code, isDown: true, isRepeat: false), modifiers: physicalModifiers, time: time, device: device)
                pendingCombo = PendingCombo(events: [event], keys: [code], deadline: time &+ UInt64(window) * 1_000_000)
                return true
            }
        }
        for layer in layers.reversed() {
            if let binding = rules.layerBinding(layer: layer.name, key: code, app: frontmostApp, inputSource: inputSource) {
                takeOneShot(for: .key(code))
                press(binding.output, owner: .key(code), time: time, into: &output)
                return true
            }
        }
        guard let binding = rules.keyBinding(for: code, app: frontmostApp, device: device, inputSource: inputSource) else {
            return false
        }
        switch binding.behavior {
        case let .output(_, keyOutput):
            takeOneShot(for: .key(code))
            press(keyOutput, owner: .key(code), time: time, into: &output)
        case let .tapHold(tapHold):
            beginTapHold(code, tapHold, time: time, previousKeyDown: previousKeyDown, into: &output)
        }
        return true
    }

    // MARK: - Tap-hold

    private mutating func beginTapHold(
        _ code: KeyCode,
        _ binding: TapHoldBinding,
        time: UInt64,
        previousKeyDown: UInt64?,
        into output: inout EngineOutput
    ) {
        let settings = binding.settings
        if let doubleTap = binding.doubleTap, let pending = pendingDoubleTap, pending.key == code {
            pendingDoubleTap = nil
            lastTap = nil
            press(doubleTap, owner: .key(code), time: time, into: &output)
            return
        }
        // Typing: a key pressed right after another one is a tap.
        if settings.typingStreakMilliseconds > 0, let previousKeyDown,
           time &- previousKeyDown < UInt64(settings.typingStreakMilliseconds) * 1_000_000 {
            takeOneShot(for: .key(code))
            press(binding.tap, owner: .key(code), time: time, into: &output)
            return
        }
        // Tap, then press again quickly and hold: the tap repeats.
        if binding.doubleTap == nil, let last = lastTap, last.key == code,
           time &- last.time < UInt64(settings.holdAfterMilliseconds) * 1_000_000 {
            takeOneShot(for: .key(code))
            press(binding.tap, owner: .key(code), time: time, into: &output)
            return
        }
        pendingTapHold = PendingTapHold(
            key: code, binding: binding, deadline: time &+ UInt64(settings.holdAfterMilliseconds) * 1_000_000
        )
    }

    /// Lets a pending tap-hold key see an event first. Returns true when
    /// the event was held back or fully handled.
    private mutating func takenByPendingTapHold(_ event: InputEvent, into output: inout EngineOutput) -> Bool {
        guard var pending = pendingTapHold, case let .key(code, isDown, isRepeat) = event.kind else { return false }
        let settings = pending.binding.settings

        if code == pending.key {
            if isDown { return true } // repeats while undecided
            // Released before its deadline: a tap.
            pendingTapHold = nil
            if pending.binding.doubleTap != nil {
                pendingDoubleTap = PendingDoubleTap(
                    key: code, binding: pending.binding,
                    deadline: event.time &+ UInt64(settings.doubleTapMilliseconds) * 1_000_000
                )
            } else {
                tapOnce(pending.binding.tap, time: event.time, into: &output)
                lastTap = (code, event.time)
            }
            replay(pending.buffered, into: &output)
            return true
        }

        if isDown, !isRepeat {
            if settings.oppositeHandsOnly, let own = KeyHand(pending.key), let other = KeyHand(code), own == other {
                // Same hand: a roll while typing, so the first key is a tap.
                pendingTapHold = nil
                takeOneShot(for: .key(pending.key))
                press(pending.binding.tap, owner: .key(pending.key), time: event.time, into: &output)
                replay(pending.buffered, into: &output)
                return false
            }
            switch settings.interrupt {
            case .holdOnOtherKey:
                pendingTapHold = nil
                press(pending.binding.hold, owner: .key(pending.key), time: event.time, into: &output)
                replay(pending.buffered, into: &output)
                return false
            case .permissive, .timeOnly:
                pending.buffered.append(event)
                pendingTapHold = pending
                return true
            }
        }

        if !isDown, settings.interrupt != .timeOnly, pending.hasBufferedDown(code) {
            // Another key pressed and released inside the hold: a hold.
            pendingTapHold = nil
            press(pending.binding.hold, owner: .key(pending.key), time: event.time, into: &output)
            replay(pending.buffered, into: &output)
            return false
        }
        if pending.buffered.isEmpty {
            return false // nothing to keep in order with
        }
        pending.buffered.append(event)
        pendingTapHold = pending
        return true
    }

    // MARK: - Combos

    private mutating func takenByPendingCombo(_ event: InputEvent, into output: inout EngineOutput) -> Bool {
        guard var pending = pendingCombo, case let .key(code, isDown, isRepeat) = event.kind else { return false }
        if isDown, !isRepeat, code.modifierKey == nil, !pending.keys.contains(code) {
            let candidate = pending.keys.union([code])
            let applicable = rules.combos.filter { $0.keys.isSuperset(of: candidate) && matches($0.conditions) }
            if let combo = applicable.first(where: { $0.keys == candidate }) {
                pendingCombo = nil
                fireCombo(combo, keys: candidate, time: event.time, into: &output)
                return true
            }
            if !applicable.isEmpty {
                pending.events.append(event)
                pending.keys = candidate
                pendingCombo = pending
                return true
            }
        }
        if isDown, isRepeat, pending.keys.contains(code) {
            return true
        }
        flushCombo(into: &output)
        return false
    }

    private mutating func fireCombo(_ combo: ComboRule, keys: Set<KeyCode>, time: UInt64, into output: inout EngineOutput) {
        let group = newGroup()
        for key in keys {
            held[.key(key)] = .comboPart(group)
        }
        press(combo.output, owner: .group(group), time: time, into: &output)
    }

    /// The keys did not form a combo: deliver them as typed.
    private mutating func flushCombo(into output: inout EngineOutput) {
        guard let pending = pendingCombo else { return }
        pendingCombo = nil
        let wasSuppressed = suppressCombos
        suppressCombos = true
        replay(pending.events, into: &output)
        suppressCombos = wasSuppressed
    }

    // MARK: - Sequences

    private mutating func continueSequence(with code: KeyCode, time: UInt64, into output: inout EngineOutput) {
        guard var current = sequence else { return }
        held[.key(code)] = .nothing
        if code == .escape {
            sequence = nil
            return
        }
        current.path.append(code)
        let candidates = rules.sequences.filter { $0.keys.starts(with: current.path) && matches($0.conditions) }
        if let done = candidates.first(where: { $0.keys == current.path }) {
            sequence = nil
            tapOnce(done.output, time: time, into: &output)
        } else if candidates.isEmpty {
            sequence = nil
        } else {
            current.deadline = time &+ UInt64(SequenceRule.timeoutMilliseconds) * 1_000_000
            sequence = current
        }
    }

    // MARK: - Outputs

    private mutating func newGroup() -> Int {
        nextGroup &+= 1
        return nextGroup
    }

    /// Starts an output for `owner`. Held outputs last until `end(owner)`.
    private mutating func press(_ keyOutput: KeyOutput, owner: Owner, time: UInt64, into output: inout EngineOutput) {
        let before = logicalModifiers(for: physicalModifiers)
        switch keyOutput {
        case let .key(code, extra):
            let extraSet = ModifierSet(leftSideOf: extra)
            if let modifier = code.modifierKey {
                held[owner] = .modifiers(modifier.set.union(extraSet))
                appendModifierTransitions(from: before, to: logicalModifiers(for: physicalModifiers), into: &output)
            } else {
                let flags = extraSet.union(oneShotHolders[owner] ?? [])
                held[owner] = .key(code, extra: flags)
                holdOutput(code, flags: before.union(flags), into: &output)
            }
        case let .modifiers(modifiers):
            held[owner] = .modifiers(modifiers)
            appendModifierTransitions(from: before, to: logicalModifiers(for: physicalModifiers), into: &output)
        case let .layer(name):
            held[owner] = .layer(name)
            layers.append(ActiveLayer(owner: owner, name: name))
        case let .toggleLayer(name):
            held[owner] = .nothing
            if let index = layers.firstIndex(where: { $0.owner == nil && $0.name == name }) {
                layers.remove(at: index)
            } else {
                layers.append(ActiveLayer(owner: nil, name: name))
            }
        case let .oneShot(modifiers):
            held[owner] = .nothing
            if oneShot == modifiers {
                oneShot = []
                oneShotDeadline = nil
            } else {
                oneShot.formUnion(modifiers)
                oneShotDeadline = time &+ UInt64(Self.oneShotTimeoutMilliseconds) * 1_000_000
            }
        case .startSequence:
            held[owner] = .nothing
            sequence = SequenceState(path: [], deadline: time &+ UInt64(SequenceRule.timeoutMilliseconds) * 1_000_000)
        case let .action(action):
            held[owner] = .nothing
            output.actions.append(action)
        case .none:
            held[owner] = .nothing
        }
    }

    /// Ends what `owner` holds.
    private mutating func end(_ owner: Owner, into output: inout EngineOutput) {
        oneShotHolders[owner] = nil
        guard let current = held.removeValue(forKey: owner) else { return }
        switch current {
        case let .key(code, extra):
            releaseOutput(code, flags: logicalModifiers(for: physicalModifiers).union(extra), into: &output)
        case .modifiers:
            held[owner] = current
            let before = logicalModifiers(for: physicalModifiers)
            held[owner] = nil
            appendModifierTransitions(from: before, to: logicalModifiers(for: physicalModifiers), into: &output)
        case .layer:
            layers.removeAll { $0.owner == owner }
        case let .comboPart(group):
            end(.group(group), into: &output)
        case .nothing:
            break
        }
    }

    /// Presses and releases an output at once. A typed key takes pending
    /// one-shot modifiers.
    private mutating func tapOnce(_ keyOutput: KeyOutput, time: UInt64, into output: inout EngineOutput) {
        let owner = Owner.group(newGroup())
        if case .key = keyOutput { takeOneShot(for: owner) }
        press(keyOutput, owner: owner, time: time, into: &output)
        end(owner, into: &output)
    }

    /// The next key takes pending one-shot modifiers until it is released.
    private mutating func takeOneShot(for owner: Owner) {
        guard !oneShot.isEmpty else { return }
        oneShotHolders[owner] = oneShot
        oneShot = []
        oneShotDeadline = nil
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

    /// Delivers a buffered leader key down; the leader then behaves as an
    /// ordinary held key and can no longer start a chord.
    private mutating func flushLeader(into output: inout EngineOutput) {
        guard let pending = leader, !pending.chorded else { return }
        leader = nil
        output.items.append(.key(pending.key, isDown: true, isRepeat: false, flags: logicalModifiers(for: physicalModifiers)))
    }

    // MARK: - Mouse buttons

    /// A click decides every pending key: tap-hold keys become holds, so
    /// a held home row modifier works with the click.
    private mutating func settleBeforeClick(time: UInt64, into output: inout EngineOutput) {
        aloneCandidate = nil
        // Replayed keys can start new decisions; settle those too.
        for _ in 0..<16 {
            if pendingCombo != nil {
                flushCombo(into: &output)
            } else if let pending = pendingTapHold {
                pendingTapHold = nil
                press(pending.binding.hold, owner: .key(pending.key), time: time, into: &output)
                replay(pending.buffered, into: &output)
            } else {
                break
            }
        }
        if let pending = pendingDoubleTap {
            pendingDoubleTap = nil
            tapOnce(pending.binding.tap, time: time, into: &output)
        }
        sequence = nil
    }

    private mutating func handleMouse(
        _ button: MouseButton,
        isDown: Bool,
        physical: ModifierSet,
        device: DeviceID?,
        touch: TouchSnapshot?,
        into output: inout EngineOutput
    ) {
        physicalModifiers = physical
        var flags = logicalModifiers(for: physical)

        guard isDown else {
            if consumedButtons.remove(button) == nil {
                output.items.append(.original(flags: overrideFlags(flags)))
            }
            return
        }

        if consumedButtons.contains(button) {
            return // a second down without an up; keep it consumed
        }

        // Physical modifiers plus those held by key behaviors; remapped
        // modifier keys still count as the physical key for chords.
        let chordModifiers = physical.union(heldModifiers).union(oneShot)

        if button.isProtected, let touch, let rule = trackpadClickRule(for: touch, modifiers: chordModifiers) {
            consumedButtons.insert(button)
            output.actions.append(rule.action)
            oneShot = []
            return
        }

        for chord in rules.chordsByButton[button] ?? []
        where chordLeaderIsHeld(chord.leader, modifiers: chordModifiers) && matches(chord.conditions, device: device) {
            if case let .key(key, _) = chord.leader, leader?.key == key {
                leader?.chorded = true
                leader?.deadline = nil
            }
            consumedButtons.insert(button)
            output.actions.append(chord.action)
            oneShot = []
            return
        }
        if !oneShot.isEmpty {
            flags.formUnion(oneShot)
            oneShot = []
            oneShotDeadline = nil
        }
        output.items.append(.original(flags: overrideFlags(flags)))
    }

    /// A trackpad click rule for the fingers on the trackpad: several
    /// fingers first, then a finger resting in or just tapping a corner.
    private func trackpadClickRule(for touch: TouchSnapshot, modifiers: ModifierSet) -> TrackpadRule? {
        guard rules.observesTrackpadClicks else { return nil }
        var triggers: [TrackpadTrigger] = []
        if TrackpadTrigger.clickFingers.contains(touch.fingers) { triggers.append(.click(fingers: touch.fingers)) }
        if let corner = touch.corner ?? (touch.fingers == 0 ? touch.tappedCorner : nil) {
            triggers.append(.cornerClick(corner))
        }
        for trigger in triggers {
            if let rule = rules.trackpadRule(for: trigger, modifiers: modifiers.generic, app: frontmostApp) { return rule }
        }
        return nil
    }

    // MARK: - Trackpad gestures

    /// Runs the action of the rule matching a recognized gesture under the
    /// currently held modifiers. Gestures never produce key events.
    /// `point` is where the gesture started, for rules limited to a zone.
    public mutating func handleGesture(_ gesture: GestureEvent, at point: TrackpadPoint? = nil) -> EngineOutput {
        var output = EngineOutput()
        let modifiers = physicalModifiers.union(heldModifiers).union(oneShot)
        if let rule = rules.trackpadRule(for: .gesture(gesture), modifiers: modifiers.generic, app: frontmostApp, at: point) {
            output.actions.append(rule.action)
            oneShot = []
        }
        output.nextDeadline = pendingDeadline
        return output
    }

    private func chordLeaderIsHeld(_ chordLeader: ChordLeader, modifiers: ModifierSet) -> Bool {
        switch chordLeader {
        case let .modifiers(required):
            return modifiers.generic == required
        case let .key(key, _):
            return leader?.key == key || heldNonConsumingLeaders.contains(key)
        }
    }

    private var passThroughOriginal: EngineOutput.Item { .original(flags: nil) }

    /// Returns nil when the event's own flags are already correct.
    private func overrideFlags(_ logical: ModifierSet) -> ModifierSet? {
        logical == physicalModifiers ? nil : logical
    }
}
