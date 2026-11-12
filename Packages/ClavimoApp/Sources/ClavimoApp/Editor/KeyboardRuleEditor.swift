import ClavimoCore
import ClavimoQuartz
import SwiftUI

/// Edits a tap-hold key, a key output, a layer key, a combo or a sequence.
struct KeyboardRuleEditor: View {
    @Bindable var model: AgentController
    @State var draft: KeyboardRuleDraft
    let isNew: Bool
    /// Layer names already used, offered in the layer fields.
    let layers: [String]
    /// Returns an error message, or nil when the rule was saved.
    let save: (KeyboardRuleDraft) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var inputSources = InputSources.enabled()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(String(localized: "Rule type"), selection: $draft.kind) {
                        ForEach(KeyboardRuleDraft.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    TextField(String(localized: "Name"), text: $draft.name, prompt: Text(draft.suggestedName))
                }
                triggerSection
                outputSections
                if draft.kind == .tapHold { timingSection }
                conditionsSection
                Section {
                    Toggle(String(localized: "Enabled"), isOn: $draft.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let message = errorMessage ?? draft.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "Add Rule") : String(localized: "Save")) {
                    if let error = save(draft) { errorMessage = error } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage != nil)
            }
            .padding(12)
        }
        .frame(width: 600, height: 700)
    }

    // MARK: Sections

    @ViewBuilder
    private var triggerSection: some View {
        Section {
            switch draft.kind {
            case .tapHold, .keyOutput:
                KeyField(title: String(localized: "Key"), code: $draft.key, model: model)
            case .layerKey:
                LayerField(name: $draft.layer, layers: layers)
                KeyField(title: String(localized: "Key"), code: $draft.key, model: model)
            case .combo, .sequence:
                KeyListField(keys: $draft.keys, model: model, limit: draft.kind == .combo ? ComboRule.keyCount.upperBound : SequenceRule.keyCount.upperBound)
                if draft.kind == .combo {
                    Stepper(String(localized: "Press together within \(draft.windowMilliseconds) ms"),
                            value: $draft.windowMilliseconds, in: ComboRule.windowRange, step: 10)
                }
            }
        } header: {
            Text(String(localized: "When"))
        } footer: {
            Text(triggerFooter).formFooterStyle()
        }
    }

    private var triggerFooter: String {
        switch draft.kind {
        case .tapHold:
            String(localized: "A short press does one thing and holding the key does another. Letter keys can become modifiers (home row modifiers); Caps Lock can become Hyper.")
        case .keyOutput:
            String(localized: "Pressing the key does something else: a shortcut, modifiers, a layer, an action or nothing.")
        case .layerKey:
            String(localized: "While the layer is on, the key does this instead. Keys not on the layer keep working as usual.")
        case .combo:
            String(localized: "Pressing the keys at the same moment does something else. Each key is held back for this long while you type, so keep it short.")
        case .sequence:
            String(localized: "After the leader key, type these keys one after another. A panel shows the keys that can come next; Esc cancels.")
        }
    }

    @ViewBuilder
    private var outputSections: some View {
        if draft.kind == .tapHold {
            OutputSection(title: String(localized: "When tapped"), output: $draft.output, model: model, layers: layers, allowed: tapKinds)
            if KeyCode(draft.key).modifierKey == nil {
                OutputSection(title: String(localized: "When held"), output: $draft.hold, model: model, layers: layers,
                              allowed: [.modifiers, .holdLayer, .key, .shortcut, .compass])
                Section {
                    Toggle(String(localized: "Double tap does something else"), isOn: $draft.doubleTapEnabled)
                    if draft.doubleTapEnabled {
                        OutputFields(output: $draft.doubleTap, model: model, layers: layers, allowed: tapKinds)
                    }
                } footer: {
                    if draft.doubleTapEnabled {
                        Text(String(localized: "A single tap then waits briefly to see whether a second one follows.")).formFooterStyle()
                    }
                }
            } else {
                Section {
                    Text(String(localized: "Held, the key stays \(KeyNames.name(for: draft.key)). The tap output runs when you press and release it alone."))
                        .foregroundStyle(.secondary)
                }
                .onAppear { draft.hold = ownModifierHold }
            }
        } else {
            OutputSection(title: String(localized: "Then"), output: $draft.output, model: model, layers: layers,
                          allowed: draft.kind == .keyOutput ? OutputDraft.Kind.allCases : tapKinds)
        }
    }

    private var tapKinds: [OutputDraft.Kind] {
        [.key, .shortcut, .action, .compass, .oneShot, .toggleLayer, .startSequence, .capsLock, .none]
    }

    private var ownModifierHold: OutputDraft {
        guard let modifier = KeyCode(draft.key).modifierKey else { return draft.hold }
        let generic: RuleDraft.Modifier = switch modifier {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        case .leftCommand, .rightCommand: .command
        }
        return .modifiers([generic])
    }

    private var timingSection: some View {
        Section {
            LabeledContent(String(localized: "Hold after")) {
                HStack {
                    Slider(value: Binding(get: { Double(draft.holdAfterMilliseconds) },
                                          set: { draft.holdAfterMilliseconds = Int($0 / 10) * 10 }),
                           in: 120...500)
                    Text("\(draft.holdAfterMilliseconds) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
            }
            Picker(String(localized: "Another key pressed meanwhile"), selection: $draft.interrupt) {
                Text(String(localized: "Means hold")).tag(TapHoldSettings.Interrupt.holdOnOtherKey)
                Text(String(localized: "Means hold once that key is released")).tag(TapHoldSettings.Interrupt.permissive)
                Text(String(localized: "Waits for the time")).tag(TapHoldSettings.Interrupt.timeOnly)
            }
            Toggle(String(localized: "A key of the same hand means tap"), isOn: $draft.oppositeHandsOnly)
            Toggle(String(localized: "Tap at once while typing"), isOn: Binding(
                get: { draft.typingStreakMilliseconds > 0 },
                set: { draft.typingStreakMilliseconds = $0 ? TapHoldSettings.homeRow.typingStreakMilliseconds : 0 }
            ))
        } header: {
            Text(String(localized: "Timing"))
        } footer: {
            Text(String(localized: "For letter keys, use \"once that key is released\", a key of the same hand means tap, and tap at once while typing: fast typing then never triggers a modifier. For Caps Lock or Space, \"means hold\" feels the most direct."))
                .formFooterStyle()
        }
    }

    private var conditionsSection: some View {
        Section {
            AppListEditor(title: String(localized: "Only in apps"), apps: $draft.onlyApps, limit: nil)
            AppListEditor(title: String(localized: "Not in apps"), apps: $draft.exceptApps, limit: nil)
            if inputSources.count > 1 || !draft.inputSources.isEmpty {
                DisclosureGroup(draft.inputSources.isEmpty
                    ? String(localized: "Input sources (all)")
                    : String(localized: "Input sources (\(draft.inputSources.count))")) {
                    ForEach(inputSources) { source in
                        Toggle(source.name, isOn: Binding(
                            get: { draft.inputSources.contains(source.id) },
                            set: { on in
                                if on { draft.inputSources.append(source.id) } else { draft.inputSources.removeAll { $0 == source.id } }
                            }
                        ))
                    }
                }
            }
        } header: {
            Text(String(localized: "Conditions"))
        } footer: {
            Text(String(localized: "Leave everything empty to apply the rule everywhere.")).formFooterStyle()
        }
    }
}

/// One output with its own header.
private struct OutputSection: View {
    let title: String
    @Binding var output: OutputDraft
    let model: AgentController
    let layers: [String]
    let allowed: [OutputDraft.Kind]

    var body: some View {
        Section {
            OutputFields(output: $output, model: model, layers: layers, allowed: allowed)
        } header: {
            Text(title)
        }
    }
}

/// Chooses what a keyboard rule produces.
struct OutputFields: View {
    @Binding var output: OutputDraft
    let model: AgentController
    let layers: [String]
    let allowed: [OutputDraft.Kind]

    var body: some View {
        Picker(String(localized: "Output"), selection: $output.kind) {
            ForEach(allowed) { Text($0.title).tag($0) }
        }
        switch output.kind {
        case .key:
            KeyField(title: String(localized: "Key"), code: $output.key, model: model)
        case .shortcut:
            KeyField(title: String(localized: "Key"), code: $output.key, model: model)
            ModifierToggles(title: String(localized: "With"), selection: $output.modifiers, choices: [.control, .option, .shift, .command])
        case .modifiers, .oneShot:
            ModifierToggles(title: String(localized: "Modifiers"), selection: Binding(
                get: { output.modifiers },
                set: { output.modifiers = $0.subtracting([.function]); output.sideNames = nil }
            ), choices: [.control, .option, .shift, .command])
            Button(String(localized: "Use Hyper (⌃⌥⇧⌘)")) {
                output.modifiers = OutputDraft.hyper
                output.sideNames = nil
            }
        case .holdLayer, .toggleLayer:
            LayerField(name: $output.layer, layers: layers)
        case .action:
            ActionFields(draft: Binding(get: { output.action.ruleDraft }, set: { output.action = ActionChoice($0) }), model: model)
        case .compass:
            CompassPicker(compassID: $output.action.compassID, model: model)
        case .startSequence, .capsLock, .none:
            EmptyView()
        }
    }
}

/// A layer name with the names already in use.
struct LayerField: View {
    @Binding var name: String
    let layers: [String]

    var body: some View {
        LabeledContent(String(localized: "Layer")) {
            HStack {
                TextField(String(localized: "Layer"), text: $name, prompt: Text(verbatim: "nav"))
                    .labelsHidden()
                if !layers.isEmpty {
                    Menu(String(localized: "Existing")) {
                        ForEach(layers, id: \.self) { layer in Button(layer) { name = layer } }
                    }
                    .fixedSize()
                }
            }
        }
    }
}

/// Several keys, each recorded or picked, for combos and sequences.
struct KeyListField: View {
    @Binding var keys: [UInt16]
    let model: AgentController
    let limit: Int

    var body: some View {
        ForEach(keys.indices, id: \.self) { index in
            HStack {
                KeyField(title: String(localized: "Key \(index + 1)"), code: Binding(
                    get: { index < keys.count ? keys[index] : 0 },
                    set: { if index < keys.count { keys[index] = $0 } }
                ), model: model)
                if keys.count > 1 {
                    Button { keys.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Remove key"))
                }
            }
        }
        if keys.count < limit {
            Button(String(localized: "Add Key")) { keys.append(0x00) }
        }
    }
}
