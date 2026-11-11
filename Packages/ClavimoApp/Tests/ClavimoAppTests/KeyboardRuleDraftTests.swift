import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Keyboard rules in the form")
struct KeyboardRuleDraftTests {
    static func drafts() -> [KeyboardRuleDraft] {
        var caps = KeyboardRuleDraft()
        caps.name = "Caps"
        caps.doubleTapEnabled = true
        caps.onlyApps = ["com.apple.Safari"]
        caps.inputSources = ["com.apple.keylayout.Polish"]

        let homeRow = KeyboardRuleDraft.homeRow(key: 0x03, modifier: .command, holdAfter: 230, profileID: "default")

        var output = KeyboardRuleDraft(kind: .keyOutput)
        output.output = .of(.action)
        output.output.action.action = .launchApp
        output.output.action.appBundleID = "com.apple.Safari"

        var oneShot = KeyboardRuleDraft(kind: .keyOutput)
        oneShot.key = 0x6A
        oneShot.output = .modifiers([.shift])
        oneShot.output.kind = .oneShot

        var layerKey = KeyboardRuleDraft(kind: .layerKey)
        layerKey.output.kind = .shortcut
        layerKey.output.modifiers = [.command]

        var combo = KeyboardRuleDraft(kind: .combo)
        combo.windowMilliseconds = 40

        var sequence = KeyboardRuleDraft(kind: .sequence)
        sequence.keys = [0x1F, 0x01]
        sequence.output = .key(KeyCode.escape.rawValue)

        return [caps, homeRow, output, oneShot, layerKey, combo, sequence]
    }

    @Test func formSurvivesTheFileRoundTrip() throws {
        for draft in Self.drafts() {
            #expect(draft.validationMessage == nil, "\(draft.displayName): \(draft.validationMessage ?? "")")
            let rule = draft.makeRule(id: "r1", order: 0)
            let data = try JSONEncoder().encode(rule)
            let decoded = try JSONDecoder().decode(ConfigDocument.Rule.self, from: data)
            let reread = try #require(KeyboardRuleDraft(rule: decoded), "\(draft.displayName)")
            #expect(reread.makeRule(id: "r1", order: 0) == rule, "\(draft.displayName)")
            #expect(reread.kind == draft.kind && reread.key == draft.key && reread.output.kind == draft.output.kind)
        }
    }

    /// Every template must load and compile as a whole, together with the
    /// home row modifiers and a Caps Lock rule.
    @Test func templatesCompile() throws {
        var document = ConfigDocument()
        var drafts = KeyboardTemplates.all.flatMap(\.drafts)
        drafts.append(KeyboardRuleDraft()) // Caps Lock: Escape / Hyper
        for (key, modifier) in zip([UInt16(0x00), 0x01, 0x02, 0x03], [RuleDraft.Modifier.command, .option, .control, .shift]) {
            drafts.append(.homeRow(key: key, modifier: modifier, holdAfter: 220, profileID: "default"))
        }
        // The number pad and the navigation layer both use J, K, L on
        // different layers, which is fine; the Escape combo uses J and K.
        for (index, draft) in drafts.enumerated() {
            #expect(draft.validationMessage == nil, "\(draft.displayName): \(draft.validationMessage ?? "")")
            document.rules.append(draft.makeRule(id: "r\(index)", order: index))
        }
        let interpreted = try document.interpret()
        #expect(interpreted.unsupported.isEmpty, "\(interpreted.unsupported)")
        let compiled = CompiledRules.compile(interpreted.definitions)
        if case let .failure(failure) = compiled { Issue.record("\(failure.errors)") }
        #expect(interpreted.definitions.count == drafts.count)
    }

    @Test func modifierKeysKeepTheirHold() {
        var draft = KeyboardRuleDraft()
        draft.key = KeyCode.rightOption.rawValue
        draft.output = .of(.startSequence)
        draft.hold = .layer("nav")
        #expect(draft.validationMessage != nil)
        draft.hold = .modifiers([.option])
        #expect(draft.validationMessage == nil)
        let rule = draft.makeRule(id: "r1", order: 0)
        #expect(rule.action["hold"]?["modifiers"] == .array([.string("rightOption")]))
    }
}
