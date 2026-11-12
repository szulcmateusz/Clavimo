import AppKit
import ClavimoCore
import ClavimoQuartz
import SwiftUI

/// Chooses one of the saved compasses.
struct CompassPicker: View {
    @Binding var compassID: String
    let model: AgentController
    /// A compass that cannot be chosen, e.g. the one being edited.
    var excluding: String?

    var body: some View {
        let choices = model.compassChoices.filter { $0.id != excluding }
        if choices.isEmpty {
            Text(String(localized: "No compass yet. Add one in the Compass pane."))
                .foregroundStyle(.secondary)
        } else {
            Picker(String(localized: "Compass"), selection: $compassID) {
                if !choices.contains(where: { $0.id == compassID }) {
                    Text(String(localized: "Choose…")).tag(compassID)
                }
                ForEach(choices, id: \.id) { Text($0.name).tag($0.id) }
            }
            .onAppear {
                if compassID.isEmpty, let first = choices.first { compassID = first.id }
            }
        }
    }
}

/// A menu item of another app, chosen from its menus.
struct MenuItemField: View {
    @Binding var path: [String]
    @State private var picking = false

    var body: some View {
        LabeledContent(String(localized: "Menu item")) {
            HStack {
                Text(path.isEmpty ? String(localized: "None") : path.joined(separator: " › "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                Button(String(localized: "Choose…")) { picking = true }
            }
        }
        .sheet(isPresented: $picking) {
            MenuItemPicker(path: $path)
        }
    }
}

/// Lists the menus of a running app so an item can be chosen without
/// typing its titles. Titles are stored in the app's language.
struct MenuItemPicker: View {
    @Binding var path: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var appPID: pid_t?
    @State private var items: [MenuItems.Item] = []
    @State private var loading = false
    @State private var search = ""
    @State private var selection: [String]?

    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private var filtered: [MenuItems.Item] {
        let words = search.lowercased().split(separator: " ")
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let text = item.path.joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Choose a menu item")).font(.headline)
            Picker(String(localized: "App"), selection: $appPID) {
                Text(String(localized: "Choose an app")).tag(pid_t?.none)
                ForEach(apps, id: \.processIdentifier) { app in
                    Text(app.localizedName ?? app.bundleIdentifier ?? "?").tag(Optional(app.processIdentifier))
                }
            }
            .onChange(of: appPID) { _, pid in load(pid) }
            TextField(String(localized: "Search"), text: $search)
                .textFieldStyle(.roundedBorder)
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appPID != nil, items.isEmpty {
                    Text(String(localized: "Clavimo could not read this app's menus. Check that Clavimo has Accessibility permission and that the app is still open."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, id: \.path, selection: $selection) { item in
                        HStack {
                            Text(item.path.joined(separator: " › "))
                                .foregroundStyle(item.isEnabled ? .primary : .secondary)
                            Spacer()
                            if let shortcut = item.shortcut {
                                Text(shortcut).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .tag(item.path)
                    }
                }
            }
            .frame(minHeight: 280)
            Text(String(localized: "Menu titles are saved in the app's language. If you change the language of macOS or the app, choose the item again."))
                .formFooterStyle()
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Choose")) {
                    if let selection { path = selection }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
    }

    private func load(_ pid: pid_t?) {
        items = []
        selection = nil
        guard let pid else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let found = MenuItems.items(inApp: pid)
            await MainActor.run {
                if appPID == pid {
                    items = found
                    loading = false
                }
            }
        }
    }
}
