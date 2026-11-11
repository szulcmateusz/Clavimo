import AppKit
import ClavimoCore
import SwiftUI

/// Renders the settings panes with a sample configuration to PNG files,
/// for reviewing the interface and for documentation screenshots. It uses
/// the app's real views in an offscreen window, so no screen recording
/// permission is needed and the user's own configuration is not touched.
///
///   Clavimo --render-screenshots <output-dir>
@MainActor
enum ScreenshotRenderer {
    /// True while rendering: live touch input is replaced by sample fingers.
    static var isRendering = false

    static func run(outputDirectory: URL) -> Int32 {
        isRendering = true
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let sampleFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("clavimo-screenshots-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("config.json")
            try FileManager.default.createDirectory(at: sampleFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sampleDocument().encoded().write(to: sampleFile)
            let store = ConfigStore(fileURL: sampleFile)
            let agent = AgentController(store: store)
            agent.loadForPreview()
            let editor = ConfigEditor(store: store)

            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                for pane in SettingsNavigation.Pane.allCases {
                    let view = SettingsView(model: agent, editor: editor, initialPane: pane)
                    try render(view, size: NSSize(width: 980, height: 660), appearance: appearance,
                               to: outputDirectory.appendingPathComponent("\(pane.rawValue)-\(suffix).png"))
                }
                if let draft = editor.rows.first(where: { $0.draft?.kind == .keyClick })?.draft {
                    let sheet = RuleEditorView(model: agent, draft: draft, isNew: false) { _ in nil }
                    try render(sheet, size: NSSize(width: 600, height: 680), appearance: appearance,
                               to: outputDirectory.appendingPathComponent("editor-\(suffix).png"))
                }
                if let draft = editor.rows.first(where: { $0.id == KeyboardPane.capsLockRuleID })?.keyboard {
                    let sheet = KeyboardRuleEditor(model: agent, draft: draft, isNew: false, layers: ["nav"]) { _ in nil }
                    try render(sheet, size: NSSize(width: 600, height: 700), appearance: appearance,
                               to: outputDirectory.appendingPathComponent("editor-keyboard-\(suffix).png"))
                }
                if let draft = editor.rows.first(where: { $0.draft?.kind == .trackpadGesture && $0.draft?.gesture == .swipe })?.draft {
                    let sheet = RuleEditorView(model: agent, draft: draft, isNew: false) { _ in nil }
                    try render(sheet, size: NSSize(width: 600, height: 680), appearance: appearance,
                               to: outputDirectory.appendingPathComponent("editor-trackpad-\(suffix).png"))
                }
            }
            for step in OnboardingView.Step.allCases {
                let view = OnboardingPreview(agent: agent, editor: editor, step: step)
                try render(view, size: NSSize(width: 640, height: 560), appearance: .aqua,
                           to: outputDirectory.appendingPathComponent("onboarding-\(step.rawValue + 1).png"))
            }
            print("Rendered screenshots to \(outputDirectory.path)")
            return 0
        } catch {
            print("Rendering failed: \(error)")
            return 1
        }
    }

    private static func render(_ view: some View, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.layoutIfNeeded()
        // Let SwiftUI finish layout and asynchronous updates before drawing.
        for _ in 0..<6 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// A realistic configuration that shows every rule type.
    static func sampleDocument() -> ConfigDocument {
        var swap = RuleDraft()
        var fnLeft = RuleDraft()
        fnLeft.kind = .modifierClick
        fnLeft.button = 1
        fnLeft.action = .previousWorkspace
        var fnRight = fnLeft
        fnRight.button = 2
        fnRight.action = .nextWorkspace
        var mission = RuleDraft()
        mission.kind = .modifierClick
        mission.button = 4
        mission.action = .missionControl
        var chord = RuleDraft()
        chord.kind = .keyClick
        chord.firstKey = KeyCode.g.rawValue
        chord.button = 4
        chord.exceptApps = ["com.apple.Terminal"]
        var wheel = RuleDraft()
        wheel.kind = .wheel
        wheel.vertical.mode = .byLines
        wheel.vertical.lines = 3

        var tap = RuleDraft()
        tap.kind = .trackpadGesture
        tap.fingers = 3
        tap.action = .middleClick
        var back = RuleDraft()
        back.kind = .trackpadGesture
        back.gesture = .swipe
        back.direction = .left
        back.trackpadModifiers = [.function]
        back.action = .backClick
        var corner = RuleDraft()
        corner.kind = .trackpadClick
        corner.clickPlace = .corner
        corner.corner = .topRight
        corner.action = .shortcut
        corner.shortcutKey = 0x0D
        corner.shortcutModifiers = [.command]
        var trackpadScroll = RuleDraft()
        trackpadScroll.kind = .trackpadScroll
        trackpadScroll.trackpadScroll = TrackpadScrollSettings(speed: 1.25, momentum: true)

        var rules = [swap, fnLeft, fnRight, mission, chord, tap, back, corner].enumerated().map { index, draft in
            draft.makeRule(id: "sample-\(index)", order: index)
        }
        var caps = KeyboardRuleDraft()
        caps.doubleTapEnabled = true
        caps.name = String(localized: "Caps Lock: \(KeyboardPane.CapsPreset.hyperEscape.title)")
        rules.append(caps.makeRule(id: KeyboardPane.capsLockRuleID, order: rules.count))
        let order = KeyboardPane.HomeRowOrder.commandOptionControlShift.modifiers
        for (key, modifier) in zip(KeyboardPane.leftHomeRow + KeyboardPane.rightHomeRow, order + order) {
            let draft = KeyboardRuleDraft.homeRow(key: key, modifier: modifier, holdAfter: 220, profileID: "default")
            rules.append(draft.makeRule(id: KeyboardPane.homeRowPrefix + "\(key)", order: rules.count))
        }
        for (index, draft) in (KeyboardTemplates.navigation.drafts + KeyboardTemplates.escapeCombo.drafts).enumerated() {
            rules.append(draft.makeRule(id: "sample-keyboard-\(index)", order: rules.count))
        }
        return ConfigDocument(engine: .init(enabledOnLaunch: true), rules: rules,
                              deviceSettings: [wheel.makeDeviceSetting(id: "sample-wheel"),
                                               trackpadScroll.makeDeviceSetting(id: "sample-trackpad")])
    }
}
