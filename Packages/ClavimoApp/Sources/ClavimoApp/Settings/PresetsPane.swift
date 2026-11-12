import AppKit
import ClavimoCore
import SwiftUI

/// Ready-made setups, the easiest way to start: each one lists exactly what
/// it changes, switches on in one click and off again in one click.
struct PresetsPane: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    let navigation: SettingsNavigation
    @State private var hardware = Hardware()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(
                            title: String(localized: "Ready-made setups"),
                            subtitle: String(localized: "Switch on what suits you. Every change can be adjusted later, and a whole setup switches off in one click.")
                        )
                        if let summary = hardware.summary {
                            Label(summary, systemImage: "cable.connector")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(Presets.ordered(for: hardware)) { preset in
                    PresetCard(preset: preset, editor: editor, hardware: hardware) { pane in
                        navigation.pane = pane
                    }
                }
            }
            .padding(Spacing.xl)
        }
        .navigationTitle(String(localized: "Ready-made setups"))
        .onAppear { hardware = Hardware.current() }
    }
}

/// One preset with its items, a switch for each, and what happened after
/// it was applied.
struct PresetCard: View {
    let preset: Preset
    @Bindable var editor: ConfigEditor
    let hardware: Hardware
    /// Opens the pane where the preset's rules can be adjusted.
    var open: ((SettingsNavigation.Pane) -> Void)?
    /// A short version for the Overview.
    var compact = false

    @State private var chosen: Set<String>?
    @State private var outcome: Outcome?
    @State private var errorMessage: String?

    private struct Outcome {
        let message: String
        let skipped: [(title: String, reason: String)]
        let previous: ConfigDocument
    }

    private var document: ConfigDocument? { editor.document }
    private var applied: Set<String> { document.map { PresetEngine.appliedItems(preset, in: $0) } ?? [] }

    private func unavailable(_ item: PresetItem) -> String? {
        guard let document else { return nil }
        return item.unavailable(hardware, document)
    }

    /// Items switched on by default: suitable, possible and not on yet.
    private var defaultChoice: Set<String> {
        Set(preset.items.filter { $0.defaultOn(hardware) && unavailable($0) == nil && !applied.contains($0.id) }.map(\.id))
    }

    private var selection: Set<String> { chosen ?? defaultChoice }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                if let note = preset.note(hardware) {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if compact {
                    Text(preset.items.filter { $0.defaultOn(hardware) }.map(\.title).joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(preset.items) { item in row(item) }
                    }
                }
                if let outcome { result(outcome) }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                buttons
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: preset.symbol)
                .font(.title2)
                .foregroundStyle(Brand.violet)
                .frame(width: 44, height: 44)
                .background(Brand.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.s) {
                    Text(preset.title).font(.title3.weight(.semibold))
                    if !applied.isEmpty {
                        StatusChip(text: String(localized: "On: \(applied.count) of \(preset.items.count)"), kind: .active)
                    } else if preset.fits(hardware) {
                        StatusChip(text: String(localized: "Fits your hardware"), kind: .info)
                    }
                }
                Text(preset.audience).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: PresetItem) -> some View {
        let isOn = applied.contains(item.id)
        let reason = isOn ? nil : unavailable(item)
        return HStack(alignment: .top, spacing: Spacing.s) {
            if isOn {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 20)
            } else {
                Toggle(item.title, isOn: Binding(
                    get: { selection.contains(item.id) },
                    set: { value in
                        var updated = selection
                        if value { updated.insert(item.id) } else { updated.remove(item.id) }
                        chosen = updated
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(reason != nil)
                .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).fontWeight(.medium)
                Text(item.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            .opacity(reason != nil ? 0.6 : 1)
            .accessibilityElement(children: .combine)
        }
    }

    private func result(_ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(outcome.message, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
                Button(String(localized: "Undo")) {
                    if let error = editor.replace(with: outcome.previous) {
                        errorMessage = error
                    } else {
                        self.outcome = nil
                        chosen = nil
                    }
                }
            }
            ForEach(outcome.skipped, id: \.title) { skipped in
                Text(String(localized: "Left out: \(skipped.title). \(skipped.reason)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var buttons: some View {
        let toAdd = selection.subtracting(applied)
        return HStack {
            if applied.isEmpty {
                Button(String(localized: "Switch On")) { apply(toAdd) }
                    .buttonStyle(.borderedProminent)
                    .disabled(toAdd.isEmpty)
            } else {
                if !toAdd.isEmpty, !compact {
                    Button(String(localized: "Add Selected")) { apply(toAdd) }
                        .buttonStyle(.borderedProminent)
                }
                Button(String(localized: "Switch Off"), role: .destructive) { switchOff() }
            }
            Spacer()
            if let open, !applied.isEmpty, let pane = adjustPane {
                Button(String(localized: "Adjust…")) { open(pane) }
            } else if compact, let open {
                Button(String(localized: "Details…")) { open(.presets) }
            }
        }
    }

    /// Where the preset's rules live in the settings.
    private var adjustPane: SettingsNavigation.Pane? {
        switch preset.id {
        case "trackpad": .trackpad
        case "mouse": applied.contains("compass") ? .compass : .rules
        case "developer": .keyboard
        default: .rules
        }
    }

    private func titles(_ ids: [String]) -> String {
        preset.items.filter { ids.contains($0.id) }.map(\.title).joined(separator: ", ")
    }

    private func apply(_ items: Set<String>) {
        guard let before = document else { return }
        let result = PresetEngine.apply(preset, items: items, to: before, hardware: hardware)
        let skipped = result.skipped.compactMap { skipped in
            preset.items.first { $0.id == skipped.item }.map { (title: $0.title, reason: skipped.reason) }
        }
        guard !result.applied.isEmpty else {
            outcome = nil
            errorMessage = skipped.isEmpty ? nil : String(localized: "Nothing was switched on. \(skipped.map { "\($0.title): \($0.reason)" }.joined(separator: " "))")
            return
        }
        if let error = editor.replace(with: result.document) {
            errorMessage = error
            return
        }
        errorMessage = nil
        chosen = nil
        outcome = Outcome(
            message: String(localized: "Switched on: \(titles(result.applied))."),
            skipped: skipped, previous: before
        )
    }

    private func switchOff() {
        guard let before = document else { return }
        if let error = editor.replace(with: PresetEngine.remove(preset, from: before)) {
            errorMessage = error
            return
        }
        errorMessage = nil
        chosen = nil
        outcome = Outcome(message: String(localized: "Switched off."), skipped: [], previous: before)
    }
}

extension Hardware {
    /// What was found, in one line, or nil when nothing is known.
    var summary: String? {
        var parts: [String] = []
        if hasTrackpad { parts.append(String(localized: "a trackpad")) }
        if hasMouse { parts.append(hasLogitech ? String(localized: "a Logitech mouse") : String(localized: "a mouse")) }
        if !pcKeyboards.isEmpty { parts.append(String(localized: "a PC keyboard")) }
        guard !parts.isEmpty else { return nil }
        var text = String(localized: "Connected: \(parts.formatted(.list(type: .and))).")
        if !otherApps.isEmpty {
            text += " " + String(localized: "Also running: \(otherApps.formatted(.list(type: .and))).")
        }
        return text
    }
}
