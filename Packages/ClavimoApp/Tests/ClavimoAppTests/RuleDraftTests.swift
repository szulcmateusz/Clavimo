import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Rule form round trip")
struct RuleDraftTests {
    static func drafts() -> [RuleDraft] {
        var swap = RuleDraft()
        swap.name = "Swap"
        swap.devices = ["1452:835"]

        var remap = RuleDraft()
        remap.kind = .remapKey
        remap.name = "Caps to Escape"
        remap.firstKey = KeyCode.capsLock.rawValue
        remap.secondKey = KeyCode.escape.rawValue
        remap.exceptApps = ["com.example.game"]

        var fnClick = RuleDraft()
        fnClick.kind = .modifierClick
        fnClick.name = "Fn click"
        fnClick.modifiers = [.function]
        fnClick.button = 1
        fnClick.action = .previousWorkspace

        var keyClick = RuleDraft()
        keyClick.kind = .keyClick
        keyClick.name = "F click"
        keyClick.firstKey = KeyCode.f.rawValue
        keyClick.button = 4
        keyClick.policy = .boundedWindow
        keyClick.windowMilliseconds = 150
        keyClick.onlyApps = ["com.apple.finder"]
        return [swap, remap, fnClick, keyClick]
    }

    @Test(arguments: drafts())
    func formSurvivesJSONRoundTrip(draft: RuleDraft) throws {
        let rule = draft.makeRule(id: "id", order: 0)
        let data = try ConfigDocument(rules: [rule]).encoded()
        let decoded = try ConfigDocument.decode(data)
        #expect(RuleDraft(rule: decoded.rules[0]) == draft)
        let interpreted = try decoded.interpret()
        #expect(interpreted.unsupported.isEmpty, "every form rule must be runnable: \(interpreted.unsupported)")
        #expect(throws: Never.self) { try CompiledRules.compile(interpreted.definitions).get() }
    }

    @Test func wheelDraftBecomesDeviceSetting() throws {
        var wheel = RuleDraft()
        wheel.kind = .wheel
        wheel.name = "Wheel"
        let setting = wheel.makeDeviceSetting(id: "w")
        #expect(RuleDraft(deviceSetting: setting) == wheel)
        let interpreted = try ConfigDocument(deviceSettings: [setting]).interpret()
        #expect(interpreted.definitions == [.reverseWheel(vertical: true, horizontal: false)])
    }

    @Test func invalidDraftsExplainWhy() {
        var sameKeys = RuleDraft()
        sameKeys.secondKey = sameKeys.firstKey
        #expect(sameKeys.validationMessage != nil)

        var noModifier = RuleDraft()
        noModifier.kind = .modifierClick
        noModifier.modifiers = []
        #expect(noModifier.validationMessage != nil)

        var letterOnLeftClick = RuleDraft()
        letterOnLeftClick.kind = .keyClick
        letterOnLeftClick.firstKey = KeyCode.f.rawValue
        letterOnLeftClick.button = 1
        #expect(letterOnLeftClick.validationMessage != nil)
    }
}

@Suite("Config editor")
@MainActor
struct ConfigEditorTests {
    func makeEditor(_ json: String? = nil) throws -> (ConfigEditor, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        if let json { try Data(json.utf8).write(to: file) }
        return (ConfigEditor(store: ConfigStore(fileURL: file)), file)
    }

    @Test func addEditToggleAndDelete() throws {
        let (editor, file) = try makeEditor()
        #expect(editor.rows.isEmpty)
        #expect(editor.upsert(RuleDraft(), id: nil) == nil)
        let id = try #require(editor.rows.first?.id)

        var changed = try #require(editor.rows.first?.draft)
        changed.secondKey = KeyCode.rightControl.rawValue
        #expect(editor.upsert(changed, id: id) == nil)
        #expect(editor.rows.count == 1)
        #expect(editor.rows.first?.draft?.secondKey == KeyCode.rightControl.rawValue)

        #expect(editor.setEnabled(false, id: id) == nil)
        #expect(editor.rows.first?.enabled == false)

        #expect(editor.delete(id: id) == nil)
        #expect(editor.rows.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("config.backup.json").path))
    }

    @Test func conflictingRuleIsRejectedAndFileUnchanged() throws {
        let (editor, file) = try makeEditor()
        editor.upsert(RuleDraft(), id: nil)
        let before = try Data(contentsOf: file)
        let error = editor.upsert(RuleDraft(), id: nil)
        #expect(error != nil, "a second identical swap must be rejected")
        #expect(try Data(contentsOf: file) == before)
        #expect(editor.rows.count == 1)
    }

    @Test func advancedRulesArePreservedWhenEditingOthers() throws {
        let advanced = """
        {"schemaVersion": 1, "configId": "c", "engine": {"enabledOnLaunch": false, "failOpen": true},
         "activeProfileId": "default", "profiles": [{"id": "default", "name": "Default", "inherits": null}],
         "rules": [{"id": "adv", "name": "Advanced", "enabled": true, "priority": 1, "profileId": "default",
                    "trigger": {"kind": "mouseButton", "mouseButton": 4, "phase": "down"}, "conditions": [],
                    "action": {"kind": "runMacro", "macroId": "m"},
                    "behavior": {"consumeTrigger": true, "fireOn": "down", "repeat": "once"}, "ui": {"order": 0}}],
         "macros": []}
        """
        let (editor, _) = try makeEditor(advanced)
        #expect(editor.rows.count == 1)
        #expect(editor.rows.first?.draft == nil)
        #expect(editor.upsert(RuleDraft(), id: nil) == nil)
        #expect(editor.document?.rules.first?.id == "adv")
        #expect(editor.document?.rules.first?.action["macroId"]?.string == "m")
    }
}
