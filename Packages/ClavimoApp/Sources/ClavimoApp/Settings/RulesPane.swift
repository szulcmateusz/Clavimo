import ClavimoCore
import SwiftUI

struct RulesPane: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, active, off, problems
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .active: String(localized: "Active")
            case .off: String(localized: "Off")
            case .problems: String(localized: "Problems")
            }
        }
    }

    struct Editing: Identifiable {
        let ruleID: String?
        let draft: RuleDraft
        var id: String { ruleID ?? "new" }
    }

    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    @Bindable var navigation: SettingsNavigation
    @State private var editing: Editing?
    @State private var editingKeyboard: KeyboardPane.Editing?
    @State private var pasting = false
    @State private var selection: String?
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var errorMessage: String?
    @State private var profileID = ""

    /// Rules of the selected profile. Mouse wheel settings live in Mouse
    /// & Scrolling.
    private var rows: [ConfigEditor.Row] {
        editor.rows.filter { $0.draft?.kind.isSetting != true && $0.profileID == selectedProfile }
    }

    private var selectedProfile: String {
        profileID.isEmpty ? editor.activeProfileID : profileID
    }

    private var inheritedCount: Int {
        let ancestors = editor.ancestors(of: selectedProfile)
        return editor.rows.filter { $0.draft?.kind.isSetting != true && ancestors.contains($0.profileID) }.count
    }

    private func newDraft(_ base: RuleDraft = RuleDraft()) -> RuleDraft {
        var draft = base
        draft.profileID = selectedProfile
        return draft
    }

    private var visibleRows: [ConfigEditor.Row] {
        rows.filter { row in
            let issue = model.unsupported.contains { $0.ruleID == row.id }
            let matchesFilter = switch filter {
            case .all: true
            case .active: row.enabled && !issue
            case .off: !row.enabled
            case .problems: issue || !row.isEditable
            }
            guard matchesFilter else { return false }
            guard !search.isEmpty else { return true }
            let text = [row.name, row.draft?.sentence ?? row.keyboard?.suggestedName ?? ""].joined(separator: " ")
            return text.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                ProfilePicker(editor: editor, selection: Binding(get: { selectedProfile }, set: { profileID = $0 }))
                Picker(String(localized: "Show"), selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                Spacer()
                Button { pasting = true } label: {
                    Label(String(localized: "Paste Rules..."), systemImage: "doc.on.clipboard")
                }
                .help(String(localized: "Add rules written by an AI assistant or copied from elsewhere"))
                Button { editing = Editing(ruleID: nil, draft: newDraft()) } label: {
                    Label(String(localized: "New Rule"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.m)

            if let message = editor.lastError ?? errorMessage {
                WarningCard(symbol: "xmark.octagon.fill", color: .red, title: String(localized: "Could not save"), message: message)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.s)
            }

            if inheritedCount > 0 {
                Label(String(localized: "This profile also uses rules inherited from \(editor.ancestors(of: selectedProfile).map(editor.profileName).formatted(.list(type: .and))) (\(inheritedCount))."),
                      systemImage: "arrow.turn.down.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.s)
            }

            if rows.isEmpty {
                EmptyRulesView { draft in editing = Editing(ruleID: nil, draft: newDraft(draft)) }
            } else if visibleRows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(selection: $selection) {
                    ForEach(visibleRows) { row in
                        RuleRow(row: row, issue: model.unsupported.first { $0.ruleID == row.id },
                                engineActive: model.status == .active) { enabled in
                            errorMessage = editor.setEnabled(enabled, id: row.id)
                        }
                        .tag(row.id)
                        .accessibilityAction(named: Text(String(localized: "Edit..."))) { edit(row) }
                        .accessibilityAction(named: Text(String(localized: "Duplicate"))) { duplicate(row) }
                        .accessibilityAction(named: Text(String(localized: "Delete"))) { errorMessage = editor.delete(id: row.id) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                // Double-click or Return edits; Delete removes the selected rule.
                .contextMenu(forSelectionType: String.self) { ids in
                    if let row = row(for: ids) {
                        Button(String(localized: "Edit...")) { edit(row) }.disabled(!row.isEditable)
                        Button(String(localized: "Duplicate")) { duplicate(row) }.disabled(row.draft == nil)
                        Divider()
                        Button(String(localized: "Delete"), role: .destructive) { errorMessage = editor.delete(id: row.id) }
                    }
                } primaryAction: { ids in
                    if let row = row(for: ids) { edit(row) }
                }
                .onDeleteCommand {
                    if let row = row(for: selection.map { [$0] } ?? []) { errorMessage = editor.delete(id: row.id) }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: Text(String(localized: "Search rules")))
        .navigationTitle(String(localized: "Rules"))
        .sheet(item: $editing) { item in
            RuleEditorView(model: model, draft: item.draft, isNew: item.ruleID == nil) { draft in
                editor.upsert(draft, id: item.ruleID)
            }
        }
        .sheet(item: $editingKeyboard) { item in
            KeyboardRuleEditor(model: model, draft: item.draft, isNew: false,
                               layers: Array(Set(editor.rows.compactMap { $0.keyboard?.layer })).sorted()) { draft in
                editor.upsertKeyboard(draft, id: item.ruleID)
            }
        }
        .sheet(isPresented: $pasting) {
            PasteRulesView(editor: editor) { result in errorMessage = result == String(localized: "Configuration applied.") ? nil : result }
        }
        .onAppear(perform: consumeRequest)
        .onChange(of: navigation.ruleToCreate) { consumeRequest() }
    }

    private func consumeRequest() {
        guard let draft = navigation.ruleToCreate else { return }
        navigation.ruleToCreate = nil
        editing = Editing(ruleID: nil, draft: newDraft(draft))
    }

    private func row(for ids: Set<String>) -> ConfigEditor.Row? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return rows.first { $0.id == id }
    }

    private func edit(_ row: ConfigEditor.Row) {
        if let keyboard = row.keyboard {
            editingKeyboard = KeyboardPane.Editing(ruleID: row.id, draft: keyboard)
            return
        }
        guard let draft = row.draft else { return }
        editing = Editing(ruleID: row.id, draft: draft)
    }

    private func duplicate(_ row: ConfigEditor.Row) {
        guard var draft = row.draft else { return }
        draft.name = draft.name.isEmpty ? "" : String(localized: "\(draft.name) copy")
        draft.enabled = false
        errorMessage = editor.upsert(draft, id: nil)
    }
}

struct RuleRow: View {
    let row: ConfigEditor.Row
    let issue: ConfigIssue?
    let engineActive: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Toggle(String(localized: "Enabled"), isOn: Binding(get: { row.enabled }, set: { setEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Text(row.name).font(.headline)
                    if row.draft?.devices.isEmpty == false {
                        StatusChip(text: String(localized: "Device"), kind: .beta)
                    }
                }
                if let draft = row.draft {
                    RuleTokensView(tokens: draft.tokens)
                    Text(draft.sentence).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                } else if let keyboard = row.keyboard {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: keyboard.kind.symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                        KeyCap(label: keyboard.triggerTitle, caption: nil)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(keyboard.resultTitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                } else {
                    Text(String(localized: "Advanced rule. Edit it in the configuration file."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let issue {
                    Label(Messages.describe(issue.reason), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            .opacity(row.enabled ? 1 : 0.55)
            Spacer(minLength: Spacing.s)
            StatusChip(text: status.text, kind: status.kind)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "Double-click or press Return to edit"))
    }

    private var status: (text: String, kind: StatusChip.Kind) {
        if issue != nil { return (String(localized: "Cannot run"), .problem) }
        if !row.enabled { return (String(localized: "Off"), .off) }
        return engineActive ? (String(localized: "Active"), .active) : (String(localized: "Paused"), .paused)
    }
}

/// Shown when there are no rules yet: ready-made starting points.
struct EmptyRulesView: View {
    let create: (RuleDraft) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                SectionHeader(title: String(localized: "Start with a template"),
                              subtitle: String(localized: "Pick one and adjust it, or create a rule from scratch."))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                    ForEach(RuleTemplates.all) { template in
                        Button { create(template.draft) } label: {
                            Card {
                                VStack(alignment: .leading, spacing: Spacing.s) {
                                    Text(template.title).font(.headline)
                                    RuleTokensView(tokens: template.draft.tokens)
                                    Text(template.draft.sentence).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { create(RuleDraft()) } label: { Label(String(localized: "Create from Scratch"), systemImage: "plus") }
            }
            .padding(Spacing.xl)
        }
    }
}
