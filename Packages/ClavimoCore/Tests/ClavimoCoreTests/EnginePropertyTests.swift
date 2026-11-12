import Testing
@testable import ClavimoCore

/// Seeded random input sequences against several rule sets. Whatever the
/// order of presses, releases, repeats, chord windows, app switches, rule
/// reloads and resets, the engine must keep the emitted stream balanced
/// and must not leave anything held once the user lets go.
@Suite("Engine invariants under random input")
struct EnginePropertyTests {
    static let keyboardA = DeviceID(vendorID: 1452, productID: 835)
    static let keyboardB = DeviceID(vendorID: 1133, productID: 45934)

    /// Physical keys the generator presses. Remap outputs that are not
    /// themselves sources (G, V) are left out: a physical G while A is
    /// remapped to G is two keyboards typing the same key.
    static let keys: [KeyCode] = [
        .a, .c, .f, .escape, .leftArrow,
        .leftCommand, .leftOption, .rightCommand, .rightOption, .leftShift, .leftControl,
        .capsLockProxy, .space, j, k, h, section, KeyCode.digits[0], KeyCode.digits[2], .returnKey,
    ]
    static let j = KeyCode(0x26)
    static let k = KeyCode(0x28)
    static let h = KeyCode(0x04)
    static let section = KeyCode(0x0A)
    /// Outputs that no generated key produces physically.
    static let forwardDelete = KeyCode(0x75)
    static let end = KeyCode(0x77)
    static let home = KeyCode(0x73)
    static let f1 = KeyCode(0x7A)
    static let keypad1 = KeyCode(0x53)
    /// Rule sets whose outputs add modifiers to single keys (shortcuts,
    /// one-shot modifiers): flags may then exceed the modifier keys down.
    static let addsFlags: Set<Int> = [6]
    static let buttons: [MouseButton] = [.primary, .secondary, .middle, .button4, .button5]
    static let apps: [String?] = [nil, "com.apple.Safari", "com.apple.Terminal"]

    static let ruleSets: [[RuleDefinition]] = [
        [
            .swap(.leftCommand, .leftOption),
            .remap(from: .a, to: .g),
            .mouseChord(id: "ctrl", leader: .modifiers(.control), button: .button4, action: .nextWorkspace, priority: 1),
            .mouseChord(id: "f", leader: .key(.f, .boundedWindow(milliseconds: 120)), button: .button5,
                        action: .previousWorkspace, priority: 1),
        ],
        [
            .swap(.leftCommand, .leftOption, conditions: RuleConditions(onlyApps: ["com.apple.Safari"])),
            .remap(from: .a, to: .g, conditions: RuleConditions(exceptApps: ["com.apple.Terminal"])),
            .mouseChord(id: "f", leader: .key(.f, .deferredUntilUp), button: .button4, action: .missionControl, priority: 1),
            .mouseChord(id: "shift", leader: .modifiers(.shift), button: .primary, action: .nextWorkspace, priority: 1,
                        allowProtectedButton: true),
        ],
        [
            .swap(.rightCommand, .rightOption, conditions: RuleConditions(devices: [keyboardA])),
            .remap(from: .c, to: .v, conditions: RuleConditions(devices: [keyboardB])),
            .remap(from: .c, to: .g),
            .mouseChord(id: "f", leader: .key(.f, .nonConsuming), button: .button5, action: .applicationWindows, priority: 1),
            .mouseChord(id: "cmd", leader: .modifiers(.command), button: .secondary, action: .missionControl, priority: 1,
                        allowProtectedButton: true),
        ],
        [
            .remap(from: .a, to: .g),
            .remap(from: .c, to: .g),
            .swap(.leftShift, .leftControl),
            .remap(from: .escape, to: .leftCommand),
            .mouseChord(id: "a", leader: .key(.f, .boundedWindow(milliseconds: 80)), button: .button4,
                        action: .shortcut(.c, .command), priority: 1),
        ],
        [
            .swap(.leftCommand, .leftOption),
            .trackpad(id: "click3", trigger: .click(fingers: 3), action: .click(.middle)),
            .trackpad(id: "corner", trigger: .cornerClick(.topRight), modifiers: .command, action: .missionControl),
            .trackpad(id: "tap3", trigger: .gesture(.tap(fingers: 3)), action: .missionControl),
            .mouseChord(id: "ctrl", leader: .modifiers(.control), button: .primary, action: .nextWorkspace, priority: 1,
                        allowProtectedButton: true),
        ],
        [
            .tapHold(id: "caps", key: .capsLock, tap: .key(forwardDelete), hold: .modifiers(.hyper)),
            .tapHold(id: "f", key: .f, tap: .key(.f), hold: .modifiers(.leftCommand), settings: .homeRow),
            .tapHold(id: "j", key: j, tap: .key(j), hold: .modifiers(.rightCommand), settings: .homeRow),
            .tapHold(id: "space", key: .space, tap: .key(.space), hold: .layer("nav"), doubleTap: .key(.tab)),
            .layerKey(id: "h", layer: "nav", key: h, output: .key(.downArrow)),
            .layerKey(id: "nj", layer: "nav", key: j, output: .key(.upArrow)),
            .combo(id: "ck", keys: [.c, k], output: .key(end)),
            .keyOutput(id: "lead", key: section, output: .startSequence),
            .sequence(id: "a", keys: [.a], output: .key(home)),
            .sequence(id: "hk", keys: [h, k], output: .action(.missionControl)),
            .mouseChord(id: "ctrl", leader: .modifiers(.control), button: .button4, action: .nextWorkspace, priority: 1),
        ],
        [
            .swap(.leftCommand, .leftOption),
            .keyOutput(id: "os", key: section, output: .oneShot(.leftShift)),
            .keyOutput(id: "sc", key: .escape, output: .key(f1, [.command])),
            .keyOutput(id: "tg", key: h, output: .toggleLayer("num")),
            .tapHold(id: "caps", key: .capsLock, tap: .oneShot(.leftCommand), hold: .layer("num")),
            .tapHold(id: "cmd", key: .rightCommand, tap: .key(.jisEisu), hold: .modifiers(.rightCommand)),
            .layerKey(id: "a", layer: "num", key: .a, output: .key(keypad1, [.shift])),
            .combo(id: "fk", keys: [.f, k], output: .action(.missionControl)),
            .tapHold(id: "space", key: .space, tap: .key(.space), hold: .modifiers(.leftShift),
                     settings: TapHoldSettings(interrupt: .permissive)),
        ],
        [
            .keyOutput(id: "h", key: h, output: .action(.openCompass("main"))),
            .tapHold(id: "caps", key: .capsLock, tap: .key(forwardDelete), hold: .action(.openCompass("main"))),
            .mouseChord(id: "b4", leader: .modifiers([]), button: .button4, action: .openCompass("main"), priority: 1),
            .trackpad(id: "tap3", trigger: .gesture(.tap(fingers: 3)), action: .openCompass("main")),
            .remap(from: .a, to: .g),
            .swap(.leftCommand, .leftOption),
        ],
    ]

    static let compiled: [CompiledRules] = ruleSets.map { try! CompiledRules.compile($0).get() }

    @Test(arguments: 0..<8)
    func randomSequencesStayBalanced(ruleSet: Int) {
        for seed in 0..<300 {
            var run = Run(seed: UInt64(ruleSet * 100_000 + seed), rules: ruleSet)
            run.play(steps: 400)
            run.releaseEverything()
            #expect(run.violations.isEmpty, "seed \(seed): \(run.violations.prefix(3))\n\(run.traceBeforeFirstViolation)")
            #expect(run.logicalKeys.isEmpty, "seed \(seed): still down \(run.logicalKeys)")
            #expect(run.logicalButtons.isEmpty, "seed \(seed): buttons still down \(run.logicalButtons)")
            #expect(!run.engine.hasTransientState, "seed \(seed): engine not idle")
            if !run.violations.isEmpty { return }
        }
    }

    /// One random session: a simulated user plus the adapter's timer.
    struct Run {
        var rng: SplitMix64
        var engine: InputEngine
        var now: UInt64 = 1_000_000_000
        var deadline: UInt64?
        var physical: ModifierSet = []
        var heldKeys: [KeyCode: DeviceID?] = [:]
        var heldButtons: Set<MouseButton> = []
        var logicalKeys: Set<KeyCode> = []
        var logicalButtons: Set<MouseButton> = []
        var violations: [String] = []
        /// The last events and outputs, shown when a run fails.
        var trace: [String] = []
        var firstViolationAt: Int?

        var traceBeforeFirstViolation: String {
            guard let at = firstViolationAt else { return "" }
            return trace[max(0, at - 30)..<min(trace.count, at + 2)].joined(separator: "\n")
        }
        /// Cleared for good once a rule set that adds flags was active:
        /// its held outputs can outlive a rule reload.
        var strictFlags: Bool

        init(seed: UInt64, rules: Int) {
            strictFlags = !EnginePropertyTests.addsFlags.contains(rules)
            rng = SplitMix64(seed: seed)
            engine = InputEngine(rules: EnginePropertyTests.compiled[rules])
        }

        mutating func play(steps: Int) {
            for _ in 0..<steps {
                let roll = rng.next(100)
                switch roll {
                case 0..<45: toggleKey(EnginePropertyTests.keys[rng.next(EnginePropertyTests.keys.count)])
                case 45..<52: repeatHeldKey()
                case 52..<72: toggleButton(EnginePropertyTests.buttons[rng.next(EnginePropertyTests.buttons.count)])
                case 72..<88: now += UInt64(rng.next(300)) * 1_000_000
                case 88..<93:
                    let app = EnginePropertyTests.apps[rng.next(EnginePropertyTests.apps.count)]
                    trace.append("app \(app ?? "none")")
                    engine.setFrontmostApp(app)
                case 93..<96:
                    let index = rng.next(EnginePropertyTests.compiled.count)
                    if EnginePropertyTests.addsFlags.contains(index) { strictFlags = false }
                    trace.append("install \(index)")
                    engine.install(EnginePropertyTests.compiled[index])
                case 96: _ = engine.handleGesture(.tap(fingers: 3))
                default:
                    trace.append("reset")
                    reset()
                }
                if rng.next(2) == 0 { fireTimerIfDue() }
                // The app runs or dismisses an open compass at some point.
                if engine.openCompassID != nil, rng.next(4) == 0 {
                    trace.append("close compass")
                    engine.closeCompass()
                }
            }
        }

        mutating func releaseEverything() {
            for (key, device) in heldKeys { send(.key(key, isDown: false, isRepeat: false), key: key, device: device) }
            for button in heldButtons { send(.mouseButton(button, isDown: false), button: button) }
            heldButtons = []
            engine.closeCompass()
            now += 5_000_000_000
            fireTimerIfDue()
        }

        private mutating func toggleKey(_ key: KeyCode) {
            if let device = heldKeys[key] {
                send(.key(key, isDown: false, isRepeat: false), key: key, device: device)
            } else {
                let devices: [DeviceID?] = [nil, EnginePropertyTests.keyboardA, EnginePropertyTests.keyboardB]
                send(.key(key, isDown: true, isRepeat: false), key: key, device: devices[rng.next(devices.count)])
            }
        }

        private mutating func repeatHeldKey() {
            let candidates = heldKeys.keys.filter { $0.modifierKey == nil }.sorted { $0.rawValue < $1.rawValue }
            guard !candidates.isEmpty else { return }
            let key = candidates[rng.next(candidates.count)]
            send(.key(key, isDown: true, isRepeat: true), key: key, device: heldKeys[key] ?? nil)
        }

        private mutating func toggleButton(_ button: MouseButton) {
            let isDown = !heldButtons.contains(button)
            if isDown { heldButtons.insert(button) } else { heldButtons.remove(button) }
            let touches: [TouchSnapshot?] = [nil, TouchSnapshot(fingers: 1), TouchSnapshot(fingers: 3),
                                             TouchSnapshot(fingers: 1, corner: .topRight), TouchSnapshot(fingers: 0, tappedCorner: .topRight)]
            send(.mouseButton(button, isDown: isDown), button: button, touch: touches[rng.next(touches.count)])
        }

        private mutating func fireTimerIfDue() {
            guard let due = deadline, now >= due else { return }
            let output = engine.handleDeadline(now: now)
            trace.append("t=\((now - 1_000_000_000) / 1_000_000) deadline -> \(Self.describe(output))")
            apply(output, original: nil, physicalAfter: physical)
            deadline = output.nextDeadline
        }

        private mutating func reset() {
            let output = engine.reset()
            trace.append("  -> \(Self.describe(output))")
            apply(output, original: nil, physicalAfter: physical)
            deadline = output.nextDeadline
            let logicalModifiers = Self.modifiers(of: logicalKeys)
            if logicalModifiers != physical {
                noteViolation("after reset logical modifiers \(logicalModifiers.rawValue) != physical \(physical.rawValue)")
            }
        }

        private mutating func send(_ kind: InputEvent.Kind, key: KeyCode? = nil, button: MouseButton? = nil, device: DeviceID? = nil,
                                   touch: TouchSnapshot? = nil) {
            var isDown = false
            var isRepeat = false
            switch kind {
            case let .key(code, down, repeating):
                isDown = down
                isRepeat = repeating
                if !repeating {
                    if down { heldKeys[code] = device } else { heldKeys[code] = nil }
                }
                if let modifier = code.modifierKey {
                    if down { physical.insert(modifier.set) } else { physical.remove(modifier.set) }
                }
            case let .mouseButton(_, down):
                isDown = down
            }
            let output = engine.handle(InputEvent(kind: kind, modifiers: physical, time: now, device: device, touch: touch))
            trace.append("t=\((now - 1_000_000_000) / 1_000_000) \(kind) phys=\(physical.rawValue) -> \(Self.describe(output))")
            apply(output, original: key.map { (.key($0), isDown, isRepeat) } ?? button.map { (.button($0), isDown, false) },
                  physicalAfter: physical)
            deadline = output.nextDeadline
        }

        enum Source { case key(KeyCode), button(MouseButton) }

        private mutating func apply(_ output: EngineOutput, original: (Source, Bool, Bool)?, physicalAfter: ModifierSet) {
            for item in output.items {
                switch item {
                case let .key(key, isDown, isRepeat, flags):
                    record(key, isDown: isDown, isRepeat: isRepeat)
                    checkFlags(flags, context: "emitted \(key) \(isDown ? "down" : "up")")
                case let .original(flags):
                    guard let (source, isDown, isRepeat) = original else {
                        noteViolation("pass-through with no incoming event")
                        continue
                    }
                    switch source {
                    case let .key(key):
                        record(key, isDown: isDown, isRepeat: isRepeat)
                        checkFlags(flags ?? physicalAfter, context: "forwarded \(key) \(isDown ? "down" : "up")")
                    case let .button(button):
                        if isDown {
                            logicalButtons.insert(button)
                        } else if logicalButtons.remove(button) == nil {
                            noteViolation("button \(button) up without down")
                        }
                    }
                }
            }
        }

        private mutating func record(_ key: KeyCode, isDown: Bool, isRepeat: Bool) {
            if isDown {
                if logicalKeys.contains(key) != isRepeat {
                    noteViolation(isRepeat ? "repeat of \(key) while up" : "duplicate down \(key)")
                }
                logicalKeys.insert(key)
            } else if logicalKeys.remove(key) == nil {
                noteViolation("up without down \(key)")
            }
        }

        /// Every event that reaches apps must carry flags that match the
        /// modifier keys apps have seen go down.
        private mutating func checkFlags(_ flags: ModifierSet, context: String) {
            let expected = Self.modifiers(of: logicalKeys)
            let actual = flags.subtracting(.function)
            if strictFlags ? actual != expected : !actual.isSuperset(of: expected) {
                noteViolation("\(context): flags \(actual.rawValue), keys say \(expected.rawValue)")
            }
        }

        mutating func noteViolation(_ text: String) {
            if firstViolationAt == nil { firstViolationAt = trace.count }
            violations.append(text)
        }

        static func describe(_ output: EngineOutput) -> String {
            let items = output.items.map { item -> String in
                switch item {
                case let .original(flags): "orig(\(flags.map { String($0.rawValue) } ?? "-"))"
                case let .key(code, isDown, isRepeat, flags): "\(code.rawValue)\(isRepeat ? "r" : isDown ? "v" : "^")(\(flags.rawValue))"
                }
            }
            return items.joined(separator: " ") + (output.actions.isEmpty ? "" : " actions \(output.actions.count)")
        }

        static func modifiers(of keys: Set<KeyCode>) -> ModifierSet {
            keys.reduce(into: ModifierSet()) { set, key in
                if let modifier = key.modifierKey { set.insert(modifier.set) }
            }
        }
    }
}

/// Small deterministic generator so failures are reproducible by seed.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}
