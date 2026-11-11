import ClavimoCore
import ClavimoQuartz
import SwiftUI

struct TrackpadPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    @State private var preview = TouchPreview()
    @State private var editing: Editing?
    @State private var errorMessage: String?
    @State private var systemGestures = SystemTrackpadGestures.enabled()

    struct Editing: Identifiable {
        let id = UUID()
        let ruleID: String?
        let draft: RuleDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                statusCard
                TouchPreviewCard(preview: preview, rules: trackpadRows.compactMap(\.draft).filter(\.enabled))
                rulesCard
                templatesCard
                TrackpadScrollCard(editor: editor)
                if !conflicts.isEmpty { conflictsCard }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Trackpad"))
        .onAppear {
            preview.start()
            systemGestures = SystemTrackpadGestures.enabled()
        }
        .onDisappear { preview.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemGestures = SystemTrackpadGestures.enabled()
        }
        .sheet(item: $editing) { item in
            RuleEditorView(model: model, draft: item.draft, isNew: item.ruleID == nil) { draft in
                editor.upsert(draft, id: item.ruleID)
            }
        }
    }

    private var trackpadRows: [ConfigEditor.Row] {
        editor.rows.filter { $0.draft?.kind.isTrackpad == true }
    }

    private var conflicts: [(rule: String, gestures: [SystemTrackpadGestures.Gesture])] {
        trackpadRows.compactMap { row in
            guard let draft = row.draft, row.enabled else { return nil }
            let gestures = SystemTrackpadGestures.conflicts(with: draft.trackpadTrigger, enabled: systemGestures)
            return gestures.isEmpty ? nil : (row.name, gestures)
        }
    }

    // MARK: - Cards

    private var statusCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                TrackpadGlyph(model: TrackpadGlyphModel(.gesture(.tap(fingers: 3))), size: CGSize(width: 54, height: 38))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(String(localized: "Trackpad gestures")).font(.title3.weight(.semibold))
                        StatusChip(text: statusText, kind: statusKind)
                    }
                    Text(String(localized: "Taps, swipes and clicks with several fingers can run actions, also together with a held key. Clavimo reads finger positions through an unofficial macOS interface, only while a trackpad rule is on or this page is open, and never stores them. If a macOS update changes that interface, gestures turn themselves off and everything else keeps working."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusText: String {
        switch preview.status {
        case .running: String(localized: "Available")
        case .stopped: String(localized: "Off")
        case .unavailable(.noDevices): String(localized: "No trackpad")
        case .unavailable(.frameworkMissing), .unavailable(.dataLayoutChanged): String(localized: "Not available on this macOS")
        }
    }

    private var statusKind: StatusChip.Kind {
        switch preview.status {
        case .running: .active
        case .stopped: .off
        case .unavailable: .problem
        }
    }

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    SectionHeader(title: String(localized: "Your trackpad rules"),
                                  subtitle: trackpadRows.isEmpty ? String(localized: "None yet. Start with a template below.") : nil)
                    Spacer()
                    Button {
                        var draft = RuleDraft()
                        draft.kind = .trackpadGesture
                        draft.action = .middleClick
                        editing = Editing(ruleID: nil, draft: draft)
                    } label: { Label(String(localized: "New Rule"), systemImage: "plus") }
                }
                ForEach(trackpadRows) { row in
                    RuleRow(row: row, issue: model.unsupported.first { $0.ruleID == row.id },
                            engineActive: model.status == .active) { enabled in
                        errorMessage = editor.setEnabled(enabled, id: row.id)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if let draft = row.draft { editing = Editing(ruleID: row.id, draft: draft) } }
                    .contextMenu {
                        Button(String(localized: "Edit...")) { if let draft = row.draft { editing = Editing(ruleID: row.id, draft: draft) } }
                        Button(String(localized: "Delete"), role: .destructive) { errorMessage = editor.delete(id: row.id) }
                    }
                    .accessibilityAction(named: Text(String(localized: "Edit..."))) {
                        if let draft = row.draft { editing = Editing(ruleID: row.id, draft: draft) }
                    }
                    if row.id != trackpadRows.last?.id { Divider() }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
            }
        }
    }

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: String(localized: "Templates"),
                          subtitle: String(localized: "Pick one to open it in the editor; nothing changes until you add it."))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Spacing.m, alignment: .top)], spacing: Spacing.m) {
                ForEach(RuleTemplates.trackpad) { template in
                    Button { editing = Editing(ruleID: nil, draft: template.draft) } label: {
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text(template.title).font(.headline)
                                RuleTokensView(tokens: template.draft.tokens)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var conflictsCard: some View {
        Card {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(String(localized: "Some gestures are also used by macOS")).font(.headline)
                    ForEach(conflicts, id: \.rule) { conflict in
                        Text(String(localized: "\(conflict.rule): \(conflict.gestures.map(\.title).formatted(.list(type: .and)))"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text(String(localized: "Both actions happen, even while a key is held. Turn the macOS gesture off in Trackpad settings, or change the rule."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Open Trackpad Settings")) { SystemSettingsLink.open(.trackpad) }
                }
            }
        }
    }
}

// MARK: - Live preview

/// Shows the fingers on the trackpad and names recognized gestures, so
/// rules can be tried without guessing. Reads touches only while visible.
@MainActor
@Observable
final class TouchPreview {
    private(set) var contacts: [TouchContact] = []
    private(set) var lastGesture: GestureEvent?
    private(set) var lastGestureAt = Date.distantPast
    private(set) var status: TouchBackend.Status = .stopped
    private var subscription: TouchHub.Subscription?
    private var statusTimer: Timer?

    func start() {
        if ScreenshotRenderer.isRendering {
            contacts = [TouchContact(id: 1, state: .touching, x: 0.38, y: 0.42), TouchContact(id: 2, state: .touching, x: 0.5, y: 0.47),
                        TouchContact(id: 3, state: .touching, x: 0.62, y: 0.43)]
            lastGesture = .tap(fingers: 3)
            status = .running(devices: 1)
            return
        }
        guard subscription == nil else { return }
        let recognizer = PreviewRecognizer()
        subscription = TouchHub.shared.subscribe { [weak self] _, frame in
            let gestures = recognizer.process(frame)
            Task { @MainActor [weak self] in self?.update(frame: frame, gestures: gestures) }
        }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.status = TouchHub.shared.status }
        }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        statusTimer?.invalidate()
        statusTimer = nil
        contacts = []
    }

    private func update(frame: TouchFrame, gestures: [GestureEvent]) {
        contacts = frame.down
        if let gesture = gestures.last {
            lastGesture = gesture
            lastGestureAt = Date()
        }
        if case .stopped = status { status = TouchHub.shared.status }
    }
}

/// A recognizer used from the framework thread.
private final class PreviewRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizer = GestureRecognizer()

    func process(_ frame: TouchFrame) -> [GestureEvent] {
        lock.withLock { recognizer.process(frame) }
    }
}

private struct TouchPreviewCard: View {
    let preview: TouchPreview
    let rules: [RuleDraft]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Try it"),
                              subtitle: String(localized: "Put your fingers on the trackpad. Recognized gestures appear below, with the rule they run."))
                HStack(alignment: .center, spacing: Spacing.xl) {
                    TrackpadSurface(contacts: preview.contacts)
                        .frame(width: 260, height: 170)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(String(localized: "\(preview.contacts.count) fingers"))
                            .font(.title2.weight(.semibold).monospacedDigit())
                        if let gesture = preview.lastGesture {
                            Label(GestureNames.title(gesture), systemImage: "hand.tap")
                                .font(.headline)
                                .foregroundStyle(Brand.violet)
                                .id(preview.lastGestureAt)
                                .transition(.opacity)
                            Text(matchText(for: gesture)).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(String(localized: "No gesture yet.")).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func matchText(for gesture: GestureEvent) -> String {
        let matching = rules.filter { $0.kind == .trackpadGesture && $0.trackpadTrigger == .gesture(gesture) }
        guard let rule = matching.first else { return String(localized: "No rule uses this gesture.") }
        return rule.trackpadModifiers.isEmpty
            ? String(localized: "Runs: \(rule.actionTitle)")
            : String(localized: "Runs \(rule.actionTitle) while you hold \(rule.trackpadModifierText).")
    }
}

/// A large trackpad with the current fingers drawn where they touch.
struct TrackpadSurface: View {
    let contacts: [TouchContact]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let surface = Path(roundedRect: rect, cornerRadius: 16)
            context.fill(surface, with: .color(Brand.mint.opacity(0.08)))
            context.stroke(surface, with: .color(Brand.mint.opacity(0.7)), lineWidth: 1.5)
            for contact in contacts {
                // Touch coordinates grow upwards; the view grows downwards.
                let center = CGPoint(x: rect.minX + CGFloat(contact.x) * rect.width,
                                     y: rect.maxY - CGFloat(contact.y) * rect.height)
                let dot = CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -6, dy: -6)), with: .color(Brand.mint.opacity(0.18)))
                context.fill(Path(ellipseIn: dot), with: .color(Brand.mint))
            }
        }
        .accessibilityLabel(String(localized: "Trackpad with \(contacts.count) fingers"))
    }
}

// MARK: - Scrolling

private struct TrackpadScrollCard: View {
    @Bindable var editor: ConfigEditor
    @State private var draft = TrackpadScrollCard.defaultDraft
    @State private var savedDraft: RuleDraft?
    @State private var ruleID: String?
    @State private var errorMessage: String?

    static var defaultDraft: RuleDraft {
        var draft = RuleDraft()
        draft.kind = .trackpadScroll
        draft.trackpadScroll = .unchanged
        return draft
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: String(localized: "Trackpad scrolling"),
                              subtitle: String(localized: "Separate from the mouse wheel: macOS has one natural scrolling switch for both. Also applies to Magic Mouse."))
                Toggle(String(localized: "Reverse vertical scrolling"), isOn: $draft.trackpadScroll.reverseVertical)
                Toggle(String(localized: "Reverse horizontal scrolling"), isOn: $draft.trackpadScroll.reverseHorizontal)
                HStack {
                    Text(String(localized: "Speed"))
                    Slider(value: $draft.trackpadScroll.speed, in: TrackpadScrollSettings.speedRange, step: 0.25)
                        .frame(maxWidth: 240)
                    Text("\(draft.trackpadScroll.speed.formatted(.number.precision(.fractionLength(2))))×")
                        .monospacedDigit().frame(width: 52, alignment: .leading)
                }
                Toggle(String(localized: "Keep scrolling after lifting the fingers (momentum)"), isOn: $draft.trackpadScroll.momentum)
                HStack {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Spacer()
                    Button(String(localized: "Revert")) { load() }.disabled(!hasChanges)
                    Button(String(localized: "Apply")) { apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges)
                }
            }
        }
        .onAppear(perform: load)
    }

    private var hasChanges: Bool {
        if let savedDraft { return savedDraft != draft }
        return draft.trackpadScroll.changesEvents
    }

    private func load() {
        if let row = editor.rows.first(where: { $0.draft?.kind == .trackpadScroll }), let existing = row.draft {
            ruleID = row.id
            draft = existing
            savedDraft = existing
        } else {
            ruleID = nil
            draft = Self.defaultDraft
            savedDraft = nil
        }
        errorMessage = nil
    }

    private func apply() {
        var toSave = draft
        toSave.name = ""
        if !toSave.trackpadScroll.changesEvents {
            if let ruleID { errorMessage = editor.delete(id: ruleID) }
        } else {
            errorMessage = editor.upsert(toSave, id: ruleID)
        }
        if errorMessage == nil { load() }
    }
}
