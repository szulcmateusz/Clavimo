import SwiftUI

struct MousePane: View {
    @Bindable var editor: ConfigEditor
    @State private var draft = MousePane.defaultDraft
    @State private var savedDraft: RuleDraft?
    @State private var ruleID: String?
    @State private var errorMessage: String?
    @State private var accelerationEnabled = SystemChecks.pointerAccelerationEnabled

    static var defaultDraft: RuleDraft {
        var draft = RuleDraft()
        draft.kind = .wheel
        draft.enabled = false
        draft.vertical = RuleDraft.Axis()
        return draft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        HStack {
                            SectionHeader(title: String(localized: "Mouse wheel"),
                                          subtitle: String(localized: "Applies to every mouse wheel. Trackpad and Magic Mouse scrolling keep the system settings."))
                            Spacer()
                            Toggle(String(localized: "Custom scrolling"), isOn: $draft.enabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "Custom scrolling"))
                        }
                        if draft.enabled {
                            Divider()
                            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.m) {
                                GridRow {
                                    Text(String(localized: "Vertical")).font(.headline)
                                    Text(String(localized: "Horizontal")).font(.headline)
                                }
                                GridRow(alignment: .top) {
                                    AxisControls(axis: $draft.vertical)
                                    AxisControls(axis: $draft.horizontal)
                                }
                            }
                        }
                        HStack {
                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                            }
                            Spacer()
                            Button(String(localized: "Revert")) { load() }.disabled(!hasChanges)
                            Button(String(localized: "Apply")) { apply() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!hasChanges)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: String(localized: "Try it"), subtitle: String(localized: "Scroll here after applying to feel the result."))
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(1...200, id: \.self) { line in
                                    Text(String(localized: "Line \(line)")).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(Spacing.s)
                        }
                        .frame(height: 160)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Card {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Image(systemName: "cursorarrow.motionlines").font(.title2).foregroundStyle(Brand.violet).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                Text(String(localized: "Pointer acceleration")).font(.headline)
                                StatusChip(text: accelerationEnabled ? String(localized: "On") : String(localized: "Off"),
                                           kind: accelerationEnabled ? .info : .active)
                            }
                            Text(String(localized: "macOS sets pointer speed and acceleration for all mice. Turn acceleration off in Mouse > Advanced for movement that matches your hand exactly."))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(String(localized: "Open Mouse Settings")) { SystemSettingsLink.open(.mouse) }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Mouse & Scrolling"))
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accelerationEnabled = SystemChecks.pointerAccelerationEnabled
        }
    }

    private var hasChanges: Bool {
        if let savedDraft { return savedDraft != draft }
        return draft.enabled
    }

    private func load() {
        if let row = editor.rows.first(where: { $0.draft?.kind == .wheel }), let existing = row.draft {
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
        if !toSave.vertical.changesEvents && !toSave.horizontal.changesEvents {
            toSave.enabled = false
        }
        if !toSave.enabled, ruleID == nil {
            savedDraft = draft
            return
        }
        if !toSave.vertical.changesEvents && !toSave.horizontal.changesEvents, let ruleID {
            errorMessage = editor.delete(id: ruleID)
        } else {
            errorMessage = editor.upsert(toSave, id: ruleID)
        }
        if errorMessage == nil { load() }
    }
}

private struct AxisControls: View {
    @Binding var axis: RuleDraft.Axis

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle(String(localized: "Reverse direction"), isOn: $axis.reverse)
            Picker(String(localized: "Distance"), selection: $axis.mode) {
                ForEach(RuleDraft.Axis.Mode.allCases) { Text($0.localizedTitle).tag($0) }
            }
            .frame(maxWidth: 240)
            switch axis.mode {
            case .system:
                EmptyView()
            case .accelerated:
                HStack {
                    Slider(value: $axis.speed, in: 0.1...5, step: 0.1) { Text(String(localized: "Speed")) }
                    Text("\(axis.speed.formatted(.number.precision(.fractionLength(1))))×").monospacedDigit().frame(width: 40)
                }
                .frame(maxWidth: 260)
            case .byLines:
                Stepper(String(localized: "\(axis.lines) lines per notch"), value: $axis.lines, in: 1...30)
            case .byPixels:
                HStack {
                    Slider(value: $axis.pixels, in: 10...300, step: 5) { Text(String(localized: "Pixels")) }
                    Text("\(Int(axis.pixels)) px").monospacedDigit().frame(width: 52)
                }
                .frame(maxWidth: 260)
            case .smoothed:
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Slider(value: $axis.pixels, in: 10...300, step: 5) { Text(String(localized: "Distance")) }
                        Text("\(Int(axis.pixels)) px").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Slider(value: $axis.duration, in: 0.05...1.0, step: 0.05) { Text(String(localized: "Glide")) }
                        Text("\(Int(axis.duration * 1000)) ms").monospacedDigit().frame(width: 52)
                    }
                }
                .frame(maxWidth: 280)
            }
            Text(axis.mode.localizedExplanation).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension RuleDraft.Axis.Mode {
    var localizedTitle: String {
        switch self {
        case .system: String(localized: "System")
        case .accelerated: String(localized: "Accelerated")
        case .byLines: String(localized: "By lines")
        case .byPixels: String(localized: "By pixels")
        case .smoothed: String(localized: "Smooth")
        }
    }

    var localizedExplanation: String {
        switch self {
        case .system: String(localized: "Distance and acceleration as set in macOS.")
        case .accelerated: String(localized: "The macOS acceleration curve, faster or slower.")
        case .byLines: String(localized: "The same number of lines for every notch, without acceleration.")
        case .byPixels: String(localized: "The same distance for every notch, without acceleration. Experimental.")
        case .smoothed: String(localized: "Each notch glides a fixed distance over a short animation, like a trackpad. Moving the trackpad or pausing stops it.")
        }
    }
}
