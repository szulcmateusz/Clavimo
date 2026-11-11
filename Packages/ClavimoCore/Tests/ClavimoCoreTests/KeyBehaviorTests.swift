import Testing
@testable import ClavimoCore

private let h = KeyCode(0x04)
private let j = KeyCode(0x26)
private let k = KeyCode(0x28)
private let l = KeyCode(0x25)
private let d = KeyCode(0x02)
private let o = KeyCode(0x1F)
private let s = KeyCode(0x01)
private let x = KeyCode(0x07)
private let section = KeyCode(0x0A)
private let f13 = KeyCode(0x69)

private func hyperDown() -> [Item] {
    [keyDown(.leftControl, [.leftControl]),
     keyDown(.leftShift, [.leftControl, .leftShift]),
     keyDown(.leftOption, [.leftControl, .leftShift, .leftOption]),
     keyDown(.leftCommand, .hyper)]
}

private func hyperUp() -> [Item] {
    [keyUp(.leftControl, [.leftShift, .leftOption, .leftCommand]),
     keyUp(.leftShift, [.leftOption, .leftCommand]),
     keyUp(.leftOption, [.leftCommand]),
     keyUp(.leftCommand, [])]
}

@Suite("Tap-hold keys")
struct TapHoldTests {
    static let capsHyper: [RuleDefinition] = [
        .tapHold(id: "caps", key: .capsLock, tap: .key(.escape), hold: .modifiers(.hyper)),
    ]

    @Test func capsLockTapSendsEscape() throws {
        var harness = try EngineHarness(Self.capsHyper)
        let pressed = harness.down(.capsLockProxy)
        #expect(pressed.items.isEmpty)
        #expect(pressed.nextDeadline == harness.now + 200_000_000)
        harness.advance(ms: 50)
        #expect(harness.up(.capsLockProxy).items == [keyDown(.escape), keyUp(.escape)])
        #expect(!harness.engine.hasTransientState)
    }

    @Test func capsLockHeldPastDeadlineIsHyper() throws {
        var harness = try EngineHarness(Self.capsHyper)
        harness.down(.capsLockProxy)
        harness.advance(ms: 250)
        #expect(harness.fireDeadline().items == hyperDown())
        #expect(harness.down(j).items == [.original(flags: .hyper)])
        #expect(harness.up(j).items == [.original(flags: .hyper)])
        #expect(harness.up(.capsLockProxy).items == hyperUp())
        #expect(!harness.engine.hasTransientState)
    }

    @Test func otherKeyMakesCapsLockAHoldAtOnce() throws {
        var harness = try EngineHarness(Self.capsHyper)
        harness.down(.capsLockProxy)
        harness.advance(ms: 20)
        #expect(harness.down(j).items == hyperDown() + [.original(flags: .hyper)])
    }

    @Test func clickMakesAPendingKeyAHold() throws {
        var harness = try EngineHarness([
            .tapHold(id: "f", key: .f, tap: .key(.f), hold: .modifiers(.leftCommand), settings: .homeRow),
        ])
        harness.down(.f)
        #expect(harness.press(.primary).items == [keyDown(.leftCommand, [.leftCommand]), .original(flags: [.leftCommand])])
        #expect(harness.release(.primary).items == [.original(flags: [.leftCommand])])
        #expect(harness.up(.f).items == [keyUp(.leftCommand)])
    }

    @Test func doubleTapRunsItsOwnOutput() throws {
        var harness = try EngineHarness([
            .tapHold(id: "caps", key: .capsLock, tap: .key(.escape), hold: .modifiers(.hyper), doubleTap: .action(.toggleCapsLock)),
        ])
        harness.down(.capsLockProxy)
        harness.advance(ms: 30)
        #expect(harness.up(.capsLockProxy).items.isEmpty)
        harness.advance(ms: 50)
        let second = harness.down(.capsLockProxy)
        #expect(second.items.isEmpty)
        #expect(second.actions == [.toggleCapsLock])
        #expect(harness.up(.capsLockProxy).items.isEmpty)

        harness.advance(ms: 1000)
        harness.down(.capsLockProxy)
        harness.advance(ms: 30)
        harness.up(.capsLockProxy)
        harness.advance(ms: 300)
        #expect(harness.fireDeadline().items == [keyDown(.escape), keyUp(.escape)])
    }

    @Test func tapThenHoldRepeatsTheTap() throws {
        var harness = try EngineHarness([.tapHold(id: "j", key: j, tap: .key(j), hold: .modifiers(.rightCommand))])
        harness.down(j)
        #expect(harness.up(j).items == [keyDown(j), keyUp(j)])
        harness.advance(ms: 100)
        #expect(harness.down(j).items == [keyDown(j)])
        #expect(harness.down(j, repeat: true).items == [keyRepeat(j)])
        #expect(harness.up(j).items == [keyUp(j)])
    }

    @Test func capsLockWithoutAnApplicableRuleStillToggles() throws {
        var harness = try EngineHarness([
            .tapHold(id: "caps", key: .capsLock, tap: .key(.escape), hold: .modifiers(.hyper),
                     conditions: RuleConditions(onlyApps: ["com.apple.Safari"])),
        ])
        let pressed = harness.down(.capsLockProxy)
        #expect(pressed.items.isEmpty)
        #expect(pressed.actions == [.toggleCapsLock])
        #expect(harness.down(.capsLockProxy, repeat: true).items.isEmpty)
        #expect(harness.up(.capsLockProxy).items.isEmpty)
    }

    @Test func modifierTappedAloneAddsItsTapOutput() throws {
        var harness = try EngineHarness([
            .tapHold(id: "eisu", key: .leftCommand, tap: .key(.jisEisu), hold: .modifiers(.leftCommand)),
        ])
        #expect(harness.down(.leftCommand).items == [passThrough])
        harness.advance(ms: 60)
        #expect(harness.up(.leftCommand).items == [passThrough, keyDown(.jisEisu), keyUp(.jisEisu)])

        harness.down(.leftCommand)
        harness.down(KeyCode.c)
        harness.up(KeyCode.c)
        #expect(harness.up(.leftCommand).items == [passThrough])

        harness.down(.leftCommand)
        harness.advance(ms: 400)
        #expect(harness.up(.leftCommand).items == [passThrough])
    }

    @Test func resetDropsPendingAndHeldKeys() throws {
        var harness = try EngineHarness([
            .tapHold(id: "f", key: .f, tap: .key(.f), hold: .modifiers(.leftCommand), settings: .homeRow),
        ])
        harness.down(.f)
        harness.advance(ms: 30)
        harness.down(j)
        #expect(harness.engine.reset().items.isEmpty)
        #expect(harness.up(j).items.isEmpty)
        #expect(harness.up(.f).items.isEmpty)
        #expect(!harness.engine.hasTransientState)

        harness.advance(ms: 500)
        harness.down(.f)
        harness.advance(ms: 300)
        harness.fireDeadline()
        #expect(harness.engine.reset().items == [keyUp(.leftCommand)])
        #expect(harness.up(.f).items.isEmpty)
    }
}

@Suite("Home row modifiers")
struct HomeRowTests {
    static let rules: [RuleDefinition] = [
        .tapHold(id: "f", key: .f, tap: .key(.f), hold: .modifiers(.leftCommand), settings: .homeRow),
    ]

    @Test func fastRollStaysTwoLetters() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.f)
        harness.advance(ms: 30)
        #expect(harness.down(j).items.isEmpty)
        harness.advance(ms: 30)
        #expect(harness.up(.f).items == [keyDown(.f), keyUp(.f), keyDown(j)])
        #expect(harness.up(j).items == [passThrough])
    }

    @Test func keyPressedAndReleasedInsideIsAShortcut() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.f)
        harness.advance(ms: 50)
        harness.down(j)
        harness.advance(ms: 50)
        #expect(harness.up(j).items == [keyDown(.leftCommand, [.leftCommand]), keyDown(j, [.leftCommand]),
                                        .original(flags: [.leftCommand])])
        #expect(harness.up(.f).items == [keyUp(.leftCommand)])
    }

    @Test func sameHandKeyMeansTap() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.f)
        harness.advance(ms: 40)
        #expect(harness.down(d).items == [keyDown(.f), passThrough])
        #expect(harness.up(.f).items == [keyUp(.f)])
        #expect(harness.up(d).items == [passThrough])
    }

    @Test func typingStreakIsATapAtOnce() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.a)
        harness.up(.a)
        harness.advance(ms: 50)
        #expect(harness.down(.f).items == [keyDown(.f)])
        #expect(harness.down(.f, repeat: true).items == [keyRepeat(.f)])
        #expect(harness.up(.f).items == [keyUp(.f)])
    }

    @Test func heldPastDeadlineIsCommand() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.f)
        harness.advance(ms: 230)
        #expect(harness.fireDeadline().items == [keyDown(.leftCommand, [.leftCommand])])
        #expect(harness.down(.f, repeat: true).items.isEmpty)
        #expect(harness.down(.c).items == [.original(flags: [.leftCommand])])
    }
}

@Suite("Layers")
struct LayerTests {
    static let rules: [RuleDefinition] = [
        .tapHold(id: "space", key: .space, tap: .key(.space), hold: .layer("nav")),
        .layerKey(id: "h", layer: "nav", key: h, output: .key(.leftArrow)),
        .layerKey(id: "l", layer: "nav", key: l, output: .key(.rightArrow, [.command])),
    ]

    @Test func holdingTheLayerKeyMapsKeys() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.space)
        harness.advance(ms: 20)
        #expect(harness.down(h).items == [keyDown(.leftArrow)])
        #expect(harness.engine.overlay.layers == ["nav"])
        #expect(harness.down(h, repeat: true).items == [keyRepeat(.leftArrow)])
        #expect(harness.up(.space).items.isEmpty)
        #expect(harness.up(h).items == [keyUp(.leftArrow)])
        #expect(harness.down(h).items == [passThrough])
    }

    @Test func layerOutputCarriesItsModifiers() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.space)
        harness.advance(ms: 250)
        harness.fireDeadline()
        #expect(harness.down(l).items == [keyDown(.rightArrow, [.leftCommand])])
        #expect(harness.up(l).items == [keyUp(.rightArrow, [.leftCommand])])
    }

    @Test func tappingTheLayerKeyTypesIt() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(.space)
        #expect(harness.up(.space).items == [keyDown(.space), keyUp(.space)])
    }

    @Test func toggledLayerStaysOn() throws {
        var harness = try EngineHarness([
            .keyOutput(id: "toggle", key: f13, output: .toggleLayer("nav")),
            .layerKey(id: "h", layer: "nav", key: h, output: .key(.leftArrow)),
        ])
        harness.down(f13)
        harness.up(f13)
        #expect(harness.down(h).items == [keyDown(.leftArrow)])
        harness.up(h)
        harness.down(f13)
        harness.up(f13)
        #expect(harness.down(h).items == [passThrough])
        #expect(harness.engine.overlay.layers.isEmpty)
    }
}

@Suite("Combos")
struct ComboTests {
    static let rules: [RuleDefinition] = [.combo(id: "jk", keys: [j, k], output: .key(.escape))]

    @Test func keysTogetherFireTheCombo() throws {
        var harness = try EngineHarness(Self.rules)
        #expect(harness.down(j).items.isEmpty)
        harness.advance(ms: 20)
        #expect(harness.down(k).items == [keyDown(.escape)])
        #expect(harness.down(k, repeat: true).items.isEmpty)
        #expect(harness.up(j).items == [keyUp(.escape)])
        #expect(harness.up(k).items.isEmpty)
        #expect(!harness.engine.hasTransientState)
    }

    @Test func singleKeyIsTypedAfterTheWindow() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(j)
        harness.advance(ms: 60)
        #expect(harness.fireDeadline().items == [keyDown(j)])
        #expect(harness.up(j).items == [passThrough])
    }

    @Test func otherKeyDeliversTheHeldBackKeyFirst() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(j)
        harness.advance(ms: 10)
        #expect(harness.down(l).items == [keyDown(j), passThrough])
    }

    @Test func releaseInsideTheWindowTypesTheKey() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(j)
        harness.advance(ms: 10)
        #expect(harness.up(j).items == [keyDown(j), passThrough])
    }
}

@Suite("Sequences and one-shot modifiers")
struct SequenceTests {
    static let rules: [RuleDefinition] = [
        .keyOutput(id: "leader", key: section, output: .startSequence),
        .sequence(id: "os", keys: [o, s], output: .action(.launchApp("com.apple.Safari"))),
        .sequence(id: "x", keys: [x], output: .key(.escape)),
    ]

    @Test func sequenceRunsItsOutput() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(section)
        harness.up(section)
        #expect(harness.down(o).items.isEmpty)
        #expect(harness.engine.overlay.sequence == [o])
        #expect(harness.engine.overlay.sequenceOptions.map(\.keys) == [[s]])
        harness.up(o)
        let last = harness.down(s)
        #expect(last.items.isEmpty)
        #expect(last.actions == [.launchApp("com.apple.Safari")])
        #expect(harness.up(s).items.isEmpty)
        #expect(harness.engine.overlay.sequence == nil)
    }

    @Test func sequenceCanTypeAKey() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(section)
        harness.up(section)
        #expect(harness.down(x).items == [keyDown(.escape), keyUp(.escape)])
        #expect(harness.up(x).items.isEmpty)
    }

    @Test func unknownKeyOrTimeoutCancels() throws {
        var harness = try EngineHarness(Self.rules)
        harness.down(section)
        harness.up(section)
        #expect(harness.down(.a).items.isEmpty)
        #expect(harness.up(.a).items.isEmpty)
        #expect(harness.down(.a).items == [passThrough])
        harness.up(.a)

        harness.down(section)
        harness.up(section)
        harness.advance(ms: 5000)
        harness.fireDeadline()
        #expect(harness.down(o).items == [passThrough])
    }

    @Test func oneShotModifierAppliesToTheNextKeyOnly() throws {
        var harness = try EngineHarness([.keyOutput(id: "shift", key: f13, output: .oneShot(.leftShift))])
        harness.down(f13)
        harness.up(f13)
        #expect(harness.engine.overlay.oneShot == [.leftShift])
        #expect(harness.down(.a).items == [.original(flags: [.leftShift])])
        #expect(harness.up(.a).items == [.original(flags: [.leftShift])])
        #expect(harness.down(.a).items == [passThrough])
    }

    @Test func oneShotExpires() throws {
        var harness = try EngineHarness([.keyOutput(id: "shift", key: f13, output: .oneShot(.leftShift))])
        harness.down(f13)
        harness.up(f13)
        harness.advance(ms: 3100)
        #expect(harness.down(.a).items == [passThrough])
    }

    @Test func keyOutputSendsAShortcut() throws {
        var harness = try EngineHarness([.keyOutput(id: "copy", key: f13, output: .key(.c, [.command]))])
        #expect(harness.down(f13).items == [keyDown(.c, [.leftCommand])])
        #expect(harness.up(f13).items == [keyUp(.c, [.leftCommand])])
    }
}

@Suite("Keyboard rule validation")
struct KeyBehaviorValidationTests {
    private func errors(_ definitions: [RuleDefinition]) -> [RuleValidationError] {
        if case let .failure(failure) = CompiledRules.compile(definitions) { return failure.errors }
        return []
    }

    @Test func layerNeedsAWayToTurnItOn() {
        #expect(errors([.layerKey(id: "h", layer: "nav", key: h, output: .key(.leftArrow))]) == [.layerNeverActivated("nav")])
    }

    @Test func sequencesNeedALeaderAndMustNotOverlap() {
        #expect(errors([.sequence(id: "o", keys: [o], output: .none)]) == [.sequenceWithoutLeader(id: "o")])
        #expect(errors([
            .keyOutput(id: "leader", key: section, output: .startSequence),
            .sequence(id: "o", keys: [o], output: .none),
            .sequence(id: "os", keys: [o, s], output: .none),
        ]) == [.ambiguousSequence(ids: ["o", "os"])])
    }

    @Test func holdMustBeHeldAndModifiersKeepTheirHold() {
        #expect(errors([.tapHold(id: "a", key: .a, tap: .key(.a), hold: .action(.missionControl))]) == [.holdOutputNotHeld(id: "a")])
        #expect(errors([.tapHold(id: "cmd", key: .leftCommand, tap: .key(.escape), hold: .layer("nav"))])
            == [.modifierTapHoldChangesHold(id: "cmd")])
        #expect(errors([.tapHold(id: "a", key: .a, tap: .key(.a), hold: .modifiers(.leftShift),
                                 settings: TapHoldSettings(holdAfterMilliseconds: 20))]) == [.tapHoldTimingOutOfRange(id: "a")])
    }

    @Test func combosNeedTwoOrThreeOrdinaryKeys() {
        #expect(errors([.combo(id: "c", keys: [j], output: .none)]) == [.invalidCombo(id: "c")])
        #expect(errors([.combo(id: "c", keys: [j, .leftShift], output: .none)]) == [.modifierKeyNotAllowed(.leftShift, id: "c")])
    }

    @Test func keyCannotHaveTwoBehaviors() {
        #expect(errors([
            .remap(from: .a, to: .c),
            .tapHold(id: "a", key: .a, tap: .key(.a), hold: .modifiers(.leftShift)),
        ]) == [.duplicateRemapSource(.a)])
    }

    @Test func inputSourceConditionNeedsThatSource() throws {
        var engine = InputEngine(rules: try CompiledRules.compile([
            .remap(from: .a, to: .c, conditions: RuleConditions(inputSources: ["com.apple.keylayout.Polish"])),
        ]).get())
        let event = InputEvent(kind: .key(.a, isDown: true, isRepeat: false), modifiers: [], time: 1)
        #expect(engine.handle(event).items == [passThrough])
        engine.setInputSource("com.apple.keylayout.Polish")
        #expect(engine.handle(InputEvent(kind: .key(.a, isDown: false, isRepeat: false), modifiers: [], time: 2)).items == [passThrough])
        #expect(engine.handle(event).items == [keyDown(.c)])
    }
}
