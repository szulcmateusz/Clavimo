import Foundation
import Testing
@testable import ClavimoCore

@Suite("Keyboard rules in the configuration")
struct KeyboardConfigTests {
    func definitions(trigger: String, action: String, conditions: String = "[]") throws -> InterpretedConfig {
        let json = ConfigTests.document(rules: ConfigTests.rule(trigger: trigger, action: action, conditions: conditions))
        return try ConfigDocument.decode(Data(json.utf8)).interpret()
    }

    static func key(_ code: Int) -> String { #"{"codeNamespace": "macVirtualKeyCode", "code": \#(code)}"# }

    @Test func keyboardRulesAreRead() throws {
        let caps = Self.key(57)
        let j = Self.key(38)
        let k = Self.key(40)
        let cases: [(String, String, RuleDefinition)] = [
            (#"{"kind": "tapHold", "key": \#(caps), "thresholdMs": 180}"#,
             #"{"kind": "tapHold", "tap": {"kind": "sendKey", "key": \#(Self.key(53))}, "hold": {"kind": "holdModifiers", "modifiers": ["control", "option", "shift", "command"]}, "doubleTap": {"kind": "toggleCapsLock"}}"#,
             .tapHold(id: "r1", key: .capsLock, tap: .key(.escape), hold: .modifiers(.hyper), doubleTap: .action(.toggleCapsLock),
                      settings: TapHoldSettings(holdAfterMilliseconds: 180))),
            (#"{"kind": "tapHold", "key": \#(Self.key(3)), "thresholdMs": 220, "interruptPolicy": "permissiveHold", "oppositeHandsOnly": true, "typingStreakMs": 150}"#,
             #"{"kind": "tapHold", "tap": {"kind": "sendKey", "key": \#(Self.key(3))}, "hold": {"kind": "holdModifiers", "modifiers": ["leftCommand"]}}"#,
             .tapHold(id: "r1", key: .f, tap: .key(.f), hold: .modifiers(.leftCommand), settings: .homeRow)),
            (#"{"kind": "key", "key": \#(Self.key(49))}"#, #"{"kind": "holdLayer", "layerId": "nav"}"#,
             .keyOutput(id: "r1", key: .space, output: .layer("nav"))),
            (#"{"kind": "layerKey", "layerId": "nav", "key": \#(Self.key(4))}"#,
             #"{"kind": "sendShortcut", "key": \#(Self.key(123)), "modifiers": ["command"]}"#,
             .layerKey(id: "r1", layer: "nav", key: KeyCode(4), output: .key(.leftArrow, [.command]))),
            (#"{"kind": "keyCombo", "keys": [\#(j), \#(k)], "windowMs": 40}"#, #"{"kind": "sendKey", "key": \#(Self.key(53))}"#,
             .combo(id: "r1", keys: [KeyCode(38), KeyCode(40)], output: .key(.escape), windowMilliseconds: 40)),
            (#"{"kind": "keySequence", "keys": [\#(j), \#(k)]}"#, #"{"kind": "launchApp", "bundleId": "com.apple.Safari"}"#,
             .sequence(id: "r1", keys: [KeyCode(38), KeyCode(40)], output: .action(.launchApp("com.apple.Safari")))),
            (#"{"kind": "key", "key": \#(Self.key(10))}"#, #"{"kind": "startSequence"}"#,
             .keyOutput(id: "r1", key: KeyCode(10), output: .startSequence)),
            (#"{"kind": "key", "key": \#(Self.key(105))}"#, #"{"kind": "oneShotModifiers", "modifiers": ["rightShift"]}"#,
             .keyOutput(id: "r1", key: KeyCode(105), output: .oneShot(.rightShift))),
            (#"{"kind": "key", "key": \#(Self.key(105))}"#, #"{"kind": "none"}"#,
             .keyOutput(id: "r1", key: KeyCode(105), output: .none)),
        ]
        for (trigger, action, expected) in cases {
            let result = try definitions(trigger: trigger, action: action)
            #expect(result.unsupported.isEmpty, "\(trigger) \(result.unsupported)")
            #expect(result.definitions == [expected], "\(trigger)")
        }
    }

    @Test func inputSourceConditionIsRead() throws {
        let result = try definitions(
            trigger: #"{"kind": "key", "key": \#(Self.key(0))}"#, action: #"{"kind": "sendKey", "key": \#(Self.key(8))}"#,
            conditions: #"[{"kind": "inputSourceIs", "inputSourceId": "com.apple.keylayout.Polish"}]"#
        )
        #expect(result.definitions == [.remap(from: .a, to: .c, conditions: RuleConditions(inputSources: ["com.apple.keylayout.Polish"]))])
    }

    @Test func incompleteKeyboardRulesAreReported() throws {
        let cases: [(String, String)] = [
            (#"{"kind": "tapHold", "key": \#(Self.key(57)), "thresholdMs": 200}"#, #"{"kind": "tapHold", "tap": {"kind": "none"}}"#),
            (#"{"kind": "keyCombo", "keys": [\#(Self.key(38))]}"#, #"{"kind": "none"}"#),
            (#"{"kind": "keySequence", "keys": []}"#, #"{"kind": "none"}"#),
            (#"{"kind": "layerKey", "layerId": "", "key": \#(Self.key(4))}"#, #"{"kind": "none"}"#),
            (#"{"kind": "key", "key": \#(Self.key(4))}"#, #"{"kind": "holdModifiers", "modifiers": []}"#),
        ]
        for (trigger, action) in cases {
            let result = try definitions(trigger: trigger, action: action)
            #expect(result.definitions.isEmpty, "\(trigger)")
            #expect(result.unsupported.count == 1, "\(trigger)")
            if case .invalidKeyBehavior = result.unsupported.first?.reason {} else {
                Issue.record("\(trigger): \(String(describing: result.unsupported.first?.reason))")
            }
        }
    }
}
