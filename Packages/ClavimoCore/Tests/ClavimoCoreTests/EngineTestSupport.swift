@testable import ClavimoCore

/// Drives an engine with physically plausible events. It tracks the
/// physical modifier state the way the platform would report it, so tests
/// describe key presses rather than raw flag values.
struct EngineHarness {
    var engine: InputEngine
    var physical: ModifierSet = []
    var now: UInt64 = 1_000_000_000

    init(_ definitions: [RuleDefinition]) throws {
        engine = InputEngine(rules: try CompiledRules.compile(definitions).get())
    }

    mutating func advance(ms: UInt64) {
        now += ms * 1_000_000
    }

    @discardableResult
    mutating func down(_ key: KeyCode, repeat isRepeat: Bool = false) -> EngineOutput {
        if let modifier = key.modifierKey { physical.insert(modifier.set) }
        return engine.handle(InputEvent(kind: .key(key, isDown: true, isRepeat: isRepeat), modifiers: physical, time: now))
    }

    @discardableResult
    mutating func up(_ key: KeyCode) -> EngineOutput {
        if let modifier = key.modifierKey { physical.remove(modifier.set) }
        return engine.handle(InputEvent(kind: .key(key, isDown: false, isRepeat: false), modifiers: physical, time: now))
    }

    @discardableResult
    mutating func press(_ button: MouseButton) -> EngineOutput {
        engine.handle(InputEvent(kind: .mouseButton(button, isDown: true), modifiers: physical, time: now))
    }

    @discardableResult
    mutating func release(_ button: MouseButton) -> EngineOutput {
        engine.handle(InputEvent(kind: .mouseButton(button, isDown: false), modifiers: physical, time: now))
    }

    @discardableResult
    mutating func fireDeadline() -> EngineOutput {
        engine.handleDeadline(now: now)
    }
}

typealias Item = EngineOutput.Item

func keyDown(_ key: KeyCode, _ flags: ModifierSet = []) -> Item {
    .key(key, isDown: true, isRepeat: false, flags: flags)
}

func keyUp(_ key: KeyCode, _ flags: ModifierSet = []) -> Item {
    .key(key, isDown: false, isRepeat: false, flags: flags)
}

func keyRepeat(_ key: KeyCode, _ flags: ModifierSet = []) -> Item {
    .key(key, isDown: true, isRepeat: true, flags: flags)
}

let passThrough: Item = .original(flags: nil)

/// Replays an emitted stream and returns which keys are still logically
/// down, failing on an up without a matching down.
struct LogicalKeyboard {
    private(set) var down: Set<KeyCode> = []
    private(set) var violations: [String] = []

    mutating func apply(_ output: EngineOutput, original: KeyCode? = nil, originalIsDown: Bool = false) {
        for item in output.items {
            switch item {
            case let .key(key, isDown, isRepeat, _):
                record(key, isDown: isDown, isRepeat: isRepeat)
            case .original:
                if let original { record(original, isDown: originalIsDown, isRepeat: false) }
            }
        }
    }

    private mutating func record(_ key: KeyCode, isDown: Bool, isRepeat: Bool) {
        if isDown {
            if down.contains(key), !isRepeat { violations.append("duplicate down \(key)") }
            down.insert(key)
        } else if down.remove(key) == nil {
            violations.append("up without down \(key)")
        }
    }
}
