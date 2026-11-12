import ClavimoCore
import Foundation

/// A ready-made setup: a few well-chosen changes for one kind of person or
/// device, switched on and off as a whole.
struct Preset: Identifiable {
    enum Need: Equatable {
        case trackpad, mouse
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
    static var all: [Preset] { [trackpad, mouse] }

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
        /// A gesture macOS already uses would do both things at once.
        func taken(_ trigger: TrackpadTrigger) -> (Hardware, ConfigDocument) -> String? {
            { hardware, _ in
                SystemTrackpadGestures.conflicts(with: trigger, enabled: hardware.systemGestures).first.map {
                    String(localized: "macOS already uses this gesture: \($0.title). Turn it off in System Settings > Trackpad first.")
                }
            }
        }
        return Preset(
            id: "trackpad",
            title: String(localized: "MacBook trackpad, every day"),
            audience: String(localized: "For anyone with a MacBook or a Magic Trackpad."),
            symbol: "rectangle.and.hand.point.up.left",
            need: .trackpad,
            items: [
                PresetItem(id: "middle", title: String(localized: "Three-finger tap: middle click"),
                           detail: String(localized: "Opens a link in a new tab, or closes a tab when you tap its title."),
                           unavailable: taken(.gesture(.tap(fingers: 3)))) { _ in
                    [gesture(.gesture(.tap(fingers: 3)), .middleClick, name: String(localized: "Three-finger tap: middle click"))]
                },
                PresetItem(id: "swipeVolume", title: String(localized: "Four fingers up or down: volume"),
                           detail: String(localized: "Each swipe changes the volume by one step."),
                           unavailable: { hardware, document in
                               taken(.gesture(.swipe(fingers: 4, .up)))(hardware, document).map {
                                   $0 + " " + String(localized: "Set Mission Control and App Exposé to three fingers or off, or use the knob below.")
                               }
                           }) { _ in
                    [
                        gesture(.gesture(.swipe(fingers: 4, .up)), .media, name: String(localized: "Four fingers up: louder")) {
                            $0.mediaKey = .volumeUp
                        },
                        gesture(.gesture(.swipe(fingers: 4, .down)), .media, name: String(localized: "Four fingers down: quieter")) {
                            $0.mediaKey = .volumeDown
                        },
                    ]
                },
                PresetItem(id: "volume", title: String(localized: "Turn two fingers on the right half: volume"),
                           detail: String(localized: "Clockwise is louder, counterclockwise quieter, like a knob. Scrolling works as before."),
                           defaultOn: { hardware in
                               // The knob stands in when macOS keeps four-finger swipes.
                               !SystemTrackpadGestures.conflicts(with: .gesture(.swipe(fingers: 4, .up)), enabled: hardware.systemGestures).isEmpty
                           }) { _ in
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
                PresetItem(id: "play", title: String(localized: "Four-finger tap: play or pause"),
                           detail: String(localized: "Music and videos, without looking for the key. macOS does not use this tap."),
                           unavailable: taken(.gesture(.tap(fingers: 4)))) { _ in
                    [gesture(.gesture(.tap(fingers: 4)), .media, name: String(localized: "Four-finger tap: play or pause")) {
                        $0.mediaKey = .playPause
                    }]
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
}
