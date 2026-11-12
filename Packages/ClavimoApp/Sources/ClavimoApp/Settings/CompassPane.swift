import AppKit
import ClavimoCore
import SwiftUI

/// Action compasses: eight actions around the pointer, picked by moving in
/// their direction while a key or button is held.
struct CompassPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor

    @State private var selectedID: String?
    /// Nil for the page used everywhere.
    @State private var page: String?
    @State private var editingSlot: SlotEditing?
    @State private var editingRule: RuleEditing?
    @State private var editingKey: KeyEditing?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    struct SlotEditing: Identifiable {
        let id = UUID()
        let direction: CompassDirection
        let slot: CompassSlotDraft
        let isNew: Bool
    }

    struct RuleEditing: Identifiable {
        let id = UUID()
        let ruleID: String?
        let draft: RuleDraft
    }

    struct KeyEditing: Identifiable {
        let id = UUID()
        let ruleID: String?
        let draft: KeyboardRuleDraft
    }

    private var compasses: [CompassDraft] { editor.compasses }

    private var current: CompassDraft? {
        compasses.first { $0.id == selectedID } ?? compasses.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                introCard
                if let message = errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let compass = current {
                    compassCard(compass)
                    triggersCard(compass)
                    settingsCard(compass)
                    templatesCard(compass)
                } else {
                    emptyCard
                }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Compass"))
        .sheet(item: $editingSlot) { item in
            if let compass = current {
                CompassSlotEditor(model: model, slot: item.slot, direction: item.direction, isNew: item.isNew,
                                  onAppPage: page != nil, compassID: compass.id) { slot in
                    var updated = compass
                    updated.setSlot(slot, at: item.direction, page: page)
                    return editor.upsertCompass(updated)
                }
            }
        }
        .sheet(item: $editingRule) { item in
            RuleEditorView(model: model, draft: item.draft, isNew: item.ruleID == nil) { draft in
                editor.upsert(draft, id: item.ruleID)
            }
        }
        .sheet(item: $editingKey) { item in
            KeyboardRuleEditor(model: model, draft: item.draft, isNew: item.ruleID == nil, layers: []) { draft in
                editor.upsertKeyboard(draft, id: item.ruleID)
            }
        }
        .alert(String(localized: "Rename compass"), isPresented: $renaming) {
            TextField(String(localized: "Name"), text: $newName)
            Button(String(localized: "Rename")) {
                guard var compass = current else { return }
                compass.name = newName
                errorMessage = editor.upsertCompass(compass)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(String(localized: "Delete this compass?"), isPresented: $confirmDelete) {
            Button(String(localized: "Delete"), role: .destructive) {
                guard let compass = current else { return }
                errorMessage = editor.deleteCompass(id: compass.id)
                selectedID = nil
                page = nil
            }
        } message: {
            Text(String(localized: "Its actions and the rules that open it are removed too. A backup of the previous file is kept."))
        }
    }

    // MARK: Cards

    private var introCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.l) {
                Image(systemName: "safari")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Brand.violet)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(
                        title: String(localized: "Action compass"),
                        subtitle: String(localized: "Up to eight actions around the pointer. Hold a key or a mouse button, move towards an action and let go: it runs at once, without looking.")
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "Wait a moment and the compass shows its actions; the highlighted one runs when you let go."),
                              systemImage: "hand.point.up.left")
                        Label(String(localized: "Tap the key instead of holding it to keep the compass open, then click, press 1 to 8 or Esc."),
                              systemImage: "hand.tap")
                        Label(String(localized: "Each app can have its own actions; the others stay the same everywhere."),
                              systemImage: "app.badge")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "No compass yet"),
                              subtitle: String(localized: "Start with a ready-made one and change it as you like."))
                HStack {
                    Button(String(localized: "Create Compass")) { create(template: CompassTemplates.everyday) }
                        .buttonStyle(.borderedProminent)
                    Button(String(localized: "Create Empty Compass")) { create(template: nil) }
                }
            }
        }
    }

    private func compassCard(_ compass: CompassDraft) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    if compasses.count > 1 {
                        Picker(String(localized: "Compass"), selection: Binding(
                            get: { compass.id }, set: { selectedID = $0; page = nil }
                        )) {
                            ForEach(compasses) { Text($0.name).tag($0.id) }
                        }
                        .fixedSize()
                    } else {
                        Text(compass.name).font(.title3.weight(.semibold))
                    }
                    Menu {
                        Button(String(localized: "Rename…")) {
                            newName = compass.name
                            renaming = true
                        }
                        Button(String(localized: "New Compass")) { create(template: nil) }
                        Divider()
                        Button(String(localized: "Delete…"), role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button(String(localized: "Try It")) { model.openCompass(compass.id) }
                        .disabled(!model.isTapRunning)
                        .help(model.isTapRunning
                              ? String(localized: "Opens the compass at the pointer. Move towards an action and click, or press Esc.")
                              : String(localized: "Turn on Clavimo first."))
                }
                pagePicker(compass)
                rose(compass)
                Text(page == nil
                     ? String(localized: "Click a direction to choose its action. Drag one direction onto another to swap them.")
                     : String(localized: "Dimmed actions come from the page used everywhere. Click to change them in this app only, or hide them here."))
                    .formFooterStyle()
            }
        }
    }

    private func pagePicker(_ compass: CompassDraft) -> some View {
        HStack {
            Picker(String(localized: "Page"), selection: $page) {
                Text(String(localized: "Everywhere")).tag(String?.none)
                ForEach(compass.appOrder, id: \.self) { app in
                    Text(AppNames.name(app)).tag(Optional(app))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Menu(String(localized: "Add App Page")) {
                ForEach(runningApps.filter { compass.apps[$0.id] == nil }, id: \.id) { app in
                    Button(app.name) { addPage(app.id, to: compass) }
                }
                Divider()
                Button(String(localized: "Other App…")) { chooseOtherApp(for: compass) }
            }
            .fixedSize()
            if let page {
                Button(String(localized: "Remove Page"), role: .destructive) {
                    var updated = compass
                    updated.removePage(page)
                    self.page = nil
                    errorMessage = editor.upsertCompass(updated)
                }
            }
        }
    }

    /// A 3 × 3 grid: eight directions around the centre.
    private func rose(_ compass: CompassDraft) -> some View {
        let rows: [[CompassDirection?]] = [[.upLeft, .up, .upRight], [.left, nil, .right], [.downLeft, .down, .downRight]]
        return Grid(horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        if let direction = rows[row][column] {
                            tile(direction, in: compass)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "safari").font(.title2).foregroundStyle(Brand.violet)
                                Text(page.map(AppNames.name) ?? String(localized: "Everywhere"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 86)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ direction: CompassDirection, in compass: CompassDraft) -> some View {
        let own = compass.page(page)[direction]
        let inherited = page == nil ? nil : compass.slots[direction]
        let shown = own ?? inherited
        return Button {
            editingSlot = SlotEditing(direction: direction, slot: own ?? inherited ?? CompassSlotDraft(), isNew: own == nil)
        } label: {
            VStack(spacing: 6) {
                HStack {
                    Text(verbatim: "\(direction.number)").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: arrow(direction)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let shown {
                    Image(systemName: shown.symbol).font(.title3)
                    Text(shown.title).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                    Text(String(localized: "Add action")).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(own != nil ? Brand.violet.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .opacity(own == nil && inherited != nil ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(direction.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let other = items.first.flatMap(CompassDirection.init(rawValue:)), other != direction else { return false }
            var updated = compass
            updated.swap(other, direction, page: page)
            errorMessage = editor.upsertCompass(updated)
            return true
        }
        .contextMenu {
            if own != nil {
                Button(String(localized: "Remove"), role: .destructive) { setSlot(nil, direction, in: compass) }
            }
            if page != nil, inherited != nil, own?.hidden != true {
                Button(String(localized: "Hide in This App")) {
                    var hidden = CompassSlotDraft()
                    hidden.hidden = true
                    setSlot(hidden, direction, in: compass)
                }
            }
        }
        .accessibilityLabel(String(localized: "\(direction.number): \(shown?.title ?? String(localized: "Add action"))"))
    }

    private func triggersCard(_ compass: CompassDraft) -> some View {
        let rules = editor.rulesOpening(compass.id)
        return Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Open with"),
                              subtitle: String(localized: "Any key, mouse button or trackpad gesture can open the compass. Keys and buttons work best: hold, move, let go."))
                ForEach(rules, id: \.id) { rule in
                    HStack {
                        Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle").foregroundStyle(rule.enabled ? .green : .secondary)
                        Text(rule.name)
                        Spacer()
                        Button(String(localized: "Edit")) { edit(rule) }
                        Button(String(localized: "Remove"), role: .destructive) { errorMessage = editor.delete(id: rule.id) }
                    }
                }
                if rules.isEmpty {
                    Text(String(localized: "Nothing opens this compass yet. Choose one of these:"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(String(localized: "Hold a Key…")) { newKeyTrigger(compass) }
                    Button(String(localized: "Mouse Button…")) { newRuleTrigger(compass, kind: .modifierClick) }
                    Button(String(localized: "Trackpad Gesture…")) { newRuleTrigger(compass, kind: .trackpadGesture) }
                }
            }
        }
    }

    private func settingsCard(_ compass: CompassDraft) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Behavior"))
                LabeledContent(String(localized: "Show actions after")) {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(compass.hintDelayMilliseconds) },
                            set: { value in update(compass) { $0.hintDelayMilliseconds = Int(value / 50) * 50 } }
                        ), in: 0...1000)
                        Text("\(compass.hintDelayMilliseconds) ms").monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                }
                LabeledContent(String(localized: "Move at least")) {
                    HStack {
                        Slider(value: Binding(
                            get: { compass.deadZone },
                            set: { value in update(compass) { $0.deadZone = (value / 5).rounded() * 5 } }
                        ), in: 20...120)
                        Text(String(localized: "\(Int(compass.deadZone)) pt")).monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                }
                Toggle(String(localized: "Put the pointer back after an action"), isOn: Binding(
                    get: { compass.returnPointer }, set: { value in update(compass) { $0.returnPointer = value } }
                ))
                Text(String(localized: "Experienced hands pick before the actions appear. A shorter distance is faster, a longer one avoids picking by accident."))
                    .formFooterStyle()
            }
        }
    }

    private func templatesCard(_ compass: CompassDraft) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Templates"),
                              subtitle: String(localized: "Fill the page used everywhere, or add pages for apps. You can change everything afterwards."))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: Spacing.m)], spacing: Spacing.m) {
                    ForEach(CompassTemplates.all) { template in
                        Button {
                            var updated = compass
                            template.apply(to: &updated)
                            errorMessage = editor.upsertCompass(updated)
                            if let first = template.apps.first { page = first }
                        } label: {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                Image(systemName: template.symbol).font(.title3).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title).font(.callout.weight(.semibold))
                                    Text(template.summary).font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func create(template: CompassTemplate?) {
        let name = compasses.isEmpty ? String(localized: "Main") : String(localized: "Compass \(compasses.count + 1)")
        var draft = CompassDraft(id: editor.newCompassID(from: compasses.isEmpty ? "main" : name), name: name)
        template?.apply(to: &draft)
        errorMessage = editor.upsertCompass(draft)
        if errorMessage == nil {
            selectedID = draft.id
            page = nil
        }
    }

    private func update(_ compass: CompassDraft, _ change: (inout CompassDraft) -> Void) {
        var updated = compass
        change(&updated)
        guard updated != compass else { return }
        errorMessage = editor.upsertCompass(updated)
    }

    private func setSlot(_ slot: CompassSlotDraft?, _ direction: CompassDirection, in compass: CompassDraft) {
        update(compass) { $0.setSlot(slot, at: direction, page: page) }
    }

    private func addPage(_ app: String, to compass: CompassDraft) {
        update(compass) { $0.addPage(app) }
        page = app
    }

    private func chooseOtherApp(for compass: CompassDraft) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        addPage(id, to: compass)
    }

    private var activeProfile: String { editor.document?.activeProfileId ?? "default" }

    private func newKeyTrigger(_ compass: CompassDraft) {
        var draft = KeyboardRuleDraft(kind: .keyOutput)
        draft.profileID = activeProfile
        draft.output = OutputDraft.of(.compass)
        draft.output.action.compassID = compass.id
        draft.name = String(localized: "Open \(compass.name)")
        editingKey = KeyEditing(ruleID: nil, draft: draft)
    }

    private func newRuleTrigger(_ compass: CompassDraft, kind: RuleDraft.Kind) {
        var draft = RuleDraft()
        draft.kind = kind
        draft.profileID = activeProfile
        draft.action = .openCompass
        draft.compassID = compass.id
        if kind == .modifierClick {
            draft.modifiers = []
            draft.button = 4
        } else {
            draft.gesture = .tap
            draft.fingers = 4
        }
        editingRule = RuleEditing(ruleID: nil, draft: draft)
    }

    private func edit(_ rule: ConfigDocument.Rule) {
        if let draft = RuleDraft(rule: rule) {
            editingRule = RuleEditing(ruleID: rule.id, draft: draft)
        } else if let draft = KeyboardRuleDraft(rule: rule) {
            editingKey = KeyEditing(ruleID: rule.id, draft: draft)
        }
    }

    private func arrow(_ direction: CompassDirection) -> String {
        switch direction {
        case .up: "arrow.up"
        case .upRight: "arrow.up.right"
        case .right: "arrow.right"
        case .downRight: "arrow.down.right"
        case .down: "arrow.down"
        case .downLeft: "arrow.down.left"
        case .left: "arrow.left"
        case .upLeft: "arrow.up.left"
        }
    }
}

/// Edits the action in one direction of a compass page.
struct CompassSlotEditor: View {
    @Bindable var model: AgentController
    @State var slot: CompassSlotDraft
    let direction: CompassDirection
    let isNew: Bool
    let onAppPage: Bool
    let compassID: String
    /// Returns an error message, or nil when saved. Nil removes the slot.
    let save: (CompassSlotDraft?) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: $slot.name, prompt: Text(slot.actionTitle))
                    if onAppPage {
                        Toggle(String(localized: "Hide this direction in this app"), isOn: $slot.hidden)
                    }
                } header: {
                    Text(String(localized: "Direction \(direction.number)"))
                } footer: {
                    Text(String(localized: "The name is shown on the compass. Leave it empty to show what the action does."))
                        .formFooterStyle()
                }
                if !slot.hidden {
                    Section(String(localized: "Action")) {
                        if let raw = slot.raw {
                            Text(String(localized: "This action was written by hand (\(raw["kind"]?.string ?? "?")). Choose another one to replace it."))
                                .foregroundStyle(.secondary)
                            Button(String(localized: "Replace")) { slot.raw = nil }
                        } else {
                            ActionFields(draft: Binding(get: { slot.action.ruleDraft }, set: { slot.action = ActionChoice($0) }),
                                         model: model, excludedCompass: compassID)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let message = errorMessage ?? slot.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !isNew {
                    Button(String(localized: "Remove"), role: .destructive) {
                        if let error = save(nil) { errorMessage = error } else { dismiss() }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "Add") : String(localized: "Save")) {
                    if let error = save(slot) { errorMessage = error } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(slot.validationMessage != nil)
            }
            .padding(12)
        }
        .frame(width: 520, height: 460)
    }
}
