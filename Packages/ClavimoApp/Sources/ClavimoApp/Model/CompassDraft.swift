import ClavimoCore
import Foundation

/// One direction of a compass page, as the editor shows it.
struct CompassSlotDraft: Equatable {
    var name = ""
    /// On an app page: hides the default page's action in this direction.
    var hidden = false
    var action = ActionChoice()
    /// An action the form cannot show, kept exactly as written.
    var raw: JSONValue?

    init(action: ActionChoice = ActionChoice(), name: String = "") {
        self.action = action
        self.name = name
    }

    init(_ slot: ConfigDocument.Compass.Slot) {
        name = slot.name ?? ""
        if slot.action["kind"]?.string == "none" {
            hidden = true
            return
        }
        var draft = RuleDraft()
        if draft.readAction(slot.action) {
            action = ActionChoice(draft)
        } else {
            raw = slot.action
        }
    }

    var actionJSON: JSONValue {
        if hidden { return .object(["kind": .string("none")]) }
        return raw ?? action.ruleDraft.actionJSON
    }

    func slot(_ direction: CompassDirection) -> ConfigDocument.Compass.Slot {
        ConfigDocument.Compass.Slot(direction: direction.rawValue, name: name.isEmpty ? nil : name, action: actionJSON)
    }

    var actionTitle: String {
        if hidden { return String(localized: "Hidden here") }
        if let raw { return String(localized: "Custom action (\(raw["kind"]?.string ?? "?"))") }
        return action.ruleDraft.actionTitle
    }

    var title: String { name.isEmpty ? actionTitle : name }

    var symbol: String {
        if hidden { return "eye.slash" }
        if raw != nil { return "curlybraces" }
        let draft = action.ruleDraft
        return draft.action == .media ? draft.mediaKey.symbol : draft.action.symbol
    }

    var validationMessage: String? {
        guard !hidden, raw == nil else { return nil }
        return action.ruleDraft.actionValidationMessage
    }
}

/// The editable form of a compass: a default page and pages for apps.
struct CompassDraft: Equatable, Identifiable {
    var id: String
    var name: String
    var slots: [CompassDirection: CompassSlotDraft] = [:]
    /// App pages in the order they were added.
    var appOrder: [String] = []
    var apps: [String: [CompassDirection: CompassSlotDraft]] = [:]
    var hintDelayMilliseconds = CompassDefinition.defaultHintDelay
    var deadZone = CompassDefinition.defaultDeadZone
    var returnPointer = true

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ compass: ConfigDocument.Compass) {
        id = compass.id
        name = compass.name
        slots = Self.page(compass.slots)
        for app in compass.apps ?? [] where apps[app.bundleId] == nil {
            appOrder.append(app.bundleId)
            apps[app.bundleId] = Self.page(app.slots)
        }
        hintDelayMilliseconds = compass.hintDelayMs ?? CompassDefinition.defaultHintDelay
        deadZone = compass.deadZone ?? CompassDefinition.defaultDeadZone
        returnPointer = compass.returnPointer ?? true
    }

    private static func page(_ slots: [ConfigDocument.Compass.Slot]) -> [CompassDirection: CompassSlotDraft] {
        var result: [CompassDirection: CompassSlotDraft] = [:]
        for slot in slots {
            guard let direction = CompassDirection(rawValue: slot.direction), result[direction] == nil else { continue }
            result[direction] = CompassSlotDraft(slot)
        }
        return result
    }

    var document: ConfigDocument.Compass {
        func page(_ slots: [CompassDirection: CompassSlotDraft]) -> [ConfigDocument.Compass.Slot] {
            CompassDirection.clockwise.compactMap { direction in slots[direction].map { $0.slot(direction) } }
        }
        let pages = appOrder.compactMap { bundleID in
            apps[bundleID].map { ConfigDocument.Compass.AppPage(bundleId: bundleID, slots: page($0)) }
        }
        return ConfigDocument.Compass(
            id: id, name: name, slots: page(slots), apps: pages.isEmpty ? nil : pages,
            hintDelayMs: hintDelayMilliseconds == CompassDefinition.defaultHintDelay ? nil : hintDelayMilliseconds,
            deadZone: deadZone == CompassDefinition.defaultDeadZone ? nil : deadZone,
            returnPointer: returnPointer ? nil : false
        )
    }

    /// The slots of a page: nil for the default page.
    func page(_ app: String?) -> [CompassDirection: CompassSlotDraft] {
        guard let app else { return slots }
        return apps[app] ?? [:]
    }

    mutating func setSlot(_ slot: CompassSlotDraft?, at direction: CompassDirection, page app: String?) {
        if let app {
            apps[app, default: [:]][direction] = slot
            if !appOrder.contains(app) { appOrder.append(app) }
        } else {
            slots[direction] = slot
        }
    }

    mutating func swap(_ first: CompassDirection, _ second: CompassDirection, page app: String?) {
        let a = page(app)[first]
        let b = page(app)[second]
        setSlot(b, at: first, page: app)
        setSlot(a, at: second, page: app)
    }

    mutating func addPage(_ app: String) {
        guard apps[app] == nil else { return }
        apps[app] = [:]
        appOrder.append(app)
    }

    mutating func removePage(_ app: String) {
        apps[app] = nil
        appOrder.removeAll { $0 == app }
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Name the compass.") }
        let allSlots = Array(slots.values) + apps.values.flatMap(\.values)
        return allSlots.lazy.compactMap(\.validationMessage).first
    }
}

/// Ready-made pages to start from. Each one fills the default page or adds
/// pages for apps; nothing in them is specific to anyone's setup.
struct CompassTemplate: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    /// Bundle IDs of app pages; empty for the default page.
    let apps: [String]
    let slots: [CompassDirection: CompassSlotDraft]

    func apply(to draft: inout CompassDraft) {
        if apps.isEmpty {
            for (direction, slot) in slots { draft.slots[direction] = slot }
        } else {
            for app in apps {
                draft.addPage(app)
                for (direction, slot) in slots { draft.apps[app]?[direction] = slot }
            }
        }
    }
}

enum CompassTemplates {
    private static func simple(_ action: RuleDraft.Action) -> CompassSlotDraft {
        var choice = ActionChoice()
        choice.action = action
        return CompassSlotDraft(action: choice)
    }

    private static func media(_ key: MediaKey) -> CompassSlotDraft {
        var choice = ActionChoice()
        choice.action = .media
        choice.mediaKey = key
        return CompassSlotDraft(action: choice)
    }

    private static func shortcut(_ name: String, _ key: UInt16, _ modifiers: Set<RuleDraft.Modifier>) -> CompassSlotDraft {
        var choice = ActionChoice()
        choice.action = .shortcut
        choice.shortcutKey = key
        choice.shortcutModifiers = modifiers
        return CompassSlotDraft(action: choice, name: name)
    }

    static var all: [CompassTemplate] { [everyday, media, browser, codeEditor, meetings] }

    static var everyday: CompassTemplate {
        CompassTemplate(
            id: "everyday", title: String(localized: "Spaces and windows"),
            summary: String(localized: "Mission Control, Spaces, app windows, a screenshot and the Finder."),
            symbol: "rectangle.3.group", apps: [],
            slots: [
                .up: simple(.missionControl),
                .down: simple(.applicationWindows),
                .left: simple(.previousWorkspace),
                .right: simple(.nextWorkspace),
                .upLeft: media(.playPause),
                .upRight: media(.mute),
                .downLeft: shortcut(String(localized: "Screenshot of an area"), 0x15, [.shift, .command]),
                .downRight: {
                    var choice = ActionChoice()
                    choice.action = .launchApp
                    choice.appBundleID = "com.apple.finder"
                    return CompassSlotDraft(action: choice)
                }(),
            ]
        )
    }

    static var media: CompassTemplate {
        CompassTemplate(
            id: "media", title: String(localized: "Music and volume"),
            summary: String(localized: "Volume, tracks and brightness, without the function keys."),
            symbol: "music.note", apps: [],
            slots: [
                .up: media(.volumeUp), .down: media(.volumeDown),
                .left: media(.previousTrack), .right: media(.nextTrack),
                .upLeft: media(.mute), .upRight: media(.playPause),
                .downLeft: media(.brightnessDown), .downRight: media(.brightnessUp),
            ]
        )
    }

    static var browser: CompassTemplate {
        CompassTemplate(
            id: "browser", title: String(localized: "Browsers"),
            summary: String(localized: "Tabs, back and forward in Safari, Chrome, Firefox, Edge, Arc and Brave."),
            symbol: "globe",
            apps: ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac",
                   "company.thebrowser.Browser", "com.brave.Browser"],
            slots: [
                .up: shortcut(String(localized: "New tab"), 0x11, [.command]),
                .down: shortcut(String(localized: "Close tab"), 0x0D, [.command]),
                .left: shortcut(String(localized: "Back"), 0x21, [.command]),
                .right: shortcut(String(localized: "Forward"), 0x1E, [.command]),
                .upLeft: shortcut(String(localized: "Reopen closed tab"), 0x11, [.shift, .command]),
                .upRight: shortcut(String(localized: "Reload"), 0x0F, [.command]),
                .downLeft: shortcut(String(localized: "Previous tab"), 0x30, [.control, .shift]),
                .downRight: shortcut(String(localized: "Next tab"), 0x30, [.control]),
            ]
        )
    }

    static var codeEditor: CompassTemplate {
        CompassTemplate(
            id: "code", title: String(localized: "Visual Studio Code and Cursor"),
            summary: String(localized: "Command palette, quick open, terminal, sidebar and navigation."),
            symbol: "chevron.left.forwardslash.chevron.right",
            apps: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"],
            slots: [
                .up: shortcut(String(localized: "Command palette"), 0x23, [.shift, .command]),
                .down: shortcut(String(localized: "Terminal"), 0x32, [.control]),
                .left: shortcut(String(localized: "Go back"), 0x1B, [.control]),
                .right: shortcut(String(localized: "Go forward"), 0x1B, [.control, .shift]),
                .upLeft: shortcut(String(localized: "Quick open"), 0x23, [.command]),
                .upRight: shortcut(String(localized: "Search in files"), 0x03, [.shift, .command]),
                .downLeft: shortcut(String(localized: "Sidebar"), 0x0B, [.command]),
                .downRight: shortcut(String(localized: "Format document"), 0x03, [.shift, .option]),
            ]
        )
    }

    static var meetings: CompassTemplate {
        CompassTemplate(
            id: "meetings", title: String(localized: "Zoom meetings"),
            summary: String(localized: "Microphone, camera, screen sharing and leaving the meeting."),
            symbol: "video", apps: ["us.zoom.xos"],
            slots: [
                .up: shortcut(String(localized: "Microphone on or off"), 0x00, [.shift, .command]),
                .down: shortcut(String(localized: "Leave meeting"), 0x0D, [.command]),
                .left: shortcut(String(localized: "Camera on or off"), 0x09, [.shift, .command]),
                .right: shortcut(String(localized: "Share screen"), 0x01, [.shift, .command]),
            ]
        )
    }
}
