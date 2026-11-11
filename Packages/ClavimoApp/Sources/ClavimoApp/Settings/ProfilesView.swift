import ClavimoCore
import SwiftUI

/// Chooses which profile the rule list shows and edits.
struct ProfilePicker: View {
    @Bindable var editor: ConfigEditor
    @Binding var selection: String
    @State private var managing = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Picker(String(localized: "Profile"), selection: $selection) {
                ForEach(editor.profiles, id: \.id) { profile in
                    Text(profile.id == editor.activeProfileID
                        ? String(localized: "\(profile.name) (active)")
                        : profile.name).tag(profile.id)
                }
            }
            .frame(maxWidth: 240)
            if selection != editor.activeProfileID {
                Button(String(localized: "Make Active")) { editor.setActiveProfile(selection) }
            }
            Button { managing = true } label: { Image(systemName: "slider.horizontal.3") }
                .help(String(localized: "Manage Profiles"))
                .accessibilityLabel(String(localized: "Manage Profiles"))
        }
        .sheet(isPresented: $managing) { ManageProfilesView(editor: editor, selection: $selection) }
    }
}

struct ManageProfilesView: View {
    @Bindable var editor: ConfigEditor
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: ConfigDocument.Profile?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: String(localized: "Profiles"),
                          subtitle: String(localized: "Each profile uses its own rules plus the rules of Default. A rule in a profile replaces a Default rule with the same trigger."))
            List {
                ForEach(editor.profiles, id: \.id) { profile in
                    HStack {
                        if renaming == profile.id {
                            TextField(String(localized: "Name"), text: $renameText)
                                .onSubmit { commitRename(profile.id) }
                            Button(String(localized: "Done")) { commitRename(profile.id) }
                        } else {
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.headline)
                                Text(detail(for: profile)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.id == editor.activeProfileID {
                                StatusChip(text: String(localized: "Active"), kind: .active)
                            } else {
                                Button(String(localized: "Make Active")) { errorMessage = editor.setActiveProfile(profile.id) }
                            }
                            Menu {
                                Button(String(localized: "Rename...")) { renaming = profile.id; renameText = profile.name }
                                if profile.id != editor.profiles.first?.id {
                                    Button(String(localized: "Delete..."), role: .destructive) { deleting = profile }
                                }
                            } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel(String(localized: "More actions for \(profile.name)"))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 180)
            HStack {
                TextField(String(localized: "New profile name, for example Games"), text: $newName)
                    .onSubmit(add)
                Button(String(localized: "Add Profile"), action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(String(localized: "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 520, height: 460)
        .confirmationDialog(String(localized: "Delete \(deleting?.name ?? "")?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { profile in
            Button(String(localized: "Delete Profile and Its Rules"), role: .destructive) {
                errorMessage = editor.deleteProfile(profile.id)
                if selection == profile.id { selection = editor.activeProfileID }
                deleting = nil
            }
        } message: { profile in
            Text(String(localized: "\(rulesCount(profile.id)) rules that belong only to this profile will be deleted."))
        }
    }

    private func detail(for profile: ConfigDocument.Profile) -> String {
        let own = String(localized: "\(rulesCount(profile.id)) own rules")
        guard let parent = profile.inherits else { return own }
        return String(localized: "\(own), inherits from \(editor.profileName(parent))")
    }

    private func rulesCount(_ id: String) -> Int {
        editor.rows.filter { $0.profileID == id }.count
    }

    private func add() {
        if let id = editor.addProfile(named: newName) {
            selection = id
            newName = ""
        }
    }

    private func commitRename(_ id: String) {
        errorMessage = editor.renameProfile(id, to: renameText)
        renaming = nil
    }
}
