import AppKit
import ClavimoCore
import SwiftUI

/// A small panel near the bottom of the screen that shows the active
/// layer, pending one-shot modifiers and, while a key sequence runs, the
/// keys that can come next. It never takes focus or clicks.
@MainActor
final class KeyboardOverlayPanel {
    static let preferenceKey = "showKeyboardOverlay"

    private var panel: NSPanel?
    private var hosting: NSHostingView<KeyboardOverlayView>?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    func show(_ overlay: KeyboardOverlay) {
        guard Self.isEnabled, !overlay.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let view = KeyboardOverlayView(overlay: overlay)
        let panel = panel ?? makePanel(view)
        hosting?.rootView = view
        let size = hosting?.fittingSize ?? CGSize(width: 240, height: 60)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.minY + 72, width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel(_ view: KeyboardOverlayView) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }
}

struct KeyboardOverlayView: View {
    let overlay: KeyboardOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(overlay.layers, id: \.self) { layer in
                    chip(String(localized: "Layer \(layer)"), symbol: "square.3.layers.3d")
                }
                if !overlay.oneShot.isEmpty {
                    chip(String(localized: "\(overlay.oneShot.symbols) next key"), symbol: "hand.point.up")
                }
                if let sequence = overlay.sequence {
                    chip(sequence.isEmpty ? String(localized: "Sequence") : sequence.map { KeyNames.name(for: $0.rawValue) }.joined(separator: " "),
                         symbol: "arrow.right.to.line")
                }
            }
            if overlay.sequence != nil, !overlay.sequenceOptions.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(Array(overlay.sequenceOptions.prefix(12).enumerated()), id: \.offset) { _, option in
                        GridRow {
                            Text(option.keys.map { KeyNames.name(for: $0.rawValue) }.joined(separator: " "))
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                            Text(option.output.localizedTitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(String(localized: "Esc cancels")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.18), in: Capsule())
    }
}

extension ModifierSet {
    /// ⌃⌥⇧⌘ symbols, left and right alike.
    var symbols: String {
        let generic = self.generic
        return [(GenericModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { generic.contains($0.0) }.map(\.1).joined()
    }
}

extension KeyOutput {
    var localizedTitle: String {
        switch self {
        case let .key(code, modifiers):
            ModifierSet(leftSideOf: modifiers).symbols + KeyNames.name(for: code.rawValue)
        case let .modifiers(set):
            set == .hyper ? String(localized: "Hyper (⌃⌥⇧⌘)") : set.symbols
        case let .layer(name):
            String(localized: "Layer \(name)")
        case let .toggleLayer(name):
            String(localized: "Switch layer \(name)")
        case let .oneShot(set):
            String(localized: "\(set.symbols) for the next key")
        case .startSequence:
            String(localized: "Key sequence")
        case let .action(action):
            action.localizedTitle
        case .none:
            String(localized: "Nothing")
        }
    }
}

extension ActionCommand {
    var localizedTitle: String {
        switch self {
        case .nextWorkspace: String(localized: "Next Space")
        case .previousWorkspace: String(localized: "Previous Space")
        case .missionControl: String(localized: "Mission Control")
        case .applicationWindows: String(localized: "Application Windows")
        case let .shortcut(key, modifiers): ModifierSet(leftSideOf: modifiers).symbols + KeyNames.name(for: key.rawValue)
        case let .click(button): KeyNames.buttonName(button.userFacingNumber)
        case let .launchApp(bundleID): String(localized: "Open \(AppNames.name(bundleID))")
        case let .media(key): key.localizedTitle
        case .toggleCapsLock: String(localized: "Caps Lock")
        }
    }
}
