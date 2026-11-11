import ClavimoCore
import Foundation

/// Ready-made sets of keyboard rules. Each shows a different idea: a layer,
/// a combo, a sequence, taps on modifier keys.
enum KeyboardTemplates {
    struct Template: Identifiable {
        let id: String
        let title: String
        let summary: String
        let symbol: String
        let drafts: [KeyboardRuleDraft]
    }

    static var all: [Template] { [navigation, numbers, escapeCombo, leader, parentheses, japaneseInput] }

    private static func layerKey(_ layer: String, _ key: UInt16, _ output: OutputDraft) -> KeyboardRuleDraft {
        var draft = KeyboardRuleDraft(kind: .layerKey)
        draft.layer = layer
        draft.key = key
        draft.output = output
        return draft
    }

    private static func shortcut(_ key: UInt16, _ modifiers: Set<RuleDraft.Modifier>) -> OutputDraft {
        var output = OutputDraft.key(key)
        output.kind = .shortcut
        output.modifiers = modifiers
        return output
    }

    private static func layerKeyHold(_ key: UInt16, layer: String, name: String) -> KeyboardRuleDraft {
        var draft = KeyboardRuleDraft()
        draft.name = name
        draft.kind = .tapHold
        draft.key = key
        draft.output = .key(key)
        draft.hold = .layer(layer)
        draft.interrupt = .permissive
        draft.typingStreakMilliseconds = TapHoldSettings.homeRow.typingStreakMilliseconds
        return draft
    }

    static var navigation: Template {
        let arrows: [(UInt16, OutputDraft)] = [
            (0x04, .key(KeyCode.leftArrow.rawValue)), (0x26, .key(KeyCode.downArrow.rawValue)),
            (0x28, .key(KeyCode.upArrow.rawValue)), (0x25, .key(KeyCode.rightArrow.rawValue)),
            (0x10, shortcut(KeyCode.leftArrow.rawValue, [.command])), (0x1F, shortcut(KeyCode.rightArrow.rawValue, [.command])),
            (0x20, shortcut(KeyCode.leftArrow.rawValue, [.option])), (0x22, shortcut(KeyCode.rightArrow.rawValue, [.option])),
        ]
        return Template(
            id: "navigation",
            title: String(localized: "Arrows under your right hand"),
            summary: String(localized: "Hold Space: H J K L are arrows, U I jump by word, Y O go to the line start or end. Tap Space to type a space. Shift still selects."),
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            drafts: [layerKeyHold(KeyCode.space.rawValue, layer: "nav", name: String(localized: "Hold Space for arrows"))]
                + arrows.map { layerKey("nav", $0.0, $0.1) }
        )
    }

    static var numbers: Template {
        let digits: [(UInt16, UInt16)] = [
            (0x20, 0x1A), (0x22, 0x1C), (0x1F, 0x19), // U I O -> 7 8 9
            (0x26, 0x15), (0x28, 0x17), (0x25, 0x16), // J K L -> 4 5 6
            (0x2E, 0x12), (0x2B, 0x13), (0x2F, 0x14), // M , . -> 1 2 3
            (0x2D, 0x1D),                             // N -> 0
        ]
        return Template(
            id: "numbers",
            title: String(localized: "A number pad under your right hand"),
            summary: String(localized: "Hold Tab: U I O, J K L and M , . type 7 to 1 like a number pad, N types 0. Tap Tab as usual."),
            symbol: "number",
            drafts: [layerKeyHold(KeyCode.tab.rawValue, layer: "num", name: String(localized: "Hold Tab for numbers"))]
                + digits.map { layerKey("num", $0.0, .key($0.1)) }
        )
    }

    static var escapeCombo: Template {
        var draft = KeyboardRuleDraft(kind: .combo)
        draft.name = String(localized: "J + K: Escape")
        draft.keys = [0x26, 0x28]
        draft.output = .key(KeyCode.escape.rawValue)
        return Template(
            id: "escapeCombo",
            title: String(localized: "J and K together type Escape"),
            summary: String(localized: "Press J and K at the same moment for Escape. Typing J or K alone works as usual."),
            symbol: "rectangle.on.rectangle",
            drafts: [draft]
        )
    }

    static var leader: Template {
        var leaderKey = KeyboardRuleDraft()
        leaderKey.kind = .tapHold
        leaderKey.key = KeyCode.rightOption.rawValue
        leaderKey.output = .of(.startSequence)
        leaderKey.hold = .modifiers([.option])
        leaderKey.name = String(localized: "Tap Right Option to start a sequence")
        let apps: [(UInt16, String)] = [
            (0x01, "com.apple.Safari"), (0x03, "com.apple.finder"), (0x11, "com.apple.Terminal"),
            (0x2D, "com.apple.Notes"), (0x2E, "com.apple.mail"),
        ]
        let sequences = apps.map { key, bundleID -> KeyboardRuleDraft in
            var draft = KeyboardRuleDraft(kind: .sequence)
            draft.keys = [key]
            draft.output = .of(.action)
            draft.output.action.action = .launchApp
            draft.output.action.appBundleID = bundleID
            return draft
        }
        return Template(
            id: "leader",
            title: String(localized: "Open apps with a key sequence"),
            summary: String(localized: "Tap Right Option alone, then S for Safari, F for Finder, T for Terminal, N for Notes or M for Mail. A panel shows the choices."),
            symbol: "arrow.right.to.line",
            drafts: [leaderKey] + sequences
        )
    }

    static var parentheses: Template {
        func shiftTap(_ key: KeyCode, _ digit: UInt16) -> KeyboardRuleDraft {
            var draft = KeyboardRuleDraft()
            draft.kind = .tapHold
            draft.key = key.rawValue
            draft.output = shortcut(digit, [.shift])
            draft.hold = .modifiers([.shift])
            draft.name = String(localized: "Tap \(KeyNames.name(for: key.rawValue)): \(draft.output.title)")
            return draft
        }
        return Template(
            id: "parentheses",
            title: String(localized: "Tap Shift for parentheses"),
            summary: String(localized: "Tap Left Shift alone for ( and Right Shift for ). Held, they are Shift as always."),
            symbol: "parentheses",
            drafts: [shiftTap(.leftShift, 0x19), shiftTap(.rightShift, 0x1D)]
        )
    }

    static var japaneseInput: Template {
        func commandTap(_ key: KeyCode, _ output: KeyCode) -> KeyboardRuleDraft {
            var draft = KeyboardRuleDraft()
            draft.kind = .tapHold
            draft.key = key.rawValue
            draft.output = .key(output.rawValue)
            draft.hold = .modifiers([.command])
            draft.name = String(localized: "Tap \(KeyNames.name(for: key.rawValue)): \(KeyNames.name(for: output.rawValue))")
            return draft
        }
        return Template(
            id: "japaneseInput",
            title: String(localized: "Tap ⌘ to switch input (英数 / かな)"),
            summary: String(localized: "Tap Left Command for 英数 and Right Command for かな, like on a Japanese keyboard. Held, they are Command as always."),
            symbol: "character.ja",
            drafts: [commandTap(.leftCommand, .jisEisu), commandTap(.rightCommand, .jisKana)]
        )
    }
}
