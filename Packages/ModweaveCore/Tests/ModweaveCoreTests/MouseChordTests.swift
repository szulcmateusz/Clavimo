import Testing
@testable import ModweaveCore

@Suite("Modifier + mouse chords")
struct ModifierMouseChordTests {
    func shiftMouse5() throws -> EngineHarness {
        try EngineHarness([
            .mouseChord(id: "prev", leader: .modifiers(.shift), button: .button5, action: .previousWorkspace, priority: 100),
        ])
    }

    @Test func firesOnceOnDownAndConsumesBothButtonEvents() throws {
        var h = try shiftMouse5()
        h.down(.leftShift)
        let pressed = h.press(.button5)
        #expect(pressed.items == [])
        #expect(pressed.actions == [.previousWorkspace])
        let released = h.release(.button5)
        #expect(released.items == [])
        #expect(released.actions == [])
    }

    @Test func shiftReleasedBeforeMouseStillConsumesMouseUp() throws {
        var h = try shiftMouse5()
        h.down(.leftShift)
        h.press(.button5)
        #expect(h.up(.leftShift).items == [passThrough])
        #expect(h.release(.button5).items == [])
        #expect(!h.engine.hasTransientState)
    }

    @Test func buttonWithoutShiftPassesThrough() throws {
        var h = try shiftMouse5()
        #expect(h.press(.button5).items == [passThrough])
        #expect(h.release(.button5).items == [passThrough])
    }

    @Test func extraModifiersDoNotMatchExactRequirement() throws {
        var h = try shiftMouse5()
        h.down(.leftShift)
        h.down(.leftCommand)
        #expect(h.press(.button5).actions == [])
    }

    @Test func eitherSideSatisfiesGenericRequirement() throws {
        var h = try shiftMouse5()
        h.down(.rightShift)
        #expect(h.press(.button5).actions == [.previousWorkspace])
    }

    @Test func mouseUpAfterRuleRemovalIsStillConsumed() throws {
        var h = try shiftMouse5()
        h.down(.leftShift)
        h.press(.button5)
        h.engine.install(.empty)
        #expect(h.release(.button5).items == [])
    }

    @Test func fnChordOnPrimaryButtonConsumesOnlyWithFnHeld() throws {
        var h = try EngineHarness([
            .mouseChord(id: "fn-left", leader: .modifiers(.function), button: .primary, action: .previousWorkspace, priority: 1, allowProtectedButton: true),
        ])
        #expect(h.press(.primary).items == [passThrough], "plain clicks must never be eaten")
        #expect(h.release(.primary).items == [passThrough])
        h.physical.insert(.function)
        let click = h.press(.primary)
        #expect(click.items == [])
        #expect(click.actions == [.previousWorkspace])
        h.physical.remove(.function)
        #expect(h.release(.primary).items == [], "the up of a consumed click is consumed even after Fn is released")
        #expect(h.press(.primary).items == [passThrough])
    }

    @Test func fnStateDoesNotDisturbModifierSwap() throws {
        var h = try EngineHarness([.swap(.rightCommand, .rightOption)])
        h.physical.insert(.function)
        #expect(h.down(.rightCommand).items == [keyDown(.rightOption, [.rightOption])], "Fn is preserved by the adapter, not emitted")
        h.physical.remove(.function)
        #expect(h.up(.rightCommand).items == [keyUp(.rightOption, [])])
    }

    @Test func controlCommandChordMatchesExactly() throws {
        var h = try EngineHarness([
            .mouseChord(id: "cc-right", leader: .modifiers([.control, .command]), button: .secondary, action: .nextWorkspace, priority: 1, allowProtectedButton: true),
        ])
        h.down(.leftControl)
        #expect(h.press(.secondary).items == [passThrough], "Control alone is a normal secondary click")
        h.release(.secondary)
        h.down(.leftCommand)
        #expect(h.press(.secondary).actions == [.nextWorkspace])
    }

    @Test func higherPriorityChordWinsDeterministically() throws {
        var h = try EngineHarness([
            .mouseChord(id: "low", leader: .modifiers(.shift), button: .button4, action: .previousWorkspace, priority: 10),
            .mouseChord(id: "high", leader: .key(.f, .boundedWindow(milliseconds: 120)), button: .button4, action: .nextWorkspace, priority: 90),
        ])
        h.down(.leftShift)
        h.down(.f)
        #expect(h.press(.button4).actions == [.nextWorkspace])
    }
}

@Suite("Letter key + mouse chords")
struct LetterMouseChordTests {
    func fMouse4(_ policy: LeaderPolicy) throws -> EngineHarness {
        try EngineHarness([
            .mouseChord(id: "next", leader: .key(.f, policy), button: .button4, action: .nextWorkspace, priority: 90),
        ])
    }

    // MARK: Policy B - bounded window

    @Test func boundedChordInsideWindowSuppressesF() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        let fDown = h.down(.f)
        #expect(fDown.items == [])
        #expect(fDown.nextDeadline == h.now + 120_000_000)
        h.advance(ms: 50)
        let click = h.press(.button4)
        #expect(click.items == [])
        #expect(click.actions == [.nextWorkspace])
        #expect(click.nextDeadline == nil, "a chorded leader no longer needs a timer")
        #expect(h.release(.button4).items == [])
        #expect(h.up(.f).items == [])
        #expect(!h.engine.hasTransientState)
    }

    @Test func boundedTapDeliversFOnRelease() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.advance(ms: 40)
        #expect(h.up(.f).items == [keyDown(.f), keyUp(.f)])
    }

    @Test func boundedTimeoutDeliversFAndAllowsRepeat() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.advance(ms: 120)
        #expect(h.fireDeadline().items == [keyDown(.f)])
        h.advance(ms: 400)
        #expect(h.down(.f, repeat: true).items == [passThrough])
        #expect(h.up(.f).items == [passThrough])
    }

    @Test func boundedChordAfterWindowDoesNotFireEvenIfTimerIsLate() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.advance(ms: 200) // the timer has not fired yet
        let click = h.press(.button4)
        #expect(click.items == [keyDown(.f), passThrough])
        #expect(click.actions == [])
        #expect(h.release(.button4).items == [passThrough])
        #expect(h.up(.f).items == [passThrough])
    }

    @Test(arguments: [0, 30, 100, 119])
    func boundedChordFiresAtDelaysInsideWindow(delay: Int) throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.advance(ms: UInt64(delay))
        #expect(h.press(.button4).actions == [.nextWorkspace])
    }

    @Test func otherKeyInterruptsBufferedLeaderInOrder() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.advance(ms: 20)
        #expect(h.down(.a).items == [keyDown(.f), passThrough])
        #expect(h.up(.f).items == [passThrough])
        #expect(h.up(.a).items == [passThrough])
    }

    @Test func modifierChangeFlushesLeaderWithItsOriginalFlags() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.leftShift)
        h.down(.f)
        #expect(h.up(.leftShift).items == [keyDown(.f, [.leftShift]), passThrough])
    }

    @Test func repeatsWhileBufferedAreSwallowed() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 500))
        h.down(.f)
        h.advance(ms: 400)
        #expect(h.down(.f, repeat: true).items == [])
    }

    @Test func otherMouseButtonsPassWhileFIsHeld() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        #expect(h.press(.button5).items == [passThrough])
        #expect(h.release(.button5).items == [passThrough])
        #expect(h.press(.button4).actions == [.nextWorkspace])
    }

    @Test func mouseReleasedBeforeF() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.press(.button4)
        h.release(.button4)
        #expect(h.up(.f).items == [])
    }

    @Test func fReleasedBeforeMouse() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.press(.button4)
        #expect(h.up(.f).items == [])
        #expect(h.release(.button4).items == [])
    }

    @Test func repeatedClicksWhileHoldingFFireEachTime() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        h.down(.f)
        h.press(.button4)
        h.release(.button4)
        h.advance(ms: 500)
        #expect(h.press(.button4).actions == [.nextWorkspace])
    }

    @Test func typingFRepeatedlyDeliversEveryF() throws {
        var h = try fMouse4(.boundedWindow(milliseconds: 120))
        var keyboard = LogicalKeyboard()
        var taps = 0
        for _ in 0..<100 {
            let down = h.down(.f)
            keyboard.apply(down)
            h.advance(ms: 60)
            let up = h.up(.f)
            keyboard.apply(up)
            taps += up.items.filter { $0 == keyDown(.f) }.count
            h.advance(ms: 60)
        }
        #expect(taps == 100)
        #expect(keyboard.violations.isEmpty)
        #expect(keyboard.down.isEmpty)
    }

    // MARK: Policy A - deferred until release

    @Test func deferredLeaderHasNoDeadlineAndChordsLate() throws {
        var h = try fMouse4(.deferredUntilUp)
        #expect(h.down(.f).nextDeadline == nil)
        h.advance(ms: 2000)
        #expect(h.press(.button4).actions == [.nextWorkspace])
        #expect(h.up(.f).items == [])
    }

    @Test func deferredLongHoldWithoutChordTypesOneF() throws {
        var h = try fMouse4(.deferredUntilUp)
        h.down(.f)
        h.advance(ms: 2000)
        #expect(h.down(.f, repeat: true).items == [])
        #expect(h.up(.f).items == [keyDown(.f), keyUp(.f)])
    }

    // MARK: Policy C - non-consuming

    @Test func nonConsumingDeliversFImmediatelyAndStillChords() throws {
        var h = try fMouse4(.nonConsuming)
        #expect(h.down(.f).items == [passThrough])
        #expect(h.press(.button4).actions == [.nextWorkspace])
        #expect(h.up(.f).items == [passThrough])
        #expect(h.release(.button4).items == [])
    }

    @Test func nonConsumingDoesNotChordAfterRelease() throws {
        var h = try fMouse4(.nonConsuming)
        h.down(.f)
        h.up(.f)
        #expect(h.press(.button4).actions == [])
    }
}
