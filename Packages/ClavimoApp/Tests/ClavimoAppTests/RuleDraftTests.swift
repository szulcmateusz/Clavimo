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
        remap.name = "F13 to Escape"
        remap.firstKey = 0x69
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
        var shortcutClick = fnClick
        shortcutClick.name = "Fn side: copy"
        shortcutClick.button = 4
        shortcutClick.action = .shortcut
        shortcutClick.shortcutKey = KeyCode.c.rawValue
        shortcutClick.shortcutModifiers = [.command, .shift]

        var tap = RuleDraft()
        tap.kind = .trackpadGesture
        tap.name = "Tap"
        tap.gesture = .tap
        tap.fingers = 3
        tap.action = .middleClick

        var swipe = RuleDraft()
        swipe.kind = .trackpadGesture
        swipe.name = "Swipe"
        swipe.gesture = .swipe
        swipe.fingers = 4
        swipe.direction = .up
        swipe.trackpadModifiers = [.function]
        swipe.action = .media
        swipe.mediaKey = .volumeUp
        swipe.onlyApps = ["com.apple.Music"]

        var tipTap = RuleDraft()
        tipTap.kind = .trackpadGesture
        tipTap.name = "Tip tap"
        tipTap.gesture = .tipTap
        tipTap.side = .left
        tipTap.action = .launchApp
        tipTap.appBundleID = "com.apple.Safari"

        var rotate = RuleDraft()
        rotate.kind = .trackpadGesture
        rotate.name = "Knob"
        rotate.gesture = .rotate
        rotate.fingers = 2
        rotate.rotation = .counterclockwise
        rotate.zone = .left
        rotate.action = .media
        rotate.mediaKey = .volumeDown

        var corner = RuleDraft()
        corner.kind = .trackpadClick
        corner.name = "Corner"
        corner.clickPlace = .corner
        corner.corner = .bottomLeft
        corner.action = .backClick

        var click = RuleDraft()
        click.kind = .trackpadClick
        click.name = "Click"
        click.clickPlace = .fingers
        click.fingers = 4
        click.action = .forwardClick
        return [swap, remap, fnClick, keyClick, shortcutClick, tap, swipe, tipTap, rotate, corner, click]
    }

    @Test func trackpadScrollDraftBecomesTrackpadSetting() throws {
        var draft = RuleDraft()
        draft.kind = .trackpadScroll
        draft.trackpadScroll = TrackpadScrollSettings(reverseVertical: false, reverseHorizontal: true, speed: 1.5, momentum: false)
        let setting = draft.makeDeviceSetting(id: "t")
        #expect(setting["scope"]?["deviceClass"]?.string == "trackpad")
        let back = try #require(RuleDraft(deviceSetting: setting))
        #expect(back.kind == .trackpadScroll)
        #expect(back.trackpadScroll == draft.trackpadScroll)
        var document = ConfigDocument(rules: [])
        document.deviceSettings = [setting]
        let interpreted = try ConfigDocument.decode(try document.encoded()).interpret()
        #expect(interpreted.unsupported.isEmpty)
        #expect(interpreted.definitions == [.trackpadScroll(draft.trackpadScroll)])
    }

    @Test func twoFingerTapNeedsAModifier() {
        var draft = RuleDraft()
        draft.kind = .trackpadGesture
        draft.gesture = .tap
        draft.fingers = 2
        #expect(draft.validationMessage != nil)
        draft.trackpadModifiers = [.command]
        #expect(draft.validationMessage == nil)
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
        #expect(interpreted.definitions == [.wheel(vertical: ScrollAxisSettings(reverse: true), horizontal: .unchanged)])

        var modes = RuleDraft()
        modes.kind = .wheel
        modes.name = "Modes"
        modes.vertical.mode = .byLines
        modes.vertical.lines = 3
        modes.horizontal.mode = .accelerated
        modes.horizontal.speed = 1.5
        let modeSetting = modes.makeDeviceSetting(id: "m")
        #expect(RuleDraft(deviceSetting: modeSetting) == modes)
        #expect(try ConfigDocument(deviceSettings: [modeSetting]).interpret().definitions == [
            .wheel(vertical: ScrollAxisSettings(reverse: true, mode: .byLines(3)),
                   horizontal: ScrollAxisSettings(mode: .accelerated(speed: 1.5))),
        ])
    }

    @Test func smoothScrollingSurvivesRoundTrip() throws {
        var smooth = RuleDraft()
        smooth.kind = .wheel
        smooth.name = "Smooth"
        smooth.vertical.mode = .smoothed
        smooth.vertical.pixels = 80
        smooth.vertical.duration = 0.3
        let setting = smooth.makeDeviceSetting(id: "s")
        #expect(RuleDraft(deviceSetting: setting) == smooth)
        #expect(try ConfigDocument(deviceSettings: [setting]).interpret().definitions == [
            .wheel(vertical: ScrollAxisSettings(reverse: true, mode: .smoothed(SmoothScroller.Settings(pixelsPerNotch: 80, duration: 0.3))),
                   horizontal: .unchanged),
        ])
    }

    @Test func invalidDraftsExplainWhy() {
        var sameKeys = RuleDraft()
        sameKeys.secondKey = sameKeys.firstKey
        #expect(sameKeys.validationMessage != nil)

        var noModifier = RuleDraft()
        noModifier.kind = .modifierClick
        noModifier.modifiers = []
        #expect(noModifier.validationMessage == nil, "a side button can act alone")
        noModifier.button = 2
        #expect(noModifier.validationMessage != nil, "the right button needs a modifier")

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

    @Test func profilesCanBeAddedActivatedAndDeleted() throws {
        let (editor, _) = try makeEditor()
        var base = RuleDraft()
        base.profileID = "default"
        #expect(editor.upsert(base, id: nil) == nil)

        let games = try #require(editor.addProfile(named: "Games"))
        #expect(editor.profiles.map(\.id) == ["default", games])
        #expect(editor.ancestors(of: games) == ["default"])

        var override = RuleDraft()
        override.kind = .remapKey
        override.firstKey = KeyCode.rightCommand.rawValue
        override.secondKey = KeyCode.escape.rawValue
        override.profileID = games
        #expect(editor.upsert(override, id: nil) == nil, "a profile may override an inherited key")
        #expect(editor.setActiveProfile(games) == nil)
        #expect(editor.activeProfileID == games)
        let interpreted = try #require(editor.document).interpret()
        #expect(interpreted.definitions.contains(.remap(from: .rightCommand, to: .escape)))

        #expect(editor.deleteProfile(games) == nil)
        #expect(editor.activeProfileID == "default")
        #expect(editor.rows.allSatisfy { $0.profileID == "default" })
        #expect(editor.deleteProfile("default") == nil && editor.profiles.count == 1, "the base profile stays")
    }
}

@Suite("Configuration diff")
struct ConfigDiffTests {
    static func document(_ drafts: [(String, RuleDraft)], active: String = "default") -> ConfigDocument {
        ConfigDocument(activeProfileId: active, rules: drafts.enumerated().map { $1.1.makeRule(id: $1.0, order: $0) })
    }

    @Test func detectsAddedChangedAndRemovedRules() {
        var a = RuleDraft(); a.name = "A"
        var b = RuleDraft(); b.name = "B"; b.firstKey = KeyCode.leftCommand.rawValue; b.secondKey = KeyCode.leftOption.rawValue
        var bChanged = b; bChanged.enabled = false
        var c = RuleDraft(); c.name = "C"; c.kind = .remapKey; c.firstKey = 0x69; c.secondKey = KeyCode.escape.rawValue

        let diff = ConfigDiff(from: Self.document([("a", a), ("b", b)]), to: Self.document([("b", bChanged), ("c", c)]))
        #expect(diff.added.map(\.name) == ["C"])
        #expect(diff.changed.map(\.name) == ["B"])
        #expect(diff.removed.map(\.name) == ["A"])
        #expect(!diff.isEmpty)
    }

    @Test func identicalDocumentsHaveNoChanges() {
        var a = RuleDraft(); a.name = "A"
        let document = Self.document([("a", a)])
        #expect(ConfigDiff(from: document, to: document).isEmpty)
    }

    @Test func reportsUnsupportedIncomingRules() {
        var bad = RuleDraft()
        bad.kind = .remapKey
        bad.firstKey = KeyCode.a.rawValue
        bad.secondKey = KeyCode.g.rawValue
        var rule = bad.makeRule(id: "x", order: 0)
        rule.conditions = [.object(["kind": .string("timeOfDay")])]
        let diff = ConfigDiff(from: nil, to: ConfigDocument(rules: [rule]))
        #expect(diff.unsupported.map(\.ruleID) == ["x"])
        #expect(diff.added.map(\.id) == ["x"])
    }
}
