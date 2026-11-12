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
        if !panel.isVisible {
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            panel.alphaValue = reduce ? 1 : 0
            panel.orderFrontRegardless()
            if !reduce {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
        } else {
            panel.orderFrontRegardless()
        }
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

/// A dark glass ring of eight segments around a quiet centre. The
/// highlighted segment is what a release, a click or Return runs; its name
/// is shown large in the middle. Numbers pick a segment directly.
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

    static let size: CGFloat = 420
    static let outer: CGFloat = 172
    static let inner: CGFloat = 70
    /// Where icons and labels sit, between the inner and outer edge.
    static let labelRadius: CGFloat = 122

    let model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Violet near the centre, turning mint towards the rim, like the logo.
    private var accent: RadialGradient {
        RadialGradient(colors: [Color(red: 0.43, green: 0.33, blue: 0.93), Brand.violet, Brand.mint.opacity(0.95)],
                       center: .center, startRadius: Self.inner, endRadius: Self.outer)
    }

    var body: some View {
        ZStack {
            base
            ForEach(CompassDirection.allCases, id: \.self) { direction in
                segment(direction)
            }
            centre
        }
        .frame(width: Self.size, height: Self.size)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78), value: model.highlighted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.title)
    }

    private var base: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(RadialGradient(colors: [Brand.nightTop.opacity(0.92), Brand.nightBottom.opacity(0.96)],
                                     center: .center, startRadius: Self.inner, endRadius: Self.outer))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .frame(width: Self.outer * 2, height: Self.outer * 2)
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .shadow(color: Brand.violet.opacity(0.25), radius: 40)
    }

    @ViewBuilder
    private func segment(_ direction: CompassDirection) -> some View {
        let tile = model.tiles[direction]
        let isOn = model.highlighted == direction && tile != nil
        let shape = RingSector(centre: direction.degrees, inner: Self.inner + 6, outer: Self.outer - 6)
        ZStack {
            shape
                .fill(isOn ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(tile == nil ? 0.015 : 0.055)))
                .overlay(shape.stroke(Color.white.opacity(isOn ? 0.45 : 0.07), lineWidth: 1))
                .shadow(color: isOn ? Brand.violet.opacity(0.75) : .clear, radius: 16)
            if let tile {
                VStack(spacing: 5) {
                    icon(tile)
                        .frame(width: 26, height: 26)
                    Text(tile.title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 76)
                        .opacity(isOn ? 1 : 0.82)
                }
                .foregroundStyle(.white)
                .offset(offset(direction, radius: Self.labelRadius))
                Text(verbatim: "\(direction.number)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(isOn ? 0.85 : 0.35))
                    .offset(offset(direction, radius: Self.outer - 16, turn: -16))
            }
        }
        .scaleEffect(isOn && !reduceMotion ? 1.045 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tile.map { "\(direction.number): \($0.title)" } ?? String()))
        .accessibilityHidden(tile == nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var centre: some View {
        let highlighted = model.highlighted.flatMap { model.tiles[$0] }
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: (Self.inner - 4) * 2, height: (Self.inner - 4) * 2)
            if let direction = model.highlighted, highlighted != nil {
                Needle()
                    .fill(Brand.mint)
                    .frame(width: 12, height: 8)
                    .rotationEffect(.degrees(90 - direction.degrees))
                    .offset(offset(direction, radius: Self.inner - 1))
                    .shadow(color: Brand.mint.opacity(0.8), radius: 6)
            }
            VStack(spacing: 3) {
                Text(model.appName.map { "\(model.title) · \($0)" } ?? model.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                if let highlighted {
                    Text(highlighted.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else if model.tiles.isEmpty {
                    Text(String(localized: "No actions yet. Add them in Settings > Compass."))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                } else {
                    Text(model.held ? String(localized: "Move towards an action") : String(localized: "Click, number or Esc"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: (Self.inner - 14) * 2)
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
                .font(.system(size: 19, weight: .medium))
        }
    }

    /// `turn` moves the point along the ring, in degrees counterclockwise.
    private func offset(_ direction: CompassDirection, radius: CGFloat, turn: Double = 0) -> CGSize {
        let angle = (direction.degrees + turn) * .pi / 180
        // SwiftUI's y grows downwards.
        return CGSize(width: cos(angle) * radius, height: -sin(angle) * radius)
    }
}

/// One eighth of a ring, centred on a direction (degrees counterclockwise
/// from the right, as in mathematics).
struct RingSector: Shape {
    var centre: Double
    var inner: CGFloat
    var outer: CGFloat
    var gap: Double = 1.2

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Screen angles grow clockwise because y points down.
        let start = Angle.degrees(-(centre + 22.5 - gap))
        let end = Angle.degrees(-(centre - 22.5 + gap))
        var path = Path()
        path.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A small triangle pointing up, rotated towards the highlighted segment.
struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
