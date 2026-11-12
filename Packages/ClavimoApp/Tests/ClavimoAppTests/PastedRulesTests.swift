import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Pasting rules from an assistant")
struct PastedRulesTests {
    static let base = ConfigDocument(configId: "c", engine: .init(enabledOnLaunch: true), activeProfileId: "default",
                                     profiles: [.init(id: "default", name: "Default")])

    @Test func answerWithACodeBlockAndExplanation() throws {
        let answer = """
        Sure! Here are the rules:

        ```json
        [
          {
            "name": "Caps Lock: Escape / Hyper",
            "trigger": {"kind": "tapHold", "key": {"codeNamespace": "macVirtualKeyCode", "code": 57}, "thresholdMs": 200},
            "action": {"kind": "tapHold", "tap": {"kind": "sendKey", "key": {"codeNamespace": "macVirtualKeyCode", "code": 53}},
                       "hold": {"kind": "holdModifiers", "modifiers": ["control", "option", "shift", "command"]}}
          },
          {
            "trigger": {"kind": "trackpadGesture", "gesture": "rotate", "direction": "clockwise", "zone": "topRight"},
            "action": {"kind": "mediaKey", "key": "volumeUp"}
          }
        ]
        ```

        The first rule {makes} Caps Lock useful; the second turns the volume up.
        """
        let document = try PastedRules.apply(answer, to: Self.base).get()
        #expect(document.rules.count == 2)
        #expect(document.rules[0].name == "Caps Lock: Escape / Hyper")
        #expect(document.rules.allSatisfy { $0.profileId == "default" && $0.enabled && !$0.id.isEmpty })
        let interpreted = try document.interpret()
        #expect(interpreted.unsupported.isEmpty)
        if case let .failure(failure) = CompiledRules.compile(interpreted.definitions) { Issue.record("\(failure.errors)") }
    }

    @Test func singleRuleAndRulesObjectAreAccepted() throws {
        let single = #"{"trigger": {"kind": "key", "key": {"codeNamespace": "macVirtualKeyCode", "code": 105}}, "action": {"kind": "missionControl"}}"#
        #expect(try PastedRules.apply(single, to: Self.base).get().rules.count == 1)
        let wrapped = #"{"rules": [\#(single), \#(single)]}"#
        #expect(try PastedRules.apply(wrapped, to: Self.base).get().rules.count == 2)
    }

    @Test func sameIDReplacesTheRule() throws {
        var current = Self.base
        let rule = #"{"id": "r1", "name": "A", "trigger": {"kind": "key", "key": {"codeNamespace": "macVirtualKeyCode", "code": 105}}, "action": {"kind": "missionControl"}}"#
        current = try PastedRules.apply(rule, to: current).get()
        let changed = rule.replacingOccurrences(of: #""name": "A""#, with: #""name": "B""#)
        let after = try PastedRules.apply(changed, to: current).get()
        #expect(after.rules.map(\.name) == ["B"])
    }

    @Test func wholeConfigurationReplacesEverything() throws {
        let data = try Self.base.encoded()
        let text = "Here you go:\n```\n" + String(decoding: data, as: UTF8.self) + "\n```"
        #expect(try PastedRules.apply(text, to: Self.base).get() == Self.base)
    }

    @Test func clearMessagesForNonsense() {
        #expect((try? PastedRules.apply("Sorry, I cannot help with that.", to: Self.base).get()) == nil)
        #expect((try? PastedRules.apply("[1, 2]", to: Self.base).get()) == nil)
        #expect((try? PastedRules.apply("{\"a\": ", to: Self.base).get()) == nil)
    }
}
