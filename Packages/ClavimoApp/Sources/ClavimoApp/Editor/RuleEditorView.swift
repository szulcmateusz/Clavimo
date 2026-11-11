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
                        // Mouse wheel settings have their own pane.
                        ForEach(RuleDraft.Kind.allCases.filter { $0 != .wheel || draft.kind == .wheel }) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $draft.name, prompt: Text(draft.suggestedName))
                }
                triggerSection
                if draft.kind == .modifierClick || draft.kind == .keyClick {
                    Section("Then") {
                        Picker("Action", selection: $draft.action) {
                            ForEach(RuleDraft.Action.allCases) { Text($0.title).tag($0) }
                        }
                        Text("Uses the macOS Mission Control keyboard shortcuts (Control + Arrow keys). They must be enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
        case .wheel:
            Section {
                Text(String(localized: "Mouse wheel settings are edited in Mouse & Scrolling."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var conditionsSection: some View {
        Section {
            if draft.kind != .wheel && draft.kind != .keyClick {
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
            AppListEditor(title: String(localized: "Only in apps"), apps: $draft.onlyApps, limit: draft.kind == .wheel ? 1 : nil)
            if draft.kind != .wheel {
                AppListEditor(title: String(localized: "Not in apps"), apps: $draft.exceptApps, limit: nil)
            }
        } header: {
            Text("Conditions")
        } footer: {
            Text("Leave everything empty to apply the rule everywhere.").formFooterStyle()
        }
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
                }
                .frame(minWidth: 170)
                Button(recorder.isRecording ? "Cancel" : "Record") {
                    if recorder.isRecording {
                        recorder.stop()
                        model.setRecording(false)
                    } else {
                        model.setRecording(true)
                        recorder.start { recorded in
                            code = recorded
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
