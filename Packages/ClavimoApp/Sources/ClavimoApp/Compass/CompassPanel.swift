import AppKit
import ClavimoCore
import SwiftUI

/// A borderless panel centred on the pointer. It never takes focus or
/// clicks: the event tap decides what keys and clicks do while it is open.
@MainActor
final class CompassPanel {
    private var panel: NSPanel?
    private var hosting: NSHostingView<CompassView>?

    func show(_ model: CompassView.Model, at point: CGPoint) {
        let view = CompassView(model: model)
        let panel = panel ?? makePanel(view)
        hosting?.rootView = view
        let size = CGSize(width: CompassView.size, height: CompassView.size)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var frame = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(_ view: CompassView) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }
}

/// Eight tiles around a quiet centre. The highlighted tile is what a
/// release, a click or Return runs; numbers pick a tile directly.
struct CompassView: View {
    struct Tile: Hashable {
        var title: String
        var symbol: String
        var appBundleID: String?
    }

    struct Model {
        var title: String
        var appName: String?
        var tiles: [CompassDirection: Tile]
        var highlighted: CompassDirection?
        var held: Bool
    }

    static let size: CGFloat = 460
    /// Far enough apart that diagonal neighbours never overlap.
    static let radius: CGFloat = 156

    let model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                .frame(width: Self.radius * 2 + 120, height: Self.radius * 2 + 120)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            centre
            ForEach(CompassDirection.allCases, id: \.self) { direction in
                slot(direction)
                    .offset(offset(for: direction))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8), value: model.highlighted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }

    private var centre: some View {
        VStack(spacing: 3) {
            Image(systemName: "safari")
                .font(.system(size: 18, weight: .semibold))
                .rotationEffect(.degrees(model.highlighted.map { 90 - $0.degrees } ?? 0))
                .foregroundStyle(model.highlighted == nil ? .secondary : Color.accentColor)
            Text(model.title).font(.caption.weight(.semibold)).lineLimit(1)
            if let appName = model.appName {
                Text(appName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.tiles.isEmpty {
                Text(String(localized: "No actions yet. Add them in Settings > Compass."))
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if !model.held {
                Text(String(localized: "Click, number or Esc"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 112)
        .padding(10)
        .background(Circle().fill(.black.opacity(0.18)))
    }

    @ViewBuilder
    private func slot(_ direction: CompassDirection) -> some View {
        if let tile = model.tiles[direction] {
            let isOn = model.highlighted == direction
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    icon(tile)
                        .frame(width: 34, height: 34)
                    Text(verbatim: "\(direction.number)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .background(Circle().fill(.background.opacity(0.8)))
                        .offset(x: 10, y: -8)
                }
                Text(tile.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07))
            )
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .scaleEffect(isOn && !reduceMotion ? 1.12 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        } else {
            Circle().fill(Color.primary.opacity(0.12)).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private func icon(_ tile: Tile) -> some View {
        if let bundleID = tile.appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: tile.symbol)
                .font(.system(size: 20, weight: .medium))
        }
    }

    private func offset(for direction: CompassDirection) -> CGSize {
        let angle = direction.degrees * .pi / 180
        // SwiftUI's y grows downwards.
        return CGSize(width: cos(angle) * Self.radius, height: -sin(angle) * Self.radius)
    }
}
