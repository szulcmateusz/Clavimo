import Testing
@testable import ModweaveCore

@Suite("Reset and recovery")
struct ResetTests {
    @Test func resetReleasesRemappedOutputAndSwallowsLaterPhysicalUp() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g)])
        h.down(.a)
        #expect(h.engine.reset().items == [keyUp(.g)])
        #expect(h.down(.a, repeat: true).items == [])
        #expect(h.up(.a).items == [])
        #expect(!h.engine.hasTransientState)
    }

    @Test func resetRestoresPhysicalModifierStateAfterSwap() throws {
        var h = try EngineHarness([.swap(.leftCommand, .leftOption)])
        h.down(.leftCommand)
        #expect(h.engine.reset().items == [keyUp(.leftOption, []), keyDown(.leftCommand, [.leftCommand])])
        h.engine.install(.empty)
        #expect(h.up(.leftCommand).items == [passThrough])
    }

    @Test func resetDropsBufferedLeaderWithoutTypingIt() throws {
        var h = try EngineHarness([
            .mouseChord(id: "next", leader: .key(.f, .boundedWindow(milliseconds: 120)), button: .button4, action: .nextWorkspace, priority: 1),
        ])
        h.down(.f)
        let reset = h.engine.reset()
        #expect(reset.items == [])
        #expect(reset.nextDeadline == nil)
        #expect(h.up(.f).items == [], "the F up has no delivered F down to match")
    }

    @Test func resetKeepsMouseUpConsumed() throws {
        var h = try EngineHarness([
            .mouseChord(id: "prev", leader: .modifiers(.shift), button: .button5, action: .previousWorkspace, priority: 1),
        ])
        h.down(.leftShift)
        h.press(.button5)
        _ = h.engine.reset()
        #expect(h.release(.button5).items == [])
    }

    @Test func resetOnIdleEngineEmitsNothing() throws {
        var h = try EngineHarness([.swap(.leftCommand, .leftOption)])
        #expect(h.engine.reset() == EngineOutput())
    }
}

@Suite("Rule compiler validation")
struct CompilerTests {
    func errors(_ definitions: [RuleDefinition]) -> [RuleValidationError] {
        switch CompiledRules.compile(definitions) {
        case .success: []
        case let .failure(failure): failure.errors
        }
    }

    @Test func swapCompilesToTwoRemaps() throws {
        let rules = try CompiledRules.compile([.swap(.leftCommand, .leftOption)]).get()
        #expect(rules.keyRemaps == [.leftCommand: .leftOption, .leftOption: .leftCommand])
    }

    @Test func rejectsDuplicateRemapSource() {
        #expect(errors([.remap(from: .a, to: .g), .remap(from: .a, to: .c)]) == [.duplicateRemapSource(.a)])
    }

    @Test func rejectsSwapOverlappingRemap() {
        #expect(errors([.swap(.leftCommand, .leftOption), .remap(from: .leftOption, to: .a)]) == [.duplicateRemapSource(.leftOption)])
    }

    @Test func rejectsSelfMappings() {
        #expect(errors([.remap(from: .a, to: .a)]) == [.remapToItself(.a)])
        #expect(errors([.swap(.a, .a)]) == [.swapWithItself(.a)])
    }

    @Test func rejectsProtectedMouseButtons() {
        let result = errors([
            .mouseChord(id: "x", leader: .modifiers(.shift), button: .primary, action: .nextWorkspace, priority: 1),
        ])
        #expect(result == [.protectedMouseButton(.primary, id: "x")])
    }

    @Test(arguments: [0, 29, 1001])
    func rejectsLeaderWindowOutsideRange(milliseconds: Int) {
        let result = errors([
            .mouseChord(id: "x", leader: .key(.f, .boundedWindow(milliseconds: milliseconds)), button: .button4, action: .nextWorkspace, priority: 1),
        ])
        #expect(result == [.leaderWindowOutOfRange(.f, milliseconds: milliseconds)])
    }

    @Test func rejectsModifierAsLetterLeader() {
        let result = errors([
            .mouseChord(id: "x", leader: .key(.leftShift, .deferredUntilUp), button: .button4, action: .nextWorkspace, priority: 1),
        ])
        #expect(result == [.leaderIsModifierKey(.leftShift)])
    }

    @Test func rejectsLeaderThatIsAlsoRemapped() {
        let result = errors([
            .remap(from: .f, to: .g),
            .mouseChord(id: "x", leader: .key(.f, .deferredUntilUp), button: .button4, action: .nextWorkspace, priority: 1),
        ])
        #expect(result == [.leaderAlsoRemapped(.f)])
    }

    @Test func rejectsConflictingLeaderPolicies() {
        let result = errors([
            .mouseChord(id: "x", leader: .key(.f, .deferredUntilUp), button: .button4, action: .nextWorkspace, priority: 1),
            .mouseChord(id: "y", leader: .key(.f, .nonConsuming), button: .button5, action: .previousWorkspace, priority: 1),
        ])
        #expect(result == [.conflictingLeaderPolicies(.f)])
    }

    @Test func rejectsDuplicateChordAndDuplicateID() {
        let result = errors([
            .mouseChord(id: "x", leader: .modifiers(.shift), button: .button4, action: .nextWorkspace, priority: 1),
            .mouseChord(id: "x", leader: .modifiers(.shift), button: .button4, action: .previousWorkspace, priority: 1),
        ])
        #expect(result.contains(.duplicateRuleID("x")))
        #expect(result.contains(.duplicateChord(button: .button4, ids: ["x", "x"])))
    }

    @Test func rejectsEmptyModifierLeader() {
        let result = errors([
            .mouseChord(id: "x", leader: .modifiers([]), button: .button4, action: .nextWorkspace, priority: 1),
        ])
        #expect(result == [.emptyModifierLeader(id: "x")])
    }

    @Test func mouseButtonUserFacingNumbersMatchRawIndices() {
        #expect(MouseButton(userFacingNumber: 4) == .button4)
        #expect(MouseButton.button4.rawValue == 3)
        #expect(MouseButton(userFacingNumber: 0) == nil)
    }
}
