import AppKit
import ClavimoCore
import ClavimoQuartz
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case rules, devices, general, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .rules: "Rules"
            case .devices: "Devices"
            case .general: "General"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .rules: "list.bullet.rectangle"
            case .devices: "keyboard"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    @Bindable var model: AppModel
    @Bindable var editor: ConfigEditor
    @State private var pane: Pane? = .rules

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch pane ?? .rules {
            case .rules: RulesPane(model: model, editor: editor)
            case .devices: DevicesPane()
            case .general: GeneralPane(model: model, editor: editor)
            case .about: AboutPane()
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

// MARK: - Status

struct StatusBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.status == .active ? "checkmark.circle.fill" : "pause.circle.fill")
                .foregroundStyle(model.status == .active ? .green : .orange)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title).font(.headline)
                Text(statusDetail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Remapping", isOn: Binding(get: { model.userEnabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .disabled(model.status == .safeMode)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var statusDetail: String {
        switch model.status {
        case .active: "Your rules are applied to keyboard and mouse input."
        case .pausedByUser: "Input passes through unchanged until you turn remapping on."
        case .pausedInactiveSession: "Another macOS account is in use. Remapping resumes when you return."
        case .needsPermission: "Grant Accessibility and Input Monitoring in General."
        case .configurationError: model.loadError ?? "The configuration file could not be loaded."
        case .safeMode: "macOS disabled the event tap repeatedly. Resume from the menu bar after checking for conflicts."
        }
    }
}

// MARK: - Rules

struct RulesPane: View {
    @Bindable var model: AppModel
    @Bindable var editor: ConfigEditor
    @State private var editing: EditingRule?
    @State private var errorMessage: String?

    struct EditingRule: Identifiable {
        let id: String?
        var draft: RuleDraft
        var identity: String { id ?? "new" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusBanner(model: model)
            if let warning = model.otherRemapper {
                Label("\(warning) is running. Running two remappers at once can apply rules twice.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let error = editor.lastError ?? errorMessage {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
            }
            if editor.rows.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "keyboard.badge.ellipsis")
                } description: {
                    Text("Create a rule to swap keys, combine a key with a mouse button, or reverse the mouse wheel.")
                } actions: {
                    Button("New Rule") { editing = EditingRule(id: nil, draft: RuleDraft()) }
                }
            } else {
                List {
                    ForEach(editor.rows) { row in
                        RuleRow(row: row, issue: model.unsupported.first { $0.ruleID == row.id }, isActive: model.status == .active) { enabled in
                            errorMessage = editor.setEnabled(enabled, id: row.id)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { edit(row) }
                        .contextMenu {
                            Button("Edit...") { edit(row) }.disabled(row.draft == nil)
                            Button("Duplicate") { duplicate(row) }.disabled(row.draft == nil)
                            Divider()
                            Button("Delete", role: .destructive) { errorMessage = editor.delete(id: row.id) }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                Button {
                    editing = EditingRule(id: nil, draft: RuleDraft())
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
                Spacer()
                Text("Double-click a rule to edit it. Right-click for more options.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .navigationTitle("Rules")
        .sheet(item: Binding(get: { editing.map { IdentifiedEditing(value: $0) } }, set: { editing = $0?.value })) { item in
            RuleEditorView(model: model, draft: item.value.draft, isNew: item.value.id == nil) { draft in
                editor.upsert(draft, id: item.value.id)
            }
        }
    }

    struct IdentifiedEditing: Identifiable {
        let value: EditingRule
        var id: String { value.identity }
    }

    private func edit(_ row: ConfigEditor.Row) {
        guard let draft = row.draft else { return }
        editing = EditingRule(id: row.id, draft: draft)
    }

    private func duplicate(_ row: ConfigEditor.Row) {
        guard var draft = row.draft else { return }
        draft.name = draft.name.isEmpty ? "" : draft.name + " copy"
        draft.enabled = false
        errorMessage = editor.upsert(draft, id: nil)
    }
}

struct RuleRow: View {
    let row: ConfigEditor.Row
    let issue: ConfigIssue?
    let isActive: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Enabled", isOn: Binding(get: { row.enabled }, set: { setEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            StatusBadge(text: status.text, color: status.color)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-click to edit")
    }

    private var detail: String? {
        guard let draft = row.draft else { return "Advanced rule - edit it in the configuration file." }
        var parts: [String] = []
        if !draft.devices.isEmpty { parts.append("Only on \(draft.devices.joined(separator: ", ")) (experimental)") }
        if !draft.onlyApps.isEmpty { parts.append("Only in \(draft.onlyApps.joined(separator: ", "))") }
        if !draft.exceptApps.isEmpty { parts.append("Not in \(draft.exceptApps.joined(separator: ", "))") }
        if draft.kind == .keyClick { parts.append(draft.policy.title) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var status: (text: String, color: Color) {
        if let issue { return ("Unsupported: \(issue.reason)", .red) }
        if !row.enabled { return ("Off", .secondary) }
        return isActive ? ("Active", .green) : ("Paused", .orange)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .frame(maxWidth: 260, alignment: .trailing)
    }
}

// MARK: - Devices

struct DevicesPane: View {
    @State private var devices = HIDDeviceCatalog.connectedDevices()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected keyboards and pointing devices. Use a device in a rule's conditions to limit the rule to it.")
                .foregroundStyle(.secondary)
            Label {
                Text("Device-specific rules are experimental. macOS does not tag keyboard events with their device, so Clavimo checks which device currently reports the key as pressed. If that is ambiguous, the rule does not apply.")
            } icon: {
                Image(systemName: "flask")
            }
            .font(.callout)
            Table(devices) {
                TableColumn("Name", value: \.name)
                TableColumn("Type") { device in
                    Text([device.isKeyboard ? "Keyboard" : nil, device.isPointer ? "Pointer" : nil].compactMap { $0 }.joined(separator: ", "))
                }
                TableColumn("Connection") { device in Text(device.transport ?? "Unknown") }
                TableColumn("ID") { device in Text(device.id.description).font(.body.monospaced()).textSelection(.enabled) }
            }
            HStack {
                Button("Refresh") { devices = HIDDeviceCatalog.connectedDevices() }
                Spacer()
            }
        }
        .padding(16)
        .navigationTitle("Devices")
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var model: AppModel
    @Bindable var editor: ConfigEditor
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Status") {
                StatusBanner(model: model)
                Toggle("Turn remapping on when Clavimo starts", isOn: Binding(
                    get: { editor.enabledOnLaunch },
                    set: { editor.setEnabledOnLaunch($0) }
                ))
            }
            Section {
                PermissionRow(title: "Accessibility", granted: model.permissions.accessibilityTrusted,
                              explanation: "Lets Clavimo change and replace keyboard and mouse events.",
                              pane: "Privacy_Accessibility")
                PermissionRow(title: "Input Monitoring", granted: model.permissions.listenEventAccess,
                              explanation: "Lets Clavimo observe keyboard events and identify devices.",
                              pane: "Privacy_ListenEvent")
                if !(model.permissions.accessibilityTrusted && model.permissions.listenEventAccess) {
                    Button("Request Permissions") { model.requestPermissions() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Each macOS account grants permissions separately. Clavimo never records typed text.")
            }
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { enabled in
                        do { try model.setLaunchAtLogin(enabled); loginError = nil } catch { loginError = error.localizedDescription }
                    }
                ))
                LabeledContent("Startup status", value: model.loginItemDescription)
                if let loginError { Text(loginError).foregroundStyle(.red) }
                Button("Open Login Items Settings") { SMAppServiceBridge.openLoginItems() }
            } header: {
                Text("Startup")
            } footer: {
                Text("Starts in the background when you sign in to this macOS account. It does not remap input at the login screen.")
            }
            Section("Configuration") {
                LabeledContent("File") {
                    Text(model.configURL.path).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.configURL]) }
                    Button("Reload") {
                        model.reloadConfiguration()
                        editor.reload()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { model.refreshSystemState() }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let explanation: String
    let pane: String

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .accessibilityLabel(granted ? "Granted" : "Not granted")
            VStack(alignment: .leading) {
                Text(title)
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Clavimo").font(.largeTitle.bold())
            Text("Keyboard and mouse rules for macOS").foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
                .font(.callout)
            Text("Open source under the MIT License. Clavimo processes input locally and never records typed text or sends data anywhere.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle("About")
    }
}

import ServiceManagement

enum SMAppServiceBridge {
    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
