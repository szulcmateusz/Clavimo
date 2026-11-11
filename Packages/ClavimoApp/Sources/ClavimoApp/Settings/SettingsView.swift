import AppKit
import ClavimoCore
import ClavimoQuartz
import SwiftUI

/// Which pane the settings window shows, shared so one pane can send the
/// user to another (for example Overview > New Rule).
@MainActor
@Observable
final class SettingsNavigation {
    enum Pane: String, CaseIterable, Identifiable {
        case overview, rules, keyboard, mouse, trackpad, devices, diagnostics, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .rules: String(localized: "Rules")
            case .keyboard: String(localized: "Keyboard")
            case .mouse: String(localized: "Mouse & Scrolling")
            case .trackpad: String(localized: "Trackpad")
            case .devices: String(localized: "Devices")
            case .diagnostics: String(localized: "Diagnostics")
            case .general: String(localized: "General")
            case .about: String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.33percent"
            case .rules: "list.bullet.rectangle.portrait"
            case .keyboard: "keyboard.badge.ellipsis"
            case .mouse: "computermouse"
            case .trackpad: "rectangle.and.hand.point.up.left"
            case .devices: "keyboard"
            case .diagnostics: "waveform.path.ecg"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    var pane: Pane? = .overview
    /// A rule to open in the editor, set when another pane asks for it.
    var ruleToCreate: RuleDraft?

    func createRule(_ draft: RuleDraft = RuleDraft()) {
        pane = .rules
        ruleToCreate = draft
    }
}

struct SettingsView: View {
    @Bindable var model: AgentController
    @Bindable var editor: ConfigEditor
    @State private var navigation: SettingsNavigation

    init(model: AgentController, editor: ConfigEditor, initialPane: SettingsNavigation.Pane = .overview) {
        self.model = model
        self.editor = editor
        let navigation = SettingsNavigation()
        navigation.pane = initialPane
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    ForEach([SettingsNavigation.Pane.overview, .rules, .mouse, .trackpad, .devices]) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
                Section {
                    ForEach([SettingsNavigation.Pane.diagnostics, .general, .about]) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch navigation.pane ?? .overview {
            case .overview: OverviewPane(model: model, editor: editor, navigation: navigation)
            case .rules: RulesPane(model: model, editor: editor, navigation: navigation)
            case .keyboard: KeyboardPane(model: model, editor: editor)
            case .mouse: MousePane(editor: editor)
            case .trackpad: TrackpadPane(model: model, editor: editor)
            case .devices: DevicesPane(navigation: navigation)
            case .diagnostics: DiagnosticsPane(model: model)
            case .general: GeneralPane(model: model, editor: editor)
            case .about: AboutPane()
            }
        }
        .tint(Brand.violet)
        .frame(minWidth: 820, minHeight: 540)
    }
}
