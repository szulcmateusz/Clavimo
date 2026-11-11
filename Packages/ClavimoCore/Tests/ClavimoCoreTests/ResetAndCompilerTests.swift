import Testing
@testable import ClavimoCore

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

    @Test func rejectsCapsLockAndFnRemaps() {
        #expect(errors([.remap(from: .capsLock, to: .escape)]) == [.unsupportedKey(.capsLock)])
        #expect(errors([.remap(from: .a, to: .function)]) == [.unsupportedKey(.function)])
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

    @Test func protectedButtonNeedsExplicitOptInAndModifierLeader() {
        #expect(errors([
            .mouseChord(id: "x", leader: .modifiers(.function), button: .primary, action: .previousWorkspace, priority: 1, allowProtectedButton: true),
        ]) == [])
        #expect(errors([
            .mouseChord(id: "x", leader: .key(.f, .deferredUntilUp), button: .secondary, action: .nextWorkspace, priority: 1, allowProtectedButton: true),
        ]) == [.protectedMouseButtonNeedsModifierLeader(.secondary, id: "x")])
    }

    @Test(arguments: [0, 49, 501])
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

@Suite("Rule conditions")
struct ConditionTests {
    static let builtIn = DeviceID(vendorID: 1452, productID: 835)
    static let logitech = DeviceID(vendorID: 1133, productID: 45934)

    @Test func deviceScopedSwapAppliesOnlyToThatDevice() throws {
        let rules = try CompiledRules.compile([
            .swap(.rightCommand, .rightOption, conditions: RuleConditions(devices: [Self.builtIn])),
        ]).get()
        var engine = InputEngine(rules: rules)
        let fromBuiltIn = engine.handle(InputEvent(kind: .key(.rightCommand, isDown: true, isRepeat: false), modifiers: [.rightCommand], time: 1, device: Self.builtIn))
        #expect(fromBuiltIn.items == [keyDown(.rightOption, [.rightOption])])
        _ = engine.handle(InputEvent(kind: .key(.rightCommand, isDown: false, isRepeat: false), modifiers: [], time: 2, device: Self.builtIn))

        let fromOther = engine.handle(InputEvent(kind: .key(.rightCommand, isDown: true, isRepeat: false), modifiers: [.rightCommand], time: 3, device: Self.logitech))
        #expect(fromOther.items == [passThrough])
        let unknown = engine.handle(InputEvent(kind: .key(.rightCommand, isDown: false, isRepeat: false), modifiers: [], time: 4, device: nil))
        #expect(unknown.items == [passThrough], "unknown attribution never matches a device rule")
    }

    @Test func perDeviceRulesForSameKeyCoexistAndSpecificWins() throws {
        let rules = try CompiledRules.compile([
            .remap(from: .a, to: .g),
            .remap(from: .a, to: .c, conditions: RuleConditions(devices: [Self.logitech])),
        ]).get()
        #expect(rules.remapTarget(for: .a, app: nil, device: Self.logitech) == .c)
        #expect(rules.remapTarget(for: .a, app: nil, device: Self.builtIn) == .g)
        #expect(rules.remapTarget(for: .a, app: nil, device: nil) == .g)
        #expect(rules.keysNeedingDevice == [.a])
        #expect(rules.usesDeviceConditions)
    }

    @Test func duplicateConditionsAreStillRejected() {
        let conditions = RuleConditions(devices: [Self.builtIn])
        let result = CompiledRules.compile([
            .remap(from: .a, to: .g, conditions: conditions),
            .remap(from: .a, to: .c, conditions: conditions),
        ])
        #expect(throws: CompileFailure.self) { try result.get() }
    }

    @Test func appConditionsUseFrontmostApp() throws {
        var h = try EngineHarness([
            .mouseChord(id: "x", leader: .modifiers(.shift), button: .button5, action: .previousWorkspace, priority: 1,
                        conditions: RuleConditions(exceptApps: ["com.example.game"])),
        ])
        h.down(.leftShift)
        h.engine.setFrontmostApp("com.example.game")
        #expect(h.press(.button5).items == [passThrough])
        h.release(.button5)
        h.engine.setFrontmostApp("com.apple.Safari")
        #expect(h.press(.button5).actions == [.previousWorkspace])
    }

    @Test func letterLeaderIsNotBufferedWhereItsChordCannotApply() throws {
        var h = try EngineHarness([
            .mouseChord(id: "x", leader: .key(.f, .boundedWindow(milliseconds: 120)), button: .button4, action: .nextWorkspace, priority: 1,
                        conditions: RuleConditions(onlyApps: ["com.apple.finder"])),
        ])
        h.engine.setFrontmostApp("com.apple.TextEdit")
        #expect(h.down(.f).items == [passThrough], "no typing delay outside the chord's apps")
        h.up(.f)
        h.engine.setFrontmostApp("com.apple.finder")
        #expect(h.down(.f).items == [])
    }

    @Test func deviceConditionOnLetterLeaderIsRejected() {
        let result = CompiledRules.compile([
            .mouseChord(id: "x", leader: .key(.f, .deferredUntilUp), button: .button4, action: .nextWorkspace, priority: 1,
                        conditions: RuleConditions(devices: [Self.logitech])),
        ])
        #expect(throws: CompileFailure.self) { try result.get() }
    }

    @Test func wheelSettingsSkipContinuousScrolling() throws {
        let engine = InputEngine(rules: try CompiledRules.compile([
            .wheel(vertical: ScrollAxisSettings(reverse: true), horizontal: .unchanged),
        ]).get())
        #expect(engine.wheelSettings(isContinuous: false, device: nil)?.vertical.reverse == true)
        #expect(engine.wheelSettings(isContinuous: true, device: nil) == nil, "trackpads are never changed")
    }

    @Test func wheelRuleWithoutChangesIsRejected() {
        let result = CompiledRules.compile([.wheel(vertical: .unchanged, horizontal: .unchanged)])
        #expect(throws: CompileFailure.self) { try result.get() }
    }

    @Test func deviceIDParsing() {
        #expect(DeviceID(string: "1133:49298") == DeviceID(vendorID: 1133, productID: 49298))
        #expect(DeviceID(string: "0x46d:1") == nil)
        #expect(DeviceID(string: "1133") == nil)
    }
}
