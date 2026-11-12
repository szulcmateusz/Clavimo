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
        // The window is larger than the ring so its glow fades out inside it;
        // only the ring itself has to stay on screen.
        var centre = point
        if let visible = screen?.visibleFrame {
            let half = CompassView.outer + 6
            centre.x = min(max(centre.x, visible.minX + half), visible.maxX - half)
            centre.y = min(max(centre.y, visible.minY + half), visible.maxY - half)
        }
        let frame = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
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
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
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

    /// Room around the ring for its shadow and glow to fade out completely.
    static let size: CGFloat = 560
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
            if model.tiles.isEmpty {
                RingSector(start: 0, end: 360, inner: Self.inner + 6, outer: Self.outer - 6, gap: 0)
                    .fill(Color.white.opacity(0.03))
            }
            ForEach(Self.zones(for: Array(model.tiles.keys)), id: \.direction) { zone in
                segment(zone)
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
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .shadow(color: Brand.violet.opacity(0.22), radius: 30)
    }

    @ViewBuilder
    private func segment(_ zone: Zone) -> some View {
        let direction = zone.direction
        let tile = model.tiles[direction]
        let isOn = model.highlighted == direction && tile != nil
        let shape = RingSector(start: zone.start, end: zone.end, inner: Self.inner + 6, outer: Self.outer - 6,
                               gap: zone.end - zone.start >= 359 ? 0 : 1.2)
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
                        .minimumScaleFactor(0.75)
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

    /// The part of the ring that picks one direction: from halfway to the
    /// previous defined direction to halfway to the next one, the same rule
    /// `CompassGeometry` uses. Two actions get half the ring each.
    struct Zone {
        let direction: CompassDirection
        let start: Double
        let end: Double
    }

    nonisolated static func zones(for defined: [CompassDirection]) -> [Zone] {
        let sorted = defined.sorted { $0.degrees < $1.degrees }
        guard sorted.count > 1 else {
            return sorted.map { Zone(direction: $0, start: $0.degrees - 180, end: $0.degrees + 180) }
        }
        return sorted.indices.map { index in
            let direction = sorted[index]
            var below = direction.degrees - sorted[(index + sorted.count - 1) % sorted.count].degrees
            if below <= 0 { below += 360 }
            var above = sorted[(index + 1) % sorted.count].degrees - direction.degrees
            if above <= 0 { above += 360 }
            return Zone(direction: direction, start: direction.degrees - below / 2, end: direction.degrees + above / 2)
        }
    }

    /// `turn` moves the point along the ring, in degrees counterclockwise.
    private func offset(_ direction: CompassDirection, radius: CGFloat, turn: Double = 0) -> CGSize {
        let angle = (direction.degrees + turn) * .pi / 180
        // SwiftUI's y grows downwards.
        return CGSize(width: cos(angle) * radius, height: -sin(angle) * radius)
    }
}

/// A part of a ring between two angles (degrees counterclockwise from the
/// right, as in mathematics).
struct RingSector: Shape {
    /// Degrees counterclockwise from the right; `end` is after `start`.
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var gap: Double = 1.2

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Screen angles grow clockwise because y points down.
        let from = Angle.degrees(-(end - gap))
        let to = Angle.degrees(-(start + gap))
        var path = Path()
        path.addArc(center: c, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: to, endAngle: from, clockwise: true)
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
