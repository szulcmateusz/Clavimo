import ClavimoCore
import Foundation

/// A ready-made setup: a few well-chosen changes for one kind of person or
/// device, switched on and off as a whole.
struct Preset: Identifiable {
    enum Need: Equatable {
        case trackpad, mouse, pcKeyboard
    }

    let id: String
    let title: String
    let audience: String
    let symbol: String
    /// The hardware it is for; nil when it suits anyone.
    let need: Need?
    let items: [PresetItem]
    /// A remark for this hardware, e.g. about Logi Options+.
    var note: (Hardware) -> String? = { _ in nil }

    func fits(_ hardware: Hardware) -> Bool {
        switch need {
        case .trackpad: hardware.hasTrackpad
        case .mouse: hardware.hasMouse
        case .pcKeyboard: !hardware.pcKeyboards.isEmpty
        case nil: false
        }
    }
}

/// One change a preset can make, with its own switch.
struct PresetItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    var defaultOn: (Hardware) -> Bool = { _ in true }
    /// Why the item cannot be used now, or nil.
    var unavailable: (Hardware, ConfigDocument) -> String? = { _, _ in nil }
    let changes: (PresetContext) -> [PresetChange]
}

struct PresetContext {
    let hardware: Hardware
    let profileID: String
}

enum PresetChange {
    case rule(RuleDraft)
    /// A keyboard rule; `id` keeps a fixed id, such as the Caps Lock rule's.
    case keyboard(KeyboardRuleDraft, id: String?)
    case setting(RuleDraft)
    case compass(CompassDraft)
}

enum Presets {
    static var all: [Preset] { [trackpad, mouse, windows, developer] }

    /// The presets that suit this hardware first, then the others.
    static func ordered(for hardware: Hardware) -> [Preset] {
        let fitting = all.filter { $0.fits(hardware) }
        return fitting + all.filter { !$0.fits(hardware) }
    }

    // MARK: - Trackpad

    static var trackpad: Preset {
        func gesture(_ trigger: TrackpadTrigger, _ action: RuleDraft.Action, name: String,
                     configure: @escaping (inout RuleDraft) -> Void = { _ in }) -> PresetChange {
            var draft = RuleTemplates.gesture(trigger, action, configure: configure)
            draft.name = name
            return .rule(draft)
        }
        return Preset(
            id: "trackpad",
            title: String(localized: "MacBook trackpad, every day"),
            audience: String(localized: "For anyone with a MacBook or a Magic Trackpad."),
            symbol: "rectangle.and.hand.point.up.left",
            need: .trackpad,
            items: [
                PresetItem(id: "middle", title: String(localized: "Three-finger tap: middle click"),
                           detail: String(localized: "Opens a link in a new tab, or closes a tab when you tap its title.")) { _ in
                    [gesture(.gesture(.tap(fingers: 3)), .middleClick, name: String(localized: "Three-finger tap: middle click"))]
                },
                PresetItem(id: "mission", title: String(localized: "Four-finger tap: Mission Control"),
                           detail: String(localized: "Every open window at a glance.")) { _ in
                    [gesture(.gesture(.tap(fingers: 4)), .missionControl, name: String(localized: "Four-finger tap: Mission Control"))]
                },
                PresetItem(id: "volume", title: String(localized: "Turn two fingers on the right half: volume"),
                           detail: String(localized: "Clockwise is louder, counterclockwise quieter, like a knob. Scrolling works as before.")) { _ in
                    [
                        gesture(.gesture(.rotate(.clockwise)), .media, name: String(localized: "Right half, turn clockwise: louder")) {
                            $0.mediaKey = .volumeUp
                            $0.zone = .right
                        },
                        gesture(.gesture(.rotate(.counterclockwise)), .media, name: String(localized: "Right half, turn counterclockwise: quieter")) {
                            $0.mediaKey = .volumeDown
                            $0.zone = .right
                        },
                    ]
                },
                PresetItem(id: "brightness", title: String(localized: "Turn two fingers on the left half: brightness"),
                           detail: String(localized: "Clockwise is brighter, counterclockwise darker. Brightness keys may not work with external displays."),
                           defaultOn: { _ in false }) { _ in
                    [
                        gesture(.gesture(.rotate(.clockwise)), .media, name: String(localized: "Left half, turn clockwise: brighter")) {
                            $0.mediaKey = .brightnessUp
                            $0.zone = .left
                        },
                        gesture(.gesture(.rotate(.counterclockwise)), .media, name: String(localized: "Left half, turn counterclockwise: darker")) {
                            $0.mediaKey = .brightnessDown
                            $0.zone = .left
                        },
                    ]
                },
                PresetItem(id: "play", title: String(localized: "Five-finger tap: play or pause"),
                           detail: String(localized: "Music and videos, without looking for the key."),
                           defaultOn: { _ in false }) { _ in
                    [gesture(.gesture(.tap(fingers: 5)), .media, name: String(localized: "Five-finger tap: play or pause")) {
                        $0.mediaKey = .playPause
                    }]
                },
            ]
        )
    }

    // MARK: - Mouse

    static var mouse: Preset {
        Preset(
            id: "mouse",
            title: String(localized: "Mouse with side buttons"),
            audience: String(localized: "For any mouse with back and forward buttons, Logitech mice included."),
            symbol: "computermouse",
            need: .mouse,
            items: [
                PresetItem(
                    id: "compass", title: String(localized: "Action compass under ⌘ + back button"),
                    detail: String(localized: "Hold ⌘ and the back button, move towards an action and let go: Spaces, windows, a screenshot, and pages for browsers, code editors and Zoom."),
                    unavailable: { _, document in
                        let opened = (document.compasses ?? []).contains { compass in
                            !compass.id.hasPrefix("preset-") && document.rules.contains { ConfigEditor.opens(compass.id, $0) }
                        }
                        return opened ? String(localized: "You already have a compass that opens with a trigger.") : nil
                    }
                ) { context in
                    var compass = CompassDraft(id: PresetEngine.compassID("mouse", "compass"), name: String(localized: "Mouse"))
                    for template in [CompassTemplates.everyday, CompassTemplates.browser, CompassTemplates.codeEditor, CompassTemplates.meetings] {
                        template.apply(to: &compass)
                    }
                    var trigger = RuleDraft()
                    trigger.kind = .modifierClick
                    trigger.modifiers = [.command]
                    trigger.button = 4
                    trigger.action = .openCompass
                    trigger.compassID = compass.id
                    trigger.profileID = context.profileID
                    trigger.name = String(localized: "⌘ + back button: compass")
                    return [.compass(compass), .rule(trigger)]
                },
                PresetItem(id: "spaces", title: String(localized: "⌥ + side buttons: switch Spaces"),
                           detail: String(localized: "⌥ + back goes to the previous Space, ⌥ + forward to the next one.")) { context in
                    [(4, RuleDraft.Action.previousWorkspace), (5, .nextWorkspace)].map { button, action in
                        var draft = RuleDraft()
                        draft.kind = .modifierClick
                        draft.modifiers = [.option]
                        draft.button = button
                        draft.action = action
                        draft.profileID = context.profileID
                        draft.name = draft.suggestedName
                        return .rule(draft)
                    }
                },
                wheelItem(defaultOn: { !$0.usesLogiOptions }),
            ],
            note: { hardware in
                hardware.usesLogiOptions
                    ? String(localized: "Logi Options+ is running: keep the side buttons on their default actions there, and set the wheel in one app only.")
                    : nil
            }
        )
    }

    /// Discrete wheel scrolling reversed, the way Windows and most PCs work.
    static func wheelItem(defaultOn: @escaping (Hardware) -> Bool) -> PresetItem {
        PresetItem(id: "wheel", title: String(localized: "Mouse wheel like on Windows"),
                   detail: String(localized: "Turning the wheel down scrolls the page down. The trackpad keeps natural scrolling."),
                   defaultOn: defaultOn) { context in
            var draft = RuleDraft()
            draft.kind = .wheel
            draft.vertical = RuleDraft.Axis()
            draft.vertical.reverse = true
            draft.profileID = context.profileID
            draft.name = String(localized: "Mouse wheel like on Windows")
            return [.setting(draft)]
        }
    }

    // MARK: - Windows

    static var windows: Preset {
        func shortcut(_ key: KeyCode, to target: KeyCode, _ modifiers: Set<RuleDraft.Modifier>, name: String, profileID: String) -> PresetChange {
            var draft = KeyboardRuleDraft(kind: .keyOutput)
            draft.key = key.rawValue
            draft.output = OutputDraft.of(.shortcut)
            draft.output.key = target.rawValue
            draft.output.modifiers = modifiers
            draft.profileID = profileID
            draft.name = name
            return .keyboard(draft, id: nil)
        }
        return Preset(
            id: "windows",
            title: String(localized: "Switching from Windows"),
            audience: String(localized: "Keys and scrolling the way a PC works, best with a PC keyboard."),
            symbol: "pc",
            need: .pcKeyboard,
            items: [
                PresetItem(
                    id: "swap", title: String(localized: "Alt and Windows keys swapped on a PC keyboard"),
                    detail: String(localized: "⌘ sits next to the space bar, where Alt was, so ⌘C and ⌘V feel like Ctrl+C and Ctrl+V. Only on PC keyboards; the Mac keyboard stays as it is. Leave it off if your keyboard has a Mac mode."),
                    defaultOn: { _ in false },
                    unavailable: { hardware, _ in
                        hardware.pcKeyboards.isEmpty ? String(localized: "Connect a PC keyboard to use this.") : nil
                    }
                ) { context in
                    let devices = context.hardware.pcKeyboards.map(\.id.description)
                    return [(KeyCode.leftOption, KeyCode.leftCommand), (.rightOption, .rightCommand)].map { first, second in
                        var draft = RuleDraft()
                        draft.kind = .swapKeys
                        draft.firstKey = first.rawValue
                        draft.secondKey = second.rawValue
                        draft.devices = devices
                        draft.profileID = context.profileID
                        draft.name = draft.suggestedName
                        return .rule(draft)
                    }
                },
                PresetItem(id: "homeEnd", title: String(localized: "Home and End go to the start and end of the line"),
                           detail: String(localized: "With Shift they select. Mac keyboards have no Home or End, so nothing changes there.")) { context in
                    [
                        shortcut(KeyCode(0x73), to: .leftArrow, [.command], name: String(localized: "Home: start of the line"), profileID: context.profileID),
                        shortcut(KeyCode(0x77), to: .rightArrow, [.command], name: String(localized: "End: end of the line"), profileID: context.profileID),
                    ]
                },
                PresetItem(id: "printScreen", title: String(localized: "Print Screen takes a screenshot of an area"),
                           detail: String(localized: "On PC keyboards Print Screen arrives as F13; it then works as ⇧⌘4.")) { context in
                    [shortcut(KeyCode(0x69), to: KeyCode(0x15), [.shift, .command],
                              name: String(localized: "Print Screen: screenshot of an area"), profileID: context.profileID)]
                },
                wheelItem(defaultOn: { _ in true }),
            ]
        )
    }

    // MARK: - Developer

    static var developer: Preset {
        func template(_ template: KeyboardTemplates.Template, profileID: String) -> [PresetChange] {
            template.drafts.map { draft in
                var draft = draft
                draft.profileID = profileID
                return .keyboard(draft, id: nil)
            }
        }
        return Preset(
            id: "developer",
            title: String(localized: "For programmers"),
            audience: String(localized: "Faster keyboard work in code editors and the terminal."),
            symbol: "chevron.left.forwardslash.chevron.right",
            need: nil,
            items: [
                PresetItem(
                    id: "caps", title: String(localized: "Caps Lock: Escape when tapped, Hyper when held"),
                    detail: String(localized: "A double tap still turns Caps Lock on. Shortcuts with Hyper (⌃⌥⇧⌘) never clash with apps."),
                    unavailable: { _, document in
                        document.rules.contains { $0.id == KeyboardPane.capsLockRuleID }
                            ? String(localized: "Caps Lock is already set in the Keyboard pane.") : nil
                    }
                ) { context in
                    var draft = KeyboardRuleDraft()
                    draft.kind = .tapHold
                    draft.key = KeyCode.capsLock.rawValue
                    draft.output = .key(KeyCode.escape.rawValue)
                    draft.hold = .modifiers(OutputDraft.hyper)
                    draft.doubleTapEnabled = true
                    draft.doubleTap = .of(.capsLock)
                    draft.profileID = context.profileID
                    draft.name = String(localized: "Caps Lock: \(KeyboardPane.CapsPreset.hyperEscape.title)")
                    return [.keyboard(draft, id: KeyboardPane.capsLockRuleID)]
                },
                PresetItem(id: "arrows", title: String(localized: "Arrows under the right hand"),
                           detail: String(localized: "Hold Space and use H J K L as arrows. It takes a day to get used to."),
                           defaultOn: { _ in false }) { context in
                    template(KeyboardTemplates.navigation, profileID: context.profileID)
                },
                PresetItem(id: "parentheses", title: String(localized: "Parentheses on the Shift keys"),
                           detail: String(localized: "Tap left Shift for ( and right Shift for ). Held, Shift works as usual."),
                           defaultOn: { _ in false }) { context in
                    template(KeyboardTemplates.parentheses, profileID: context.profileID)
                },
                PresetItem(id: "escapeCombo", title: String(localized: "J and K together: Escape"),
                           detail: String(localized: "For Vim users."),
                           defaultOn: { _ in false }) { context in
                    template(KeyboardTemplates.escapeCombo, profileID: context.profileID)
                },
            ]
        )
    }
}
