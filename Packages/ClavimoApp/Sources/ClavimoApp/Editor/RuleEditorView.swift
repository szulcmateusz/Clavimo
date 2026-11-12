import AppKit
import ClavimoCore
import ClavimoQuartz
import SwiftUI

struct RuleEditorView: View {
    @Bindable var model: AgentController
    @State var draft: RuleDraft
    let isNew: Bool
    /// Returns an error message, or nil when the rule was saved.
    let save: (RuleDraft) -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var errorMessage: String?
    @State private var devices = HIDDeviceCatalog.connectedDevices()

    var body: some View {
        VStack(spacing: 0) {
            preview
            Form {
                Section {
                    Picker("Rule type", selection: $draft.kind) {
                        // Scroll settings have their own panes.
                        ForEach(RuleDraft.Kind.allCases.filter { !$0.isSetting || draft.kind == $0 }) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $draft.name, prompt: Text(draft.suggestedName))
                }
                triggerSection
                if draft.kind.hasAction {
                    ActionSection(draft: $draft, model: model)
                }
                conditionsSection
                Section {
                    Toggle("Enabled", isOn: $draft.enabled)
                    Stepper("Priority: \(draft.priority)", value: $draft.priority, in: 1...1000, step: 10)
                } footer: {
                    Text("Priority decides between mouse chords with the same trigger. Key rules for the same key need different conditions; the most specific one wins.").formFooterStyle()
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let message = errorMessage ?? draft.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") {
                    if let error = save(draft) { errorMessage = error } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage != nil)
            }
            .padding(12)
        }
        .frame(width: 600, height: 680)
    }

    /// Live summary of the rule being edited, in keycaps and in words.
    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RuleTokensView(tokens: draft.tokens)
            Text(draft.sentence)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(String(localized: "Preview: \(draft.sentence)"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(Brand.violet.opacity(0.08))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: draft)
    }

    @ViewBuilder
    private var triggerSection: some View {
        switch draft.kind {
        case .swapKeys:
            Section {
                KeyField(title: String(localized: "First key"), code: $draft.firstKey, model: model)
                KeyField(title: String(localized: "Second key"), code: $draft.secondKey, model: model)
            } header: {
                Text("Swap")
            } footer: {
                Text("Both directions are created: pressing either key produces the other, including in shortcuts. Left and right modifiers are separate keys.").formFooterStyle()
            }
        case .remapKey:
            Section("Remap") {
                KeyField(title: String(localized: "When I press"), code: $draft.firstKey, model: model)
                KeyField(title: String(localized: "Send"), code: $draft.secondKey, model: model)
            }
        case .modifierClick:
            Section {
                HStack {
                    Text("Hold")
                    Spacer()
                    ForEach(RuleDraft.Modifier.allCases) { modifier in
                        Toggle(modifier.symbol, isOn: Binding(
                            get: { draft.modifiers.contains(modifier) },
                            set: { if $0 { draft.modifiers.insert(modifier) } else { draft.modifiers.remove(modifier) } }
                        ))
                        .toggleStyle(.button)
                        .accessibilityLabel(modifier.rawValue)
                    }
                }
                ButtonPicker(button: $draft.button, allowsPrimary: true)
            } header: {
                Text("When")
            } footer: {
                if draft.button <= 2 {
                    Text("Ordinary clicks are never affected: only clicks made while exactly these modifiers are held are replaced by the action.").formFooterStyle()
                } else if draft.modifiers.isEmpty {
                    Text("With no modifier, the button itself runs the action. Hold it and move to choose in a compass.").formFooterStyle()
                } else {
                    Text("The exact set of held modifiers must match.").formFooterStyle()
                }
            }
        case .keyClick:
            Section {
                KeyField(title: String(localized: "Hold key"), code: $draft.firstKey, model: model)
                ButtonPicker(button: $draft.button, allowsPrimary: false)
                Picker("While waiting", selection: $draft.policy) {
                    ForEach(RuleDraft.Policy.allCases) { Text($0.title).tag($0) }
                }
                if draft.policy == .boundedWindow {
                    Stepper("Window: \(draft.windowMilliseconds) ms", value: $draft.windowMilliseconds,
                            in: LeaderPolicy.allowedWindow, step: 10)
                }
            } header: {
                Text("When")
            } footer: {
                Text(draft.policy.explanation + " " + String(localized: "Letter-key chords can delay that letter while typing.")).formFooterStyle()
            }
        case .trackpadGesture:
            Section {
                Picker(String(localized: "Gesture"), selection: $draft.gesture) {
                    ForEach(RuleDraft.Gesture.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.gesture) { clampFingers() }
                if draft.gesture != .tipTap, draft.gesture != .rotate {
                    FingerPicker(fingers: $draft.fingers, choices: draft.gesture.fingerChoices)
                }
                if draft.gesture == .rotate {
                    Picker(String(localized: "Turn"), selection: $draft.rotation) {
                        ForEach(GestureEvent.Rotation.allCases, id: \.self) { Text(GestureNames.rotation($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if draft.gesture == .swipe {
                    Picker(String(localized: "Direction"), selection: $draft.direction) {
                        ForEach(GestureEvent.Direction.allCases, id: \.self) { Text(GestureNames.direction($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if draft.gesture == .tipTap {
                    Picker(String(localized: "Tapping finger"), selection: $draft.side) {
                        Text(String(localized: "Left of the resting finger")).tag(GestureEvent.Side.left)
                        Text(String(localized: "Right of the resting finger")).tag(GestureEvent.Side.right)
                    }
                }
                Picker(String(localized: "Where on the trackpad"), selection: $draft.zone) {
                    ForEach([TrackpadZone?.none] + TrackpadZone.allCases.map(Optional.some), id: \.self) { zone in
                        Text(GestureNames.zoneName(zone)).tag(zone)
                    }
                }
                ModifierToggles(title: String(localized: "While holding"), selection: $draft.trackpadModifiers)
            } header: {
                Text("When")
            } footer: {
                trackpadFooter(draft.gesture == .rotate
                    ? String(localized: "Turn two fingers like a knob: every 15 degrees run the action once more, so it works well for volume or brightness. To keep it from happening by accident, choose a corner of the trackpad or a key to hold, such as fn.")
                    : String(localized: "With no modifiers selected, the gesture works only while no modifier is held. Choose a half or a corner of the trackpad to give the same gesture different jobs."))
            }
        case .trackpadClick:
            Section {
                Picker(String(localized: "Click"), selection: $draft.clickPlace) {
                    ForEach(RuleDraft.ClickPlace.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.clickPlace) { clampFingers() }
                if draft.clickPlace == .fingers {
                    FingerPicker(fingers: $draft.fingers, choices: TrackpadTrigger.clickFingers)
                } else {
                    Picker(String(localized: "Corner"), selection: $draft.corner) {
                        ForEach(TrackpadCorner.allCases, id: \.self) { Text(GestureNames.name($0)).tag($0) }
                    }
                }
                ModifierToggles(title: String(localized: "While holding"), selection: $draft.trackpadModifiers)
            } header: {
                Text("When")
            } footer: {
                trackpadFooter(draft.clickPlace == .corner
                    ? String(localized: "The click is replaced by the action. With tap to click, a one-finger tap in the corner counts too.")
                    : String(localized: "The click is replaced by the action. Press the trackpad with exactly this many fingers."))
            }
        case .wheel, .trackpadScroll:
            Section {
                Text(String(localized: "Scroll settings are edited in Mouse & Scrolling and Trackpad."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func clampFingers() {
        let choices = draft.kind == .trackpadClick ? TrackpadTrigger.clickFingers : draft.gesture.fingerChoices
        draft.fingers = min(max(draft.fingers, choices.lowerBound), choices.upperBound)
    }

    /// The footer of a trackpad section, with any macOS gesture the rule
    /// would overlap with.
    private func trackpadFooter(_ text: String) -> some View {
        let conflicts = SystemTrackpadGestures.conflicts(with: draft.trackpadTrigger)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text(text).formFooterStyle()
            if !conflicts.isEmpty {
                Label(String(localized: "macOS also uses this movement: \(conflicts.map(\.title).formatted(.list(type: .and))). Holding a key does not stop it, so both actions happen until you turn it off in Trackpad settings."),
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Open Trackpad Settings")) { SystemSettingsLink.open(.trackpad) }
            }
        }
    }

    @ViewBuilder
    private var conditionsSection: some View {
        Section {
            if draft.kind == .swapKeys || draft.kind == .remapKey || draft.kind == .modifierClick {
                DisclosureGroup(draft.devices.isEmpty ? String(localized: "Devices (all)") : String(localized: "Devices (\(draft.devices.count))")) {
                    ForEach(devices.filter { draft.kind == .modifierClick ? $0.isPointer : $0.isKeyboard }) { device in
                        Toggle(isOn: Binding(
                            get: { draft.devices.contains(device.id.description) },
                            set: { on in
                                if on { draft.devices.append(device.id.description) } else { draft.devices.removeAll { $0 == device.id.description } }
                            }
                        )) {
                            Text("\(device.name)  \(device.id.description)")
                        }
                    }
                    ForEach(draft.devices.filter { id in !devices.contains { $0.id.description == id } }, id: \.self) { id in
                        Toggle("Disconnected device \(id)", isOn: Binding(get: { true }, set: { if !$0 { draft.devices.removeAll { $0 == id } } }))
                    }
                    Text("Experimental: the rule applies only when Clavimo can tell which device sent the input.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            AppListEditor(title: String(localized: "Only in apps"), apps: $draft.onlyApps, limit: draft.kind.isSetting ? 1 : nil)
            if !draft.kind.isSetting {
                AppListEditor(title: String(localized: "Not in apps"), apps: $draft.exceptApps, limit: nil)
            }
        } header: {
            Text("Conditions")
        } footer: {
            Text("Leave everything empty to apply the rule everywhere.").formFooterStyle()
        }
    }
}

// MARK: - Actions

/// What a rule does: the action and its details.
private struct ActionSection: View {
    @Binding var draft: RuleDraft
    let model: AgentController

    var body: some View {
        Section {
            ActionFields(draft: $draft, model: model)
        } header: {
            Text("Then")
        } footer: {
            if draft.action.isSimple {
                Text("Uses the macOS Mission Control keyboard shortcuts (Control + Arrow keys). They must be enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.")
                    .formFooterStyle()
            } else if draft.action == .media {
                Text(String(localized: "Brightness keys may not work with external displays.")).formFooterStyle()
            }
        }
    }
}

/// The action picker and its details, for use inside a form section.
struct ActionFields: View {
    @Binding var draft: RuleDraft
    let model: AgentController
    /// A compass a slot of that compass should not open again.
    var excludedCompass: String?

    var body: some View {
        Group {
            Picker("Action", selection: $draft.action) {
                Section(String(localized: "Spaces and windows")) {
                    ForEach([RuleDraft.Action.nextWorkspace, .previousWorkspace, .missionControl, .applicationWindows]) { Text($0.title).tag($0) }
                }
                Section(String(localized: "Mouse")) {
                    ForEach([RuleDraft.Action.middleClick, .backClick, .forwardClick]) { Text($0.title).tag($0) }
                }
                Section(String(localized: "Other")) {
                    ForEach([RuleDraft.Action.shortcut, .launchApp, .media, .menuItem, .openCompass]) { Text($0.title).tag($0) }
                }
            }
            switch draft.action {
            case .shortcut:
                KeyField(title: String(localized: "Key"), code: $draft.shortcutKey, model: model)
                ModifierToggles(title: String(localized: "With"), selection: $draft.shortcutModifiers)
            case .launchApp:
                AppPicker(bundleID: $draft.appBundleID)
            case .media:
                Picker(String(localized: "Key"), selection: $draft.mediaKey) {
                    ForEach(MediaKey.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
                }
            case .openCompass:
                CompassPicker(compassID: $draft.compassID, model: model, excluding: excludedCompass)
            case .menuItem:
                MenuItemField(path: $draft.menuPath)
            default:
                EmptyView()
            }
        }
    }
}

/// Toggle buttons for the five generic modifiers.
struct ModifierToggles: View {
    let title: String
    @Binding var selection: Set<RuleDraft.Modifier>
    var choices: [RuleDraft.Modifier] = RuleDraft.Modifier.allCases

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ForEach(choices) { modifier in
                Toggle(modifier.symbol, isOn: Binding(
                    get: { selection.contains(modifier) },
                    set: { if $0 { selection.insert(modifier) } else { selection.remove(modifier) } }
                ))
                .toggleStyle(.button)
                .accessibilityLabel(modifier.localizedName)
            }
        }
    }
}

/// Number of fingers, shown as a segmented control.
struct FingerPicker: View {
    @Binding var fingers: Int
    let choices: ClosedRange<Int>

    var body: some View {
        Picker(String(localized: "Fingers"), selection: $fingers) {
            ForEach(Array(choices), id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Chooses an app by bundle identifier: from running apps or a file panel.
struct AppPicker: View {
    @Binding var bundleID: String

    var body: some View {
        LabeledContent(String(localized: "App")) {
            HStack {
                if !bundleID.isEmpty {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                    }
                    Text(AppNames.name(bundleID))
                }
                Menu(bundleID.isEmpty ? String(localized: "Choose...") : String(localized: "Change...")) {
                    ForEach(runningApps, id: \.id) { app in
                        Button(app.name) { bundleID = app.id }
                    }
                    Divider()
                    Button(String(localized: "Other App...")) { chooseFromFinder() }
                }
                .fixedSize()
            }
        }
    }

    private var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        bundleID = id
    }
}

// MARK: - Key field with recording

struct KeyField: View {
    let title: String
    @Binding var code: UInt16
    let model: AgentController
    @State private var recorder = KeyRecorder()

    var body: some View {
        LabeledContent(title) {
            HStack {
                Menu(recorder.isRecording ? "Press a key..." : KeyNames.name(for: code)) {
                    Section("Modifiers") { keyButtons(KeyNames.modifierKeys) }
                    Section("Common") { keyButtons(KeyNames.commonKeys) }
                    Menu("Letters and digits") { keyButtons(KeyNames.letterAndDigitKeys) }
                    Menu("Function keys") { keyButtons(KeyNames.functionKeys) }
                    Menu(String(localized: "Japanese keyboard")) { keyButtons(KeyNames.japaneseKeys) }
                }
                .frame(minWidth: 170)
                Button(recorder.isRecording ? "Cancel" : "Record") {
                    if recorder.isRecording {
                        recorder.stop()
                        model.setRecording(false)
                    } else {
                        model.setRecording(true)
                        recorder.start { recorded in
                            // While Caps Lock rules run, Caps Lock arrives as F18.
                            let capsLockMapped = !model.capsLockStatus.mappedKeyboards.isEmpty
                            code = recorded == KeyCode.capsLockProxy.rawValue && capsLockMapped ? KeyCode.capsLock.rawValue : recorded
                            model.setRecording(false)
                        }
                    }
                }
                .help("Press the physical key to use. Remapping pauses while recording.")
            }
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.stop()
                model.setRecording(false)
            }
        }
    }

    private func keyButtons(_ codes: [UInt16]) -> some View {
        ForEach(codes, id: \.self) { value in
            Button(KeyNames.name(for: value)) { code = value }
        }
    }
}

/// Captures one key press inside Clavimo's own window only. It never
/// observes other apps and stops after the first key.
@MainActor
@Observable
final class KeyRecorder {
    private(set) var isRecording = false
    private var monitor: Any?
    private var completion: ((UInt16) -> Void)?

    func start(_ completion: @escaping (UInt16) -> Void) {
        stop()
        isRecording = true
        self.completion = completion
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let isFlagsChanged = event.type == .flagsChanged
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            let consumed = MainActor.assumeIsolated {
                self?.record(keyCode: keyCode, isFlagsChanged: isFlagsChanged, flags: flags) ?? false
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was used (and must not reach the UI).
    private func record(keyCode: UInt16, isFlagsChanged: Bool, flags: UInt) -> Bool {
        guard isRecording else { return false }
        if isFlagsChanged {
            // Record modifiers on press, not on release.
            if let modifier = KeyCode(keyCode).modifierKey {
                guard flags & Self.deviceMask(for: modifier) != 0 else { return true }
            } else if keyCode != KeyCode.capsLock.rawValue {
                return true
            }
        }
        let completion = completion
        stop()
        completion?(keyCode)
        return true
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        completion = nil
        isRecording = false
    }

    private static func deviceMask(for modifier: ModifierKey) -> UInt {
        switch modifier {
        case .leftControl: 0x0001
        case .leftShift: 0x0002
        case .rightShift: 0x0004
        case .leftCommand: 0x0008
        case .rightCommand: 0x0010
        case .leftOption: 0x0020
        case .rightOption: 0x0040
        case .rightControl: 0x2000
        }
    }
}

// MARK: - Small editors

struct ButtonPicker: View {
    @Binding var button: Int
    let allowsPrimary: Bool

    var body: some View {
        Picker("Mouse button", selection: $button) {
            ForEach((allowsPrimary ? 1 : 3)...8, id: \.self) { Text(KeyNames.buttonName($0)).tag($0) }
        }
    }
}

struct AppListEditor: View {
    let title: String
    @Binding var apps: [String]
    let limit: Int?
    @State private var newApp = ""

    var body: some View {
        DisclosureGroup(apps.isEmpty ? String(localized: "\(title) (none)") : String(localized: "\(title) (\(apps.count))")) {
            ForEach(apps, id: \.self) { app in
                HStack {
                    Text(app).font(.callout.monospaced())
                    Spacer()
                    Button("Remove") { apps.removeAll { $0 == app } }
                }
            }
            if limit.map({ apps.count < $0 }) ?? true {
                HStack {
                    TextField("Bundle ID, e.g. com.apple.Safari", text: $newApp)
                    Menu("Running Apps") {
                        ForEach(runningApps, id: \.id) { app in
                            Button(app.name) { add(app.id) }
                        }
                    }
                    .fixedSize()
                    Button("Add") { add(newApp) }.disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !apps.contains(trimmed) else { return }
        apps.append(trimmed)
        newApp = ""
    }
}
