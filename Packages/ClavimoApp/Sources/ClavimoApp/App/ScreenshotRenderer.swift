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
    static func run(outputDirectory: URL) -> Int32 {
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
        swap.name = "Swap Command and Option (right)"
        var fnLeft = RuleDraft()
        fnLeft.kind = .modifierClick
        fnLeft.name = "Fn + left click: previous Space"
        fnLeft.button = 1
        fnLeft.action = .previousWorkspace
        var fnRight = fnLeft
        fnRight.name = "Fn + right click: next Space"
        fnRight.button = 2
        fnRight.action = .nextWorkspace
        var mission = RuleDraft()
        mission.kind = .modifierClick
        mission.name = "Fn + side button: Mission Control"
        mission.button = 4
        mission.action = .missionControl
        var chord = RuleDraft()
        chord.kind = .keyClick
        chord.name = "Hold F + side button: next Space"
        chord.firstKey = KeyCode.f.rawValue
        chord.button = 4
        chord.exceptApps = ["com.apple.Terminal"]
        var wheel = RuleDraft()
        wheel.kind = .wheel
        wheel.name = "Mouse wheel"
        wheel.vertical.mode = .byLines
        wheel.vertical.lines = 3

        let rules = [swap, fnLeft, fnRight, mission, chord].enumerated().map { index, draft in
            draft.makeRule(id: "sample-\(index)", order: index)
        }
        return ConfigDocument(engine: .init(enabledOnLaunch: true), rules: rules,
                              deviceSettings: [wheel.makeDeviceSetting(id: "sample-wheel")])
    }
}
