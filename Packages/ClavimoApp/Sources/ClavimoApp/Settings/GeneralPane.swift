import AppKit
import SwiftUI

struct GeneralPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Turn remapping on when Clavimo starts"), isOn: Binding(
                    get: { editor.enabledOnLaunch },
                    set: { editor.setEnabledOnLaunch($0) }
                ))
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { enabled in
                        do { try model.setLaunchAtLogin(enabled); loginError = nil } catch { loginError = error.localizedDescription }
                    }
                ))
                LabeledContent(String(localized: "Startup status"), value: model.loginItemDescription)
                if let loginError { Text(loginError).foregroundStyle(.red) }
                Button(String(localized: "Open Login Items Settings")) { SystemSettingsLink.open(.loginItems) }
            } header: {
                Text(String(localized: "Startup"))
            } footer: {
                Text(String(localized: "Clavimo starts in the background when you sign in to this macOS account. It cannot change input at the login screen."))
            }

            Section {
                PermissionRow(title: String(localized: "Accessibility"), granted: model.permissions.accessibilityTrusted,
                              explanation: String(localized: "Lets Clavimo change and replace keyboard and mouse events."),
                              link: .accessibility)
                PermissionRow(title: String(localized: "Input Monitoring"), granted: model.permissions.listenEventAccess,
                              explanation: String(localized: "Lets Clavimo read keyboard events and tell devices apart."),
                              link: .inputMonitoring)
                if !(model.permissions.accessibilityTrusted && model.permissions.listenEventAccess) {
                    Button(String(localized: "Request Permissions")) { model.requestPermissions() }
                }
            } header: {
                Text(String(localized: "Permissions"))
            } footer: {
                Text(String(localized: "Each macOS account grants permissions separately. Clavimo never records typed text and makes no network connections."))
            }

            Section(String(localized: "Configuration")) {
                LabeledContent(String(localized: "File")) {
                    Text(model.configURL.path).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                }
                HStack {
                    Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.configURL]) }
                    Button(String(localized: "Reload")) {
                        model.reloadConfiguration()
                        editor.reload()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "General"))
        .onAppear { model.refreshSystemState() }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let explanation: String
    let link: SystemSettingsLink

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title3)
                .accessibilityLabel(granted ? String(localized: "Granted") : String(localized: "Not granted"))
            VStack(alignment: .leading) {
                Text(title)
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "Open Settings")) { SystemSettingsLink.open(link) }
        }
    }
}

struct AboutPane: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("Clavimo").font(.largeTitle.bold())
            Text(String(localized: "Keyboard and mouse rules for macOS")).foregroundStyle(.secondary)
            Text(String(localized: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")"))
                .font(.callout)
            Text(String(localized: "Open source under the MIT License. Clavimo processes input on your Mac only: it never records typed text and makes no network connections."))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .font(.callout)
                .foregroundStyle(.secondary)
            Link(String(localized: "Project on GitHub"), destination: URL(string: "https://github.com/szulcmateusz/Clavimo")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
        .navigationTitle(String(localized: "About"))
    }
}
