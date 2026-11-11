import AppKit
import ClavimoQuartz
import SwiftUI

struct OverviewPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    let navigation: SettingsNavigation
    @State private var devices: [HIDDeviceInfo] = []
    @State private var disabledShortcuts: [SystemChecks.Shortcut] = []
    @State private var accelerationEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                StatusHero(model: model)
                warnings
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Spacing.m)], spacing: Spacing.m) {
                    StatCard(title: String(localized: "Rules"), value: "\(activeRuleCount)",
                             detail: ruleDetail, symbol: "list.bullet.rectangle.portrait") { navigation.pane = .rules }
                    StatCard(title: String(localized: "Devices"), value: "\(devices.count)",
                             detail: deviceDetail, symbol: "keyboard") { navigation.pane = .devices }
                    StatCard(title: String(localized: "Mouse wheel"), value: wheelValue,
                             detail: wheelDetail, symbol: "computermouse") { navigation.pane = .mouse }
                }
                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        SectionHeader(title: String(localized: "Quick actions"))
                        HStack(spacing: Spacing.s) {
                            Button { navigation.createRule() } label: { Label(String(localized: "New Rule"), systemImage: "plus") }
                                .buttonStyle(.borderedProminent)
                            Button { navigation.pane = .mouse } label: { Label(String(localized: "Mouse & Scrolling"), systemImage: "computermouse") }
                            Button { navigation.pane = .general } label: { Label(String(localized: "Permissions"), systemImage: "lock.shield") }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Overview"))
        .onAppear(perform: refresh)
    }

    private func refresh() {
        devices = HIDDeviceCatalog.connectedDevices()
        for device in devices { DeviceNames.cache[device.id.description] = device.name }
        disabledShortcuts = SystemChecks.disabledShortcuts()
        accelerationEnabled = SystemChecks.pointerAccelerationEnabled
        model.refreshSystemState()
    }

    // MARK: Warnings

    @ViewBuilder
    private var warnings: some View {
        if let other = model.otherRemapper {
            WarningCard(symbol: "exclamationmark.triangle.fill", color: .orange,
                        title: String(localized: "\(other) is running"),
                        message: String(localized: "Two tools changing the keyboard or mouse at once can apply rules twice. Quit one of them."))
        }
        if !disabledShortcuts.isEmpty {
            WarningCard(symbol: "keyboard.badge.exclamationmark", color: .orange,
                        title: String(localized: "Some macOS shortcuts are turned off"),
                        message: String(localized: "Actions that use them will do nothing: \(disabledShortcuts.map(\.title).formatted(.list(type: .and)))."),
                        action: (String(localized: "Open Keyboard Shortcuts"), { SystemSettingsLink.open(.keyboardShortcuts) }))
        }
        if !model.unsupported.isEmpty {
            WarningCard(symbol: "xmark.octagon.fill", color: .red,
                        title: String(localized: "\(model.unsupported.count) rules cannot run"),
                        message: model.unsupported.map(Messages.describe).joined(separator: "\n"),
                        action: (String(localized: "Show Rules"), { navigation.pane = .rules }))
        }
    }

    // MARK: Numbers

    private var ruleRows: [ConfigEditor.Row] { editor.rows.filter { $0.draft?.kind.isSetting != true } }

    private var activeRuleCount: Int {
        ruleRows.filter { row in row.enabled && !model.unsupported.contains { $0.ruleID == row.id } }.count
    }

    private var ruleDetail: String {
        let off = ruleRows.filter { !$0.enabled }.count
        return off == 0 ? String(localized: "all enabled") : String(localized: "\(off) turned off")
    }

    private var deviceDetail: String {
        let mice = devices.filter(\.looksLikeMouse).count
        let keyboards = devices.filter { $0.isKeyboard && !$0.looksLikeMouse }.count
        return [String(localized: "\(keyboards) keyboards"), String(localized: "\(mice) mice")].formatted(.list(type: .and))
    }

    private var wheel: RuleDraft? { editor.rows.first { $0.draft?.kind == .wheel && $0.enabled }?.draft }

    private var wheelValue: String {
        wheel == nil ? String(localized: "System") : String(localized: "Custom")
    }

    private var wheelDetail: String {
        var parts: [String] = []
        if let wheel { parts.append(wheel.wheelSummary) }
        parts.append(accelerationEnabled ? String(localized: "pointer acceleration on") : String(localized: "pointer acceleration off"))
        return parts.joined(separator: " · ")
    }
}

/// The large card at the top: what Clavimo is doing right now, and the
/// switch to turn it on or off.
struct StatusHero: View {
    @Bindable var model: AgentController

    var body: some View {
        HStack(spacing: Spacing.l) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Circle().fill(model.status == .active ? Brand.mint : .orange).frame(width: 9, height: 9)
                    Text(model.status.title).font(.title2.weight(.semibold))
                }
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            Spacer(minLength: Spacing.l)
            Toggle(String(localized: "Remapping"), isOn: Binding(get: { model.userEnabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
                .tint(Brand.mint)
                .disabled(model.status == .needsPermission || model.status == .configurationError)
                .accessibilityLabel(String(localized: "Remapping"))
        }
        .padding(Spacing.xl)
        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        if let until = model.pausedUntil {
            return String(localized: "Paused. Resumes at \(until.formatted(date: .omitted, time: .shortened)).")
        }
        return switch model.status {
        case .active: String(localized: "Your rules are applied to keyboard and mouse input.")
        case .pausedByUser: String(localized: "Input passes through unchanged until you turn remapping on.")
        case .pausedInactiveSession: String(localized: "Another macOS account is in use. Remapping resumes when you return.")
        case .needsPermission: String(localized: "Grant Accessibility and Input Monitoring in General to start.")
        case .configurationError: model.loadError ?? String(localized: "The configuration file could not be loaded.")
        case .safeMode: String(localized: "macOS stopped the input connection several times. Resume after checking for conflicts.")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
                    Text(value).font(.system(.title, design: .rounded).weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Opens \(title)"))
    }
}

struct WarningCard: View {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.0, action: action.1).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}
