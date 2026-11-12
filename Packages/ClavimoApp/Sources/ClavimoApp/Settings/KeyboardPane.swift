import ClavimoCore
import ClavimoQuartz
import SwiftUI

/// Caps Lock, home row modifiers, layers, tap-hold keys, combos and key
/// sequences.
struct KeyboardPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    @State private var editing: Editing?
    @State private var editingRemap: RuleDraft?
    @State private var errorMessage: String?
    @State private var homeRowHold = TapHoldSettings.homeRow.holdAfterMilliseconds
    @AppStorage(KeyboardOverlayPanel.preferenceKey) private var showOverlay = true

    struct Editing: Identifiable {
        let id = UUID()
        let ruleID: String?
        let draft: KeyboardRuleDraft
    }

    nonisolated static let capsLockRuleID = "keyboard-caps-lock"
    nonisolated static let homeRowPrefix = "keyboard-home-row-"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                introCard
                warnings
                capsLockCard
                homeRowCard
                rulesCard
                templatesCard
                Toggle(String(localized: "Show the active layer and the next keys of a sequence on screen"), isOn: $showOverlay)
                    .padding(.horizontal, Spacing.s)
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Keyboard"))
        .onAppear { model.refreshCapsLockStatus() }
        .sheet(item: $editing) { item in
            KeyboardRuleEditor(model: model, draft: item.draft, isNew: item.ruleID == nil, layers: layerNames) { draft in
                editor.upsertKeyboard(draft, id: item.ruleID)
            }
        }
    }

    // MARK: Data

    private var keyboardRows: [ConfigEditor.Row] {
        editor.rows.filter { $0.keyboard != nil && !Self.isReserved($0.id) }
    }

    static func isReserved(_ id: String) -> Bool {
        id == capsLockRuleID || id.hasPrefix(homeRowPrefix)
    }

    private var layerNames: [String] {
        var names: [String] = []
        for row in editor.rows {
            guard let draft = row.keyboard else { continue }
            for name in [draft.layer, draft.output.layer, draft.hold.layer]
                where !names.contains(name) && (draft.kind == .layerKey || [draft.output.kind, draft.hold.kind].contains { $0 == .holdLayer || $0 == .toggleLayer }) {
                names.append(name)
            }
        }
        return names
    }

    private var profileID: String { editor.activeProfileID }

    // MARK: Intro and warnings

    private var introCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "keyboard").font(.system(size: 30)).foregroundStyle(Brand.violet).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(String(localized: "Make every key do more")).font(.title3.weight(.semibold))
                    Text(String(localized: "A key can do one thing when tapped and another when held, switch on a layer of other keys, fire with another key pressed at the same moment, or start a short sequence. Keys you do not change keep working exactly as before."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if let message = editor.lastError ?? errorMessage {
            WarningCard(symbol: "xmark.octagon.fill", color: .red, title: String(localized: "Could not save"), message: message)
        }
        if model.secureInput.isEnabled {
            WarningCard(
                symbol: "lock.fill", color: .orange,
                title: String(localized: "Secure typing is on"),
                message: model.secureInput.appName.map {
                    String(localized: "\($0) asked macOS to hide keystrokes (for example in a password field), so keyboard rules wait until it ends. Mouse and trackpad rules keep working.")
                } ?? String(localized: "An app asked macOS to hide keystrokes (for example in a password field), so keyboard rules wait until it ends. Mouse and trackpad rules keep working.")
            )
        }
        if !model.capsLockStatus.conflictingKeyboards.isEmpty {
            WarningCard(
                symbol: "exclamationmark.triangle.fill", color: .orange,
                title: String(localized: "Caps Lock is changed in System Settings"),
                message: String(localized: "On \(model.capsLockStatus.conflictingKeyboards.formatted(.list(type: .and))), Caps Lock is set to another key in System Settings > Keyboard > Keyboard Shortcuts > Modifier Keys. Set it back to Caps Lock there to use Caps Lock rules on that keyboard."),
                action: (String(localized: "Open Keyboard Settings"), { SystemSettingsLink.open(.keyboardShortcuts) })
            )
        }
    }

    // MARK: Caps Lock

    enum CapsPreset: String, CaseIterable, Identifiable {
        case unchanged, escape, controlEscape, hyperEscape, hyperCapsLock, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .unchanged: String(localized: "Caps Lock (unchanged)")
            case .escape: String(localized: "Escape")
            case .controlEscape: String(localized: "Tap: Escape, hold: Control")
            case .hyperEscape: String(localized: "Tap: Escape, hold: Hyper (⌃⌥⇧⌘)")
            case .hyperCapsLock: String(localized: "Tap: Caps Lock, hold: Hyper (⌃⌥⇧⌘)")
            case .custom: String(localized: "Custom")
            }
        }
    }

    private var capsRow: ConfigEditor.Row? { editor.rows.first { $0.id == Self.capsLockRuleID } }

    private var capsPreset: CapsPreset {
        guard let row = capsRow else { return .unchanged }
        if let draft = row.draft, draft.kind == .remapKey, draft.secondKey == KeyCode.escape.rawValue { return .escape }
        guard let draft = row.keyboard, draft.kind == .tapHold, draft.key == KeyCode.capsLock.rawValue else { return .custom }
        switch (draft.output.kind, draft.output.key, draft.hold.kind, draft.hold.modifiers) {
        case (.key, KeyCode.escape.rawValue, .modifiers, [.control]): return .controlEscape
        case (.key, KeyCode.escape.rawValue, .modifiers, OutputDraft.hyper): return .hyperEscape
        case (.capsLock, _, .modifiers, OutputDraft.hyper): return .hyperCapsLock
        default: return .custom
        }
    }

    private var capsDoubleTap: Bool { capsRow?.keyboard?.doubleTapEnabled == true && capsRow?.keyboard?.doubleTap.kind == .capsLock }

    private var capsLockCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Caps Lock"),
                              subtitle: String(localized: "The easiest key to reach that does the least. Hyper (all four modifiers) gives you shortcuts no app uses."))
                Picker(String(localized: "Caps Lock does"), selection: Binding(get: { capsPreset }, set: { setCapsPreset($0, doubleTap: capsDoubleTap) })) {
                    ForEach(CapsPreset.allCases.filter { $0 != .custom || capsPreset == .custom }) { Text($0.title).tag($0) }
                }
                .fixedSize()
                if capsPreset == .controlEscape || capsPreset == .hyperEscape {
                    Toggle(String(localized: "Double tap turns Caps Lock on or off"),
                           isOn: Binding(get: { capsDoubleTap }, set: { setCapsPreset(capsPreset, doubleTap: $0) }))
                }
                if let row = capsRow, let draft = row.keyboard {
                    HStack {
                        Text(draft.resultTitle).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Fine-tune...")) { editing = Editing(ruleID: row.id, draft: draft) }
                    }
                }
                Text(String(localized: "Clavimo moves Caps Lock to a spare key (F18) at the keyboard level while these rules run, and restores it when remapping stops."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setCapsPreset(_ preset: CapsPreset, doubleTap: Bool) {
        switch preset {
        case .unchanged:
            errorMessage = editor.delete(id: Self.capsLockRuleID)
        case .escape:
            var draft = RuleDraft()
            draft.kind = .remapKey
            draft.firstKey = KeyCode.capsLock.rawValue
            draft.secondKey = KeyCode.escape.rawValue
            draft.profileID = profileID
            draft.name = String(localized: "Caps Lock to Escape")
            errorMessage = editor.upsert(draft, id: Self.capsLockRuleID)
        case .controlEscape, .hyperEscape, .hyperCapsLock:
            var draft = capsRow?.keyboard ?? KeyboardRuleDraft()
            draft.kind = .tapHold
            draft.key = KeyCode.capsLock.rawValue
            draft.profileID = capsRow?.profileID ?? profileID
            draft.output = preset == .hyperCapsLock ? .of(.capsLock) : .key(KeyCode.escape.rawValue)
            draft.hold = .modifiers(preset == .controlEscape ? [.control] : OutputDraft.hyper)
            draft.doubleTapEnabled = preset != .hyperCapsLock && doubleTap
            draft.doubleTap = .of(.capsLock)
            draft.name = String(localized: "Caps Lock: \(preset.title)")
            errorMessage = editor.replaceKeyboardRules([(Self.capsLockRuleID, draft)], removing: [Self.capsLockRuleID])
        case .custom:
            break
        }
    }

    // MARK: Home row modifiers

    enum HomeRowOrder: String, CaseIterable, Identifiable {
        case commandOptionControlShift, controlOptionCommandShift
        var id: String { rawValue }
        var modifiers: [RuleDraft.Modifier] {
            switch self {
            case .commandOptionControlShift: [.command, .option, .control, .shift]
            case .controlOptionCommandShift: [.control, .option, .command, .shift]
            }
        }
        var title: String { modifiers.map(\.symbol).joined(separator: " ") }
    }

    /// A S D F and ; L K J, from the little finger inwards.
    nonisolated static let leftHomeRow: [UInt16] = [0x00, 0x01, 0x02, 0x03]
    nonisolated static let rightHomeRow: [UInt16] = [0x29, 0x25, 0x28, 0x26]

    private var homeRowRows: [ConfigEditor.Row] { editor.rows.filter { $0.id.hasPrefix(Self.homeRowPrefix) } }

    private var homeRowOrder: HomeRowOrder? {
        guard let first = homeRowRows.first(where: { $0.id == Self.homeRowPrefix + "\(Self.leftHomeRow[0])" })?.keyboard else { return nil }
        return HomeRowOrder.allCases.first { first.hold.modifiers == [$0.modifiers[0]] }
    }

    private var homeRowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Home row modifiers"),
                              subtitle: String(localized: "Hold A S D F or J K L ; for modifiers without leaving the home row; tap them to type as usual."))
                Toggle(String(localized: "Use home row modifiers"), isOn: Binding(
                    get: { !homeRowRows.isEmpty },
                    set: { $0 ? writeHomeRow(order: homeRowOrder ?? .commandOptionControlShift) : removeHomeRow() }
                ))
                if !homeRowRows.isEmpty {
                    Picker(String(localized: "From the little finger inwards"), selection: Binding(
                        get: { homeRowOrder ?? .commandOptionControlShift }, set: { writeHomeRow(order: $0) }
                    )) {
                        ForEach(HomeRowOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(String(localized: "Hold after")) {
                        HStack {
                            Slider(value: Binding(get: { Double(homeRowHold) }, set: { homeRowHold = Int($0 / 10) * 10 }), in: 160...320) { editing in
                                if !editing { writeHomeRow(order: homeRowOrder ?? .commandOptionControlShift) }
                            }
                            Text("\(homeRowHold) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                        }
                    }
                    Text(String(localized: "Misfires are prevented: a key of the same hand or fast typing always types the letter. If letters still turn into shortcuts, raise the time."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if let hold = homeRowRows.first?.keyboard?.holdAfterMilliseconds { homeRowHold = hold }
        }
    }

    private func writeHomeRow(order: HomeRowOrder) {
        let keys = Self.leftHomeRow + Self.rightHomeRow
        let modifiers = order.modifiers + order.modifiers
        let drafts = zip(keys, modifiers).map { key, modifier in
            (Self.homeRowPrefix + "\(key)", KeyboardRuleDraft.homeRow(key: key, modifier: modifier, holdAfter: homeRowHold, profileID: profileID))
        }
        errorMessage = editor.replaceKeyboardRules(drafts, removing: Set(homeRowRows.map(\.id)))
    }

    private func removeHomeRow() {
        errorMessage = editor.replaceKeyboardRules([], removing: Set(homeRowRows.map(\.id)))
    }

    // MARK: Rules

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    SectionHeader(title: String(localized: "Your keyboard rules"),
                                  subtitle: keyboardRows.isEmpty ? String(localized: "None yet. Start with a template below.") : nil)
                    Spacer()
                    Menu {
                        ForEach(KeyboardRuleDraft.Kind.allCases) { kind in
                            Button { newRule(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label(String(localized: "New Rule"), systemImage: "plus")
                    }
                    .fixedSize()
                }
                ForEach(KeyboardRuleDraft.Kind.allCases) { kind in
                    let rows = keyboardRows.filter { $0.keyboard?.kind == kind }
                    if !rows.isEmpty {
                        Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, Spacing.xs)
                        ForEach(sorted(rows)) { row in
                            KeyboardRuleRow(row: row, issue: model.unsupported.first { $0.ruleID == row.id }) { enabled in
                                errorMessage = editor.setEnabled(enabled, id: row.id)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { edit(row) }
                            .contextMenu {
                                Button(String(localized: "Edit...")) { edit(row) }
                                Button(String(localized: "Delete"), role: .destructive) { errorMessage = editor.delete(id: row.id) }
                            }
                            .accessibilityAction(named: Text(String(localized: "Edit..."))) { edit(row) }
                        }
                    }
                }
            }
        }
    }

    /// Layer keys grouped by layer, then by name.
    private func sorted(_ rows: [ConfigEditor.Row]) -> [ConfigEditor.Row] {
        rows.sorted { ($0.keyboard?.layer ?? "", $0.name) < ($1.keyboard?.layer ?? "", $1.name) }
    }

    private func newRule(_ kind: KeyboardRuleDraft.Kind) {
        var draft = KeyboardRuleDraft(kind: kind)
        draft.profileID = profileID
        if kind == .layerKey, let layer = layerNames.first { draft.layer = layer }
        editing = Editing(ruleID: nil, draft: draft)
    }

    private func edit(_ row: ConfigEditor.Row) {
        guard let draft = row.keyboard else { return }
        editing = Editing(ruleID: row.id, draft: draft)
    }

    // MARK: Templates

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: String(localized: "Templates"),
                          subtitle: String(localized: "Each adds a set of rules you can change or delete later."))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                ForEach(KeyboardTemplates.all) { template in
                    Button { add(template) } label: {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Label(template.title, systemImage: template.symbol).font(.headline)
                                Text(template.summary).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func add(_ template: KeyboardTemplates.Template) {
        let drafts = template.drafts.map { draft -> (String, KeyboardRuleDraft) in
            var draft = draft
            draft.profileID = profileID
            return (UUID().uuidString.lowercased(), draft)
        }
        errorMessage = editor.replaceKeyboardRules(drafts, removing: [])
    }
}

/// One keyboard rule: what triggers it and what it does.
struct KeyboardRuleRow: View {
    let row: ConfigEditor.Row
    let issue: ConfigIssue?
    let setEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Toggle(String(localized: "Enabled"), isOn: Binding(get: { row.enabled }, set: { setEnabled($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            if let draft = row.keyboard {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.headline)
                    HStack(spacing: Spacing.s) {
                        KeyCap(label: draft.triggerTitle, caption: nil)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(draft.resultTitle).font(.callout).foregroundStyle(.secondary)
                    }
                    if let issue {
                        Label(Messages.describe(issue.reason), systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                    }
                }
                .opacity(row.enabled ? 1 : 0.55)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
