import Foundation
import Testing
@testable import ClavimoCore

@Suite("Config v1 interpretation")
struct ConfigTests {
    static func document(rules: String, active: String = "default") -> String {
        """
        {
          "schemaVersion": 1,
          "configId": "00000000-0000-4000-8000-000000000001",
          "engine": {"enabledOnLaunch": true, "failOpen": true},
          "activeProfileId": "\(active)",
          "profiles": [{"id": "default", "name": "Default", "inherits": null}],
          "rules": [\(rules)],
          "macros": []
        }
        """
    }

    static func rule(
        id: String = "r1",
        enabled: Bool = true,
        profile: String = "default",
        trigger: String,
        action: String,
        behavior: String = #"{"consumeTrigger": true, "fireOn": "down", "repeat": "once"}"#,
        conditions: String = "[]"
    ) -> String {
        """
        {"id": "\(id)", "name": "Rule \(id)", "enabled": \(enabled), "priority": 50, "profileId": "\(profile)",
         "trigger": \(trigger), "conditions": \(conditions), "action": \(action), "behavior": \(behavior), "ui": {"order": 0}}
        """
    }

    func interpret(_ json: String) throws -> InterpretedConfig {
        try ConfigDocument.decode(Data(json.utf8)).interpret()
    }

    @Test func swapRuleBecomesSwapDefinition() throws {
        let json = Self.document(rules: Self.rule(
            trigger: #"{"kind": "keyPair", "first": {"codeNamespace": "macVirtualKeyCode", "code": 54}, "second": {"codeNamespace": "macVirtualKeyCode", "code": 61}}"#,
            action: #"{"kind": "swapKeys", "sideMode": "asSpecified"}"#
        ))
        let result = try interpret(json)
        #expect(result.definitions == [.swap(.rightCommand, .rightOption)])
        #expect(result.unsupported.isEmpty)
    }

    @Test func fnClickChordNeedsExplicitProtectedOptIn() throws {
        let trigger = #"{"kind": "modifierChord", "requiredModifiers": ["function"], "mouseButton": 1}"#
        let json = Self.document(rules: Self.rule(
            trigger: trigger,
            action: #"{"kind": "previousWorkspace"}"#,
            behavior: #"{"consumeTrigger": true, "fireOn": "down", "repeat": "once", "allowProtectedButton": true}"#
        ))
        let result = try interpret(json)
        #expect(result.definitions == [
            .mouseChord(id: "r1", leader: .modifiers(.function), button: .primary, action: .previousWorkspace, priority: 50, allowProtectedButton: true),
        ])
        let rules = try CompiledRules.compile(result.definitions).get()
        #expect(rules.observesProtectedButtons)
    }

    @Test func letterChordRequiresExplicitPolicy() throws {
        let trigger = #"{"kind": "keyMouseChord", "leaderKey": {"codeNamespace": "macVirtualKeyCode", "code": 3}, "mouseButton": 4, "order": "leaderThenMouse"}"#
        let withPolicy = try interpret(Self.document(rules: Self.rule(
            trigger: trigger,
            action: #"{"kind": "nextWorkspace"}"#,
            behavior: #"{"consumeTrigger": true, "fireOn": "down", "repeat": "once", "leaderPolicy": "boundedWindow", "leaderWindowMs": 120}"#
        )))
        #expect(withPolicy.definitions == [
            .mouseChord(id: "r1", leader: .key(.f, .boundedWindow(milliseconds: 120)), button: .button4, action: .nextWorkspace, priority: 50),
        ])
        let withoutPolicy = try interpret(Self.document(rules: Self.rule(trigger: trigger, action: #"{"kind": "nextWorkspace"}"#)))
        #expect(withoutPolicy.definitions.isEmpty)
        #expect(withoutPolicy.unsupported.count == 1)
    }

    @Test func disabledAndOtherProfileRulesAreIgnoredSilently() throws {
        let swap = #"{"kind": "keyPair", "first": {"codeNamespace": "macVirtualKeyCode", "code": 55}, "second": {"codeNamespace": "macVirtualKeyCode", "code": 58}}"#
        let action = #"{"kind": "swapKeys", "sideMode": "left"}"#
        let json = Self.document(rules: [
            Self.rule(id: "a", enabled: false, trigger: swap, action: action),
            Self.rule(id: "b", profile: "other", trigger: swap, action: action),
        ].joined(separator: ","))
        let result = try interpret(json)
        #expect(result.definitions.isEmpty)
        #expect(result.unsupported.isEmpty)
    }

    @Test func unsupportedRulesAreReportedNotApplied() throws {
        let json = Self.document(rules: [
            Self.rule(id: "cond",
                      trigger: #"{"kind": "modifierChord", "requiredModifiers": ["shift"], "mouseButton": 5}"#,
                      action: #"{"kind": "previousWorkspace"}"#,
                      conditions: #"[{"kind": "physicalDeviceIs", "deviceId": "logitech"}]"#),
            Self.rule(id: "side",
                      trigger: #"{"kind": "modifierChord", "requiredModifiers": ["leftShift"], "mouseButton": 5}"#,
                      action: #"{"kind": "previousWorkspace"}"#),
            Self.rule(id: "macro",
                      trigger: #"{"kind": "mouseButton", "mouseButton": 4, "phase": "down"}"#,
                      action: #"{"kind": "runMacro", "macroId": "m"}"#),
            Self.rule(id: "hid",
                      trigger: #"{"kind": "key", "key": {"codeNamespace": "hidUsage", "code": 57}}"#,
                      action: #"{"kind": "sendKey", "key": {"codeNamespace": "macVirtualKeyCode", "code": 53}}"#),
        ].joined(separator: ","))
        let result = try interpret(json)
        #expect(result.definitions.isEmpty)
        #expect(result.unsupported.map(\.ruleID) == ["cond", "side", "macro", "hid"])
    }

    @Test func rejectsFutureSchemaVersion() {
        let json = Self.document(rules: "").replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        #expect(throws: ConfigLoadError.unsupportedSchemaVersion(2)) {
            try ConfigDocument.decode(Data(json.utf8))
        }
    }

    @Test func rejectsUnknownActiveProfile() {
        #expect(throws: ConfigLoadError.unknownActiveProfile("missing")) {
            try interpret(Self.document(rules: "", active: "missing"))
        }
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: (any Error).self) {
            try ConfigDocument.decode(Data("{\"schemaVersion\": 1".utf8))
        }
    }

    @Test func conditionsAreTranslated() throws {
        let json = Self.document(rules: Self.rule(
            trigger: #"{"kind": "keyPair", "first": {"codeNamespace": "macVirtualKeyCode", "code": 54}, "second": {"codeNamespace": "macVirtualKeyCode", "code": 61}}"#,
            action: #"{"kind": "swapKeys", "sideMode": "right"}"#,
            conditions: #"[{"kind": "physicalDeviceIs", "deviceId": "1452:835"}, {"kind": "appIsNot", "bundleId": "com.apple.Terminal"}]"#
        ))
        let result = try interpret(json)
        let expected = RuleConditions(exceptApps: ["com.apple.Terminal"], devices: [DeviceID(vendorID: 1452, productID: 835)])
        #expect(result.definitions == [.swap(.rightCommand, .rightOption, conditions: expected)])
    }

    @Test func mouseWheelReversalFromDeviceSettings() throws {
        var json = Self.document(rules: "")
        json = json.replacingOccurrences(of: "\"macros\": []", with: """
        "macros": [],
        "deviceSettings": [
          {"id": "w", "name": "Mouse wheel", "enabled": true, "profileId": "default", "priority": 1,
           "scope": {"deviceClass": "mouse"},
           "scrolling": {"vertical": {"reverse": true}, "horizontal": {"reverse": false, "mode": "system"}}},
          {"id": "d", "name": "One mouse", "enabled": true, "profileId": "default", "priority": 1,
           "scope": {"deviceClass": "mouse", "vendorId": 1133, "productId": 49298}, "scrolling": {"vertical": {"reverse": true}}},
          {"id": "t", "name": "Trackpad", "enabled": true, "profileId": "default", "priority": 1,
           "scope": {"deviceClass": "trackpad"}, "scrolling": {"vertical": {"reverse": true}}},
          {"id": "p", "name": "Pointer", "enabled": true, "profileId": "default", "priority": 1,
           "scope": {"deviceClass": "mouse"}, "pointer": {"accelerationMode": "disabled"}},
          {"id": "off", "name": "Disabled", "enabled": false, "profileId": "default", "priority": 1,
           "scope": {"deviceClass": "mouse"}, "scrolling": {"vertical": {"reverse": true}}}
        ]
        """)
        let result = try interpret(json)
        #expect(result.definitions == [
            .reverseWheel(vertical: true, horizontal: false),
        ])
        #expect(result.unsupported.map(\.ruleID) == ["d", "t", "p"])
    }
}
