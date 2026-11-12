import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Action compasses in the app")
struct CompassAppTests {
    static let base = PastedRulesTests.base

    @Test func anAnswerWithACompassAndItsTrigger() throws {
        let answer = """
        Here is a compass for Safari, opened by holding button 4:

        ```json
        {
          "compasses": [{
            "name": "Browsing",
            "slots": [
              {"direction": "up", "name": "New tab", "action": {"kind": "sendShortcut", "key": {"codeNamespace": "macVirtualKeyCode", "code": 17}, "modifiers": ["command"]}},
              {"direction": "left", "action": {"kind": "menuItem", "path": ["History", "Back"]}}
            ]
          }],
          "rules": [{
            "name": "Button 4 opens the compass",
            "trigger": {"kind": "mouseButton", "mouseButton": 4},
            "action": {"kind": "openCompass", "compassId": "browsing"}
          }]
        }
        ```
        """
        let document = try PastedRules.apply(answer, to: Self.base).get()
        #expect(document.compasses?.map(\.id) == ["browsing"])
        #expect(document.rules.count == 1)
        let interpreted = try document.interpret()
        #expect(interpreted.unsupported.isEmpty)
        #expect(interpreted.compasses["browsing"]?.slots[.left]?.action == .action(.menuItem(["History", "Back"])))
        let rules = try CompiledRules.compile(interpreted.definitions).get()
        #expect(rules.openedCompasses == ["browsing"])
    }

    @Test func aSingleCompassReplacesTheOneWithItsID() throws {
        var document = Self.base
        document.compasses = [ConfigDocument.Compass(id: "main", name: "Main", slots: [])]
        let pasted = #"{"id": "main", "name": "Main", "slots": [{"direction": "down", "action": {"kind": "missionControl"}}]}"#
        let result = try PastedRules.apply(pasted, to: document).get()
        #expect(result.compasses?.count == 1)
        #expect(result.compasses?.first?.slots.map(\.direction) == ["down"])
    }

    @Test func compassesWithoutAnIDGetAFreeOne() throws {
        var document = Self.base
        document.compasses = [ConfigDocument.Compass(id: "work", name: "Work", slots: [])]
        let pasted = #"[{"name": "Work", "slots": []}, {"slots": []}]"#
        let result = try PastedRules.apply(pasted, to: document).get()
        #expect(result.compasses?.map(\.id) == ["work", "work2", "compass"])
    }

    @Test func draftsRoundTrip() throws {
        let compass = ConfigDocument.Compass(
            id: "main", name: "Main",
            slots: [
                .init(direction: "up", name: "Overview", action: .object(["kind": .string("missionControl")])),
                .init(direction: "left", action: .object(["kind": .string("someFutureAction"), "x": .number(1)])),
            ],
            apps: [.init(bundleId: "com.apple.Safari", slots: [
                .init(direction: "up", action: .object(["kind": .string("none")])),
            ])],
            hintDelayMs: 400
        )
        let draft = CompassDraft(compass)
        #expect(draft.slots[.up]?.title == "Overview")
        #expect(draft.slots[.left]?.raw != nil, "an action the form cannot show is kept as written")
        #expect(draft.apps["com.apple.Safari"]?[.up]?.hidden == true)
        #expect(draft.document == compass)
    }

    @Test func templatesFillPages() {
        var draft = CompassDraft(id: "main", name: "Main")
        CompassTemplates.everyday.apply(to: &draft)
        #expect(draft.slots.count == 8)
        CompassTemplates.browser.apply(to: &draft)
        #expect(draft.appOrder.contains("com.apple.Safari"))
        #expect(draft.apps["com.apple.Safari"]?.count == 8)
        #expect(draft.validationMessage == nil)
        let interpreted = try? ConfigDocument(compasses: [draft.document]).interpret()
        #expect(interpreted?.unsupported.isEmpty == true)
    }

    @Test func ringZonesMatchWhatAMovePicks() {
        let two = CompassView.zones(for: [.right, .left])
        #expect(two.map(\.direction) == [.right, .left])
        #expect(two.map { $0.end - $0.start } == [180, 180], "two actions get half the ring each")
        let four = CompassView.zones(for: [.up, .right, .down, .left])
        #expect(four.allSatisfy { $0.end - $0.start == 90 })
        #expect(CompassView.zones(for: [.up]).first.map { $0.end - $0.start } == 360)
        // Every angle in a zone picks that zone's direction.
        for zone in CompassView.zones(for: [.up, .downRight, .left]) {
            let middle = (zone.start + zone.end) / 2 * .pi / 180
            #expect(CompassGeometry.direction(dx: cos(middle) * 100, dy: sin(middle) * 100,
                                              among: [.up, .downRight, .left], deadZone: 40) == zone.direction)
        }
    }

    @Test func swappingDirections() {
        var draft = CompassDraft(id: "main", name: "Main")
        CompassTemplates.everyday.apply(to: &draft)
        let up = draft.slots[.up]
        let down = draft.slots[.down]
        draft.swap(.up, .down, page: nil)
        #expect(draft.slots[.up] == down)
        #expect(draft.slots[.down] == up)
    }

    @Test func rulesOpenCompassesAndMenuItems() throws {
        var draft = RuleDraft()
        draft.kind = .modifierClick
        draft.modifiers = []
        draft.button = 4
        draft.action = .openCompass
        draft.compassID = "main"
        #expect(draft.validationMessage == nil)
        let rule = draft.makeRule(id: "r", order: 0)
        #expect(rule.trigger["kind"]?.string == "mouseButton")
        #expect(RuleDraft(rule: rule) == draft.withName(rule.name))

        draft.action = .menuItem
        draft.menuPath = []
        #expect(draft.validationMessage != nil)
        draft.menuPath = ["File", "New Tab"]
        #expect(RuleDraft(rule: draft.makeRule(id: "r", order: 0))?.menuPath == ["File", "New Tab"])

        draft.button = 1
        draft.action = .missionControl
        #expect(draft.validationMessage != nil, "the left button needs a modifier")
    }

    @Test func keysCanHoldACompass() throws {
        var draft = KeyboardRuleDraft(kind: .tapHold)
        draft.hold = OutputDraft.of(.compass)
        draft.hold.action.compassID = "main"
        #expect(draft.validationMessage == nil)
        let rule = draft.makeRule(id: "k", order: 0)
        #expect(rule.action["hold"]?["kind"]?.string == "openCompass")
        let read = try #require(KeyboardRuleDraft(rule: rule))
        #expect(read.hold.kind == .compass)
        #expect(read.hold.action.compassID == "main")
        #expect(ConfigEditor.opens("main", rule))
    }
}

private extension RuleDraft {
    func withName(_ name: String) -> RuleDraft {
        var copy = self
        copy.name = name
        return copy
    }
}
