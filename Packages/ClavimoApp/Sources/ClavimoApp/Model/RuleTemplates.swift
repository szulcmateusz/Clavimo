import ClavimoCore

/// Ready-made starting points for common setups.
struct RuleTemplate: Identifiable {
    let id: String
    let title: String
    let draft: RuleDraft

    init(id: String, title: String, draft: RuleDraft) {
        self.id = id
        self.title = title
        var named = draft
        named.name = title
        self.draft = named
    }
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

    /// Ready-made trackpad rules.
    static var trackpad: [RuleTemplate] {
        func gesture(_ trigger: TrackpadTrigger, _ action: RuleDraft.Action, modifiers: Set<RuleDraft.Modifier> = [],
                     configure: (inout RuleDraft) -> Void = { _ in }) -> RuleDraft {
            var draft = RuleDraft()
            draft.trackpadModifiers = modifiers
            draft.action = action
            switch trigger {
            case let .gesture(.tap(count)): draft.kind = .trackpadGesture; draft.gesture = .tap; draft.fingers = count
            case let .gesture(.tipTap(side)): draft.kind = .trackpadGesture; draft.gesture = .tipTap; draft.side = side
            case let .gesture(.swipe(count, direction)):
                draft.kind = .trackpadGesture; draft.gesture = .swipe; draft.fingers = count; draft.direction = direction
            case let .gesture(.rotate(turn)): draft.kind = .trackpadGesture; draft.gesture = .rotate; draft.rotation = turn
            case let .click(count): draft.kind = .trackpadClick; draft.clickPlace = .fingers; draft.fingers = count
            case let .cornerClick(corner): draft.kind = .trackpadClick; draft.clickPlace = .corner; draft.corner = corner
            }
            configure(&draft)
            return draft
        }
        return [
            RuleTemplate(id: "rotate-volume-up", title: String(localized: "Turn two fingers clockwise: volume up"),
                         draft: gesture(.gesture(.rotate(.clockwise)), .media) { $0.mediaKey = .volumeUp }),
            RuleTemplate(id: "rotate-volume-down", title: String(localized: "Turn two fingers counterclockwise: volume down"),
                         draft: gesture(.gesture(.rotate(.counterclockwise)), .media) { $0.mediaKey = .volumeDown }),
            RuleTemplate(id: "rotate-brightness-up", title: String(localized: "Right half, turn clockwise: brighter"),
                         draft: gesture(.gesture(.rotate(.clockwise)), .media) { $0.mediaKey = .brightnessUp; $0.zone = .right }),
            RuleTemplate(id: "tap3-middle", title: String(localized: "Three-finger tap: middle click"),
                         draft: gesture(.gesture(.tap(fingers: 3)), .middleClick)),
            RuleTemplate(id: "click3-middle", title: String(localized: "Three-finger click: middle click"),
                         draft: gesture(.click(fingers: 3), .middleClick)),
            RuleTemplate(id: "tiptap-newtab", title: String(localized: "Tip tap right: new tab"),
                         draft: gesture(.gesture(.tipTap(.right)), .shortcut) { $0.shortcutKey = 0x11; $0.shortcutModifiers = [.command] }),
            RuleTemplate(id: "fn-swipe-back", title: String(localized: "Fn + three-finger swipe left: back"),
                         draft: gesture(.gesture(.swipe(fingers: 3, .left)), .backClick, modifiers: [.function])),
            RuleTemplate(id: "fn-swipe-forward", title: String(localized: "Fn + three-finger swipe right: forward"),
                         draft: gesture(.gesture(.swipe(fingers: 3, .right)), .forwardClick, modifiers: [.function])),
            RuleTemplate(id: "tap4-mission", title: String(localized: "Four-finger tap: Mission Control"),
                         draft: gesture(.gesture(.tap(fingers: 4)), .missionControl)),
            RuleTemplate(id: "corner-close", title: String(localized: "Top right corner click: close tab"),
                         draft: gesture(.cornerClick(.topRight), .shortcut) { $0.shortcutKey = 0x0D; $0.shortcutModifiers = [.command] }),
            RuleTemplate(id: "fn-volume-up", title: String(localized: "Fn + four-finger swipe up: volume up"),
                         draft: gesture(.gesture(.swipe(fingers: 4, .up)), .media, modifiers: [.function]) { $0.mediaKey = .volumeUp }),
            RuleTemplate(id: "fn-volume-down", title: String(localized: "Fn + four-finger swipe down: volume down"),
                         draft: gesture(.gesture(.swipe(fingers: 4, .down)), .media, modifiers: [.function]) { $0.mediaKey = .volumeDown }),
            RuleTemplate(id: "tap5-play", title: String(localized: "Five-finger tap: play or pause"),
                         draft: gesture(.gesture(.tap(fingers: 5)), .media) { $0.mediaKey = .playPause }),
        ]
    }
}
