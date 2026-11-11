import ClavimoCore

/// Ready-made starting points for common setups.
struct RuleTemplate: Identifiable {
    let id: String
    let title: String
    let draft: RuleDraft
}

enum RuleTemplates {
    static var all: [RuleTemplate] {
        var swapLeft = RuleDraft()
        swapLeft.firstKey = KeyCode.leftCommand.rawValue
        swapLeft.secondKey = KeyCode.leftOption.rawValue

        var swapRight = RuleDraft()
        swapRight.firstKey = KeyCode.rightCommand.rawValue
        swapRight.secondKey = KeyCode.rightOption.rawValue

        var fnLeft = RuleDraft()
        fnLeft.kind = .modifierClick
        fnLeft.modifiers = [.function]
        fnLeft.button = 1
        fnLeft.action = .previousWorkspace

        var fnRight = fnLeft
        fnRight.button = 2
        fnRight.action = .nextWorkspace

        var sideButton = RuleDraft()
        sideButton.kind = .modifierClick
        sideButton.modifiers = [.function]
        sideButton.button = 4
        sideButton.action = .missionControl

        var letterChord = RuleDraft()
        letterChord.kind = .keyClick
        letterChord.firstKey = KeyCode.f.rawValue
        letterChord.button = 4
        letterChord.action = .nextWorkspace

        return [
            RuleTemplate(id: "swap-left", title: String(localized: "Swap Command and Option (left)"), draft: swapLeft),
            RuleTemplate(id: "swap-right", title: String(localized: "Swap Command and Option (right)"), draft: swapRight),
            RuleTemplate(id: "fn-left", title: String(localized: "Fn + left click: previous Space"), draft: fnLeft),
            RuleTemplate(id: "fn-right", title: String(localized: "Fn + right click: next Space"), draft: fnRight),
            RuleTemplate(id: "side-mission", title: String(localized: "Fn + side button: Mission Control"), draft: sideButton),
            RuleTemplate(id: "letter-chord", title: String(localized: "Hold F + side button: next Space"), draft: letterChord),
        ]
    }
}
