import AppKit
import ClavimoQuartz
import Combine
import SwiftUI

/// The first-run guide: what Clavimo does, the permissions it needs and
/// why, the connected devices, a first rule, and a quick check that
/// typing, the mouse and the pause control work.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, permissions, devices, firstRule, ready
    }

    @Bindable var agent: AgentController
    @Bindable var editor: ConfigEditor
    let finish: () -> Void

    @State var step: Step = .welcome
    @State private var devices: [HIDDeviceInfo] = []
    @State private var chosenTemplates: Set<String> = []
    @State private var launchAtLogin = false
    @State private var checks: Set<String> = []
    @State private var errorMessage: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .permissions: permissions
                    case .devices: deviceList
                    case .firstRule: firstRule
                    case .ready: ready
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.xxl)
            }
            Divider()
            HStack {
                StepDots(current: step.rawValue, total: Step.allCases.count)
                Spacer()
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout).lineLimit(2) }
                if step != .welcome {
                    Button(String(localized: "Back")) { move(-1) }
                }
                Button(primaryTitle) { advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.l)
        }
        .frame(width: 640, height: 560)
        .tint(Brand.violet)
        .onReceive(timer) { _ in agent.refreshSystemState() }
        .onAppear {
            devices = HIDDeviceCatalog.connectedDevices()
            for device in devices { DeviceNames.cache[device.id.description] = device.name }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: String(localized: "Get Started")
        case .permissions: permissionsGranted ? String(localized: "Continue") : String(localized: "Skip for Now")
        case .firstRule: chosenTemplates.isEmpty ? String(localized: "Skip") : String(localized: "Add Rules")
        case .ready: String(localized: "Start Clavimo")
        default: String(localized: "Continue")
        }
    }

    private var permissionsGranted: Bool {
        agent.permissions.accessibilityTrusted && agent.permissions.listenEventAccess
    }

    private func move(_ delta: Int) {
        errorMessage = nil
        step = Step(rawValue: step.rawValue + delta) ?? step
    }

    private func advance() {
        switch step {
        case .firstRule:
            for template in RuleTemplates.all where chosenTemplates.contains(template.id) {
                if let error = editor.upsert(template.draft, id: nil) {
                    errorMessage = error
                    return
                }
            }
            move(1)
        case .ready:
            if launchAtLogin { try? agent.setLaunchAtLogin(true) }
            editor.setEnabledOnLaunch(true)
            agent.setEnabled(true)
            finish()
        default:
            move(1)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).accessibilityHidden(true)
            Text(String(localized: "Welcome to Clavimo")).font(.largeTitle.bold())
            Text(String(localized: "Keyboard and mouse rules for macOS.")).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Spacing.m) {
                Feature(symbol: "arrow.left.arrow.right", title: String(localized: "Remap keys"),
                        text: String(localized: "Swap Command and Option, or turn any key into another."))
                Feature(symbol: "computermouse", title: String(localized: "Combine keys and mouse buttons"),
                        text: String(localized: "Hold Fn and click to switch Spaces, or open Mission Control with a side button."))
                Feature(symbol: "arrow.up.and.down", title: String(localized: "Tune the mouse wheel"),
                        text: String(localized: "Reverse it and scroll a fixed distance per notch, without touching the trackpad."))
                Feature(symbol: "lock.shield", title: String(localized: "Private by design"),
                        text: String(localized: "Everything happens on your Mac. Clavimo never records what you type and makes no network connections."))
            }
            .padding(.top, Spacing.s)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(String(localized: "Allow Clavimo to read and change input")).font(.title.bold())
            Text(String(localized: "macOS asks you to approve this once, in System Settings. Each macOS account approves separately, and you can revoke it at any time."))
                .foregroundStyle(.secondary)
            Card {
                VStack(spacing: Spacing.m) {
                    PermissionRow(title: String(localized: "Accessibility"), granted: agent.permissions.accessibilityTrusted,
                                  explanation: String(localized: "Needed to change, replace or hold back keyboard and mouse events."),
                                  link: .accessibility)
                    Divider()
                    PermissionRow(title: String(localized: "Input Monitoring"), granted: agent.permissions.listenEventAccess,
                                  explanation: String(localized: "Needed to read keyboard events and tell devices apart."),
                                  link: .inputMonitoring)
                }
            }
            if !permissionsGranted {
                Button(String(localized: "Ask macOS for Permission")) { agent.requestPermissions() }
                Text(String(localized: "Turn on Clavimo in both lists. This page updates by itself."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Label(String(localized: "All set."), systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(String(localized: "Your devices")).font(.title.bold())
            Text(String(localized: "Rules work with any keyboard and mouse. You can also limit a rule to one of these later."))
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                HStack(spacing: Spacing.m) {
                    Image(systemName: device.looksLikeMouse ? "computermouse" : "keyboard")
                        .foregroundStyle(device.looksLikeMouse ? Brand.mint : Brand.violet)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(device.name)
                    Spacer()
                    Text(device.transport ?? "").font(.caption).foregroundStyle(.secondary)
                }
                .padding(Spacing.m)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(String(localized: "If a mouse side button does nothing later, check whether Logi Options+ or a similar tool already uses it."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var firstRule: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(String(localized: "Pick a few rules to start")).font(.title.bold())
            Text(String(localized: "You can change or remove them at any time in Rules.")).foregroundStyle(.secondary)
            ForEach(RuleTemplates.all) { template in
                Toggle(isOn: Binding(
                    get: { chosenTemplates.contains(template.id) },
                    set: { on in
                        if on { chosenTemplates.insert(template.id) } else { chosenTemplates.remove(template.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(template.title).font(.headline)
                        RuleTokensView(tokens: template.draft.tokens)
                    }
                    .padding(.leading, Spacing.s)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(String(localized: "Ready to go")).font(.title.bold())
            Text(String(localized: "When you start Clavimo, it lives in the menu bar. Check that everything still feels normal:"))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Spacing.s) {
                check("typing", String(localized: "I can type normally in another app"))
                check("mouse", String(localized: "Clicking and scrolling work as usual"))
                check("menu", String(localized: "I found the Clavimo icon in the menu bar; its menu can pause or disable remapping"))
            }
            Toggle(String(localized: "Start Clavimo when I log in"), isOn: $launchAtLogin)
                .toggleStyle(.switch)
            Text(String(localized: "If anything feels wrong, choose Emergency Disable in the menu bar, or quit Clavimo. Input goes back to normal immediately."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func check(_ id: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding(get: { checks.contains(id) }, set: { if $0 { checks.insert(id) } else { checks.remove(id) } }))
            .toggleStyle(.checkbox)
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Brand.violet)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Brand.violet : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Step \(current + 1) of \(total)"))
    }
}
