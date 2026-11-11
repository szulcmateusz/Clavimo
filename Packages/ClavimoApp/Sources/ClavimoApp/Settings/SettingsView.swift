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
        case overview, rules, mouse, devices, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .rules: String(localized: "Rules")
            case .mouse: String(localized: "Mouse & Scrolling")
            case .devices: String(localized: "Devices")
            case .general: String(localized: "General")
            case .about: String(localized: "About")
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.33percent"
            case .rules: "list.bullet.rectangle.portrait"
            case .mouse: "computermouse"
            case .devices: "keyboard"
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
    @State private var navigation = SettingsNavigation()

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    ForEach([SettingsNavigation.Pane.overview, .rules, .mouse, .devices]) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
                Section {
                    ForEach([SettingsNavigation.Pane.general, .about]) { pane in
                        Label(pane.title, systemImage: pane.symbol).tag(pane)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch navigation.pane ?? .overview {
            case .overview: OverviewPane(model: model, editor: editor, navigation: navigation)
            case .rules: RulesPane(model: model, editor: editor, navigation: navigation)
            case .mouse: MousePane(editor: editor)
            case .devices: DevicesPane(navigation: navigation)
            case .general: GeneralPane(model: model, editor: editor)
            case .about: AboutPane()
            }
        }
        .tint(Brand.violet)
        .frame(minWidth: 820, minHeight: 540)
    }
}
