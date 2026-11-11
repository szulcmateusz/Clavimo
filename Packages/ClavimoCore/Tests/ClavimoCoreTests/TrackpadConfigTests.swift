import Foundation
import Testing
@testable import ClavimoCore

@Suite("Trackpad rules in the configuration")
struct TrackpadConfigTests {
    func definitions(trigger: String, action: String, conditions: String = "[]") throws -> InterpretedConfig {
        let json = ConfigTests.document(rules: ConfigTests.rule(trigger: trigger, action: action, conditions: conditions))
        return try ConfigDocument.decode(Data(json.utf8)).interpret()
    }

    @Test func gesturesAndClicksAreRead() throws {
        let cases: [(String, String, RuleDefinition)] = [
            (#"{"kind": "trackpadGesture", "gesture": "tap", "fingers": 3}"#, #"{"kind": "mouseClick", "mouseButton": 3}"#,
             .trackpad(id: "r1", trigger: .gesture(.tap(fingers: 3)), action: .click(.middle), priority: 50)),
            (#"{"kind": "trackpadGesture", "gesture": "swipe", "fingers": 3, "direction": "left", "requiredModifiers": ["function"]}"#,
             #"{"kind": "sendShortcut", "key": {"codeNamespace": "macVirtualKeyCode", "code": 33}, "modifiers": ["command"]}"#,
             .trackpad(id: "r1", trigger: .gesture(.swipe(fingers: 3, .left)), modifiers: .function,
                       action: .shortcut(KeyCode(33), .command), priority: 50)),
            (#"{"kind": "trackpadGesture", "gesture": "tipTap", "side": "right"}"#, #"{"kind": "launchApp", "bundleId": "com.apple.Safari"}"#,
             .trackpad(id: "r1", trigger: .gesture(.tipTap(.right)), action: .launchApp("com.apple.Safari"), priority: 50)),
            (#"{"kind": "trackpadClick", "fingers": 3}"#, #"{"kind": "mediaKey", "key": "playPause"}"#,
             .trackpad(id: "r1", trigger: .click(fingers: 3), action: .media(.playPause), priority: 50)),
            (#"{"kind": "trackpadClick", "corner": "topRight"}"#, #"{"kind": "missionControl"}"#,
             .trackpad(id: "r1", trigger: .cornerClick(.topRight), action: .missionControl, priority: 50)),
        ]
        for (trigger, action, expected) in cases {
            let result = try definitions(trigger: trigger, action: action)
            #expect(result.unsupported.isEmpty, "\(trigger)")
            #expect(result.definitions == [expected])
        }
    }

    @Test func incompleteGesturesAreReported() throws {
        for trigger in [
            #"{"kind": "trackpadGesture", "gesture": "swipe", "fingers": 3}"#,
            #"{"kind": "trackpadGesture", "gesture": "tap"}"#,
            #"{"kind": "trackpadGesture", "gesture": "pinch", "fingers": 3}"#,
            #"{"kind": "trackpadClick", "corner": "middle"}"#,
            #"{"kind": "trackpadClick"}"#,
        ] {
            let result = try definitions(trigger: trigger, action: #"{"kind": "missionControl"}"#)
            #expect(result.definitions.isEmpty)
            #expect(result.unsupported.map(\.reason) == [.invalidTrackpadTrigger], "\(trigger)")
        }
    }

    @Test func deviceConditionsAreNotSupportedForTrackpadRules() throws {
        let result = try definitions(
            trigger: #"{"kind": "trackpadGesture", "gesture": "tap", "fingers": 3}"#, action: #"{"kind": "missionControl"}"#,
            conditions: #"[{"kind": "physicalDeviceIs", "deviceId": "1452:835"}]"#
        )
        #expect(result.unsupported.map(\.reason) == [.unsupportedCondition("physicalDeviceIs")])
    }

    @Test func unknownMediaKeyIsReported() throws {
        let result = try definitions(trigger: #"{"kind": "trackpadGesture", "gesture": "tap", "fingers": 4}"#,
                                     action: #"{"kind": "mediaKey", "key": "eject"}"#)
        #expect(result.unsupported.map(\.reason) == [.unsupportedAction("mediaKey")])
    }
}
