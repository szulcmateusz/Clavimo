import ClavimoCore
import Testing
@testable import ClavimoApp

@Suite("User-facing messages")
struct MessagesTests {
    static let validationErrors: [RuleValidationError] = [
        .duplicateRemapSource(.rightCommand), .swapWithItself(.a), .remapToItself(.a),
        .leaderWindowOutOfRange(.f, milliseconds: 900), .leaderIsModifierKey(.leftShift), .leaderAlsoRemapped(.f),
        .conflictingLeaderPolicies(.f), .emptyModifierLeader(id: "r1"), .protectedMouseButton(.primary, id: "r1"),
        .protectedMouseButtonNeedsModifierLeader(.secondary, id: "r1"), .duplicateChord(button: .button4, ids: ["r1", "r2"]),
        .duplicateRuleID("r1"), .deviceConditionOnLetterLeader(id: "r1"), .unsupportedKey(.capsLock),
        .duplicateWheelRule, .wheelRuleWithoutChanges,
    ]

    static let reasons: [UnsupportedReason] = [
        .invalidRule, .invalidCondition("appIs"), .unsupportedCondition("x"), .unsupportedCombination(trigger: "a", action: "b"),
        .bothSidesSwap, .modifierKeyChord, .chordOrder, .invalidMouseButton, .missingLeaderPolicy, .chordBehavior,
        .keyNamespace, .sideSpecificChordModifiers, .unsupportedAction("x"), .trackpadSettings, .pointerSettings,
        .noScrollChange, .perDeviceScrolling, .displayScope, .unsupportedScrollField("x"), .unsupportedScrollMode("x"),
        .scrollValueOutOfRange(mode: "byLines"),
    ]

    @Test(arguments: validationErrors)
    func validationErrorsReadAsSentences(error: RuleValidationError) {
        let text = Messages.describe(error, ruleNames: ["r1": "Fn click", "r2": "Other click"])
        #expect(!text.contains("KeyCode("), "\(text)")
        #expect(!text.contains("MouseButton("), "\(text)")
        #expect(!text.contains("\(error)"), "the enum description must not leak: \(text)")
        #expect(text.last == ".", "\(text)")
    }

    @Test func messagesUseKeyAndRuleNames() {
        #expect(Messages.describe(.duplicateRemapSource(.rightCommand)).contains("Right Command"))
        #expect(Messages.describe(.emptyModifierLeader(id: "r1"), ruleNames: ["r1": "Fn click"]).contains("Fn click"))
    }

    @Test(arguments: reasons)
    func unsupportedReasonsReadAsSentences(reason: UnsupportedReason) {
        let text = Messages.describe(reason)
        #expect(text.first?.isUppercase == true, "\(text)")
        #expect(text.last == "." , "\(text)")
    }
}
