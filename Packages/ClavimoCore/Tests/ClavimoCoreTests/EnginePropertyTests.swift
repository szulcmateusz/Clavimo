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
    ]
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
    ]

    static let compiled: [CompiledRules] = ruleSets.map { try! CompiledRules.compile($0).get() }

    @Test(arguments: 0..<4)
    func randomSequencesStayBalanced(ruleSet: Int) {
        for seed in 0..<150 {
            var run = Run(seed: UInt64(ruleSet * 1000 + seed), rules: ruleSet)
            run.play(steps: 400)
            run.releaseEverything()
            #expect(run.violations.isEmpty, "seed \(seed): \(run.violations.prefix(3))")
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

        init(seed: UInt64, rules: Int) {
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
                case 88..<93: engine.setFrontmostApp(EnginePropertyTests.apps[rng.next(EnginePropertyTests.apps.count)])
                case 93..<97: engine.install(EnginePropertyTests.compiled[rng.next(EnginePropertyTests.compiled.count)])
                default: reset()
                }
                if rng.next(2) == 0 { fireTimerIfDue() }
            }
        }

        mutating func releaseEverything() {
            for (key, device) in heldKeys { send(.key(key, isDown: false, isRepeat: false), key: key, device: device) }
            for button in heldButtons { send(.mouseButton(button, isDown: false), button: button) }
            heldButtons = []
            now += 2_000_000_000
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
            send(.mouseButton(button, isDown: isDown), button: button)
        }

        private mutating func fireTimerIfDue() {
            guard let due = deadline, now >= due else { return }
            let output = engine.handleDeadline(now: now)
            apply(output, original: nil, physicalAfter: physical)
            deadline = output.nextDeadline
        }

        private mutating func reset() {
            let output = engine.reset()
            apply(output, original: nil, physicalAfter: physical)
            deadline = output.nextDeadline
            let logicalModifiers = Self.modifiers(of: logicalKeys)
            if logicalModifiers != physical {
                violations.append("after reset logical modifiers \(logicalModifiers.rawValue) != physical \(physical.rawValue)")
            }
        }

        private mutating func send(_ kind: InputEvent.Kind, key: KeyCode? = nil, button: MouseButton? = nil, device: DeviceID? = nil) {
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
            let output = engine.handle(InputEvent(kind: kind, modifiers: physical, time: now, device: device))
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
                        violations.append("pass-through with no incoming event")
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
                            violations.append("button \(button) up without down")
                        }
                    }
                }
            }
        }

        private mutating func record(_ key: KeyCode, isDown: Bool, isRepeat: Bool) {
            if isDown {
                if logicalKeys.contains(key) != isRepeat {
                    violations.append(isRepeat ? "repeat of \(key) while up" : "duplicate down \(key)")
                }
                logicalKeys.insert(key)
            } else if logicalKeys.remove(key) == nil {
                violations.append("up without down \(key)")
            }
        }

        /// Every event that reaches apps must carry flags that match the
        /// modifier keys apps have seen go down.
        private mutating func checkFlags(_ flags: ModifierSet, context: String) {
            let expected = Self.modifiers(of: logicalKeys)
            let actual = flags.subtracting(.function)
            if actual != expected {
                violations.append("\(context): flags \(actual.rawValue), keys say \(expected.rawValue)")
            }
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
