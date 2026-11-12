import AppKit
import ClavimoCore
import Foundation

/// Shows an action compass and decides what it runs.
///
/// The engine says when a compass opens and when its trigger is released;
/// this controller knows where the pointer is. It reads the pointer
/// position only while a compass is open, a few dozen times a second, keeps
/// it in memory only, and forgets it when the compass closes. The event tap
/// itself never sees pointer movement.
@MainActor
final class CompassController {
    /// What the controller needs from the rest of the app.
    struct Environment {
        /// Runs an action off the main thread.
        var run: (ActionCommand) -> Void
        /// Tells the engine the compass is done, so keys work normally.
        var close: () -> Void
        /// Opens a compass in the engine without a trigger.
        var begin: (String) -> Void
    }

    private struct Session {
        let compass: CompassDefinition
        let slots: [CompassDirection: CompassSlot]
        let appName: String?
        /// Where the pointer was when the compass opened (AppKit coordinates).
        let origin: CGPoint
        /// Whether the pointer goes back to `origin` after a pick.
        let returnsPointer: Bool
        var held: Bool
        let openedAt: Date
        var lastMove: Date
        var lastPoint: CGPoint
        var highlighted: CompassDirection?
        var panelShown: Bool
    }

    /// A tap shorter than this, without movement, keeps the compass open
    /// as a panel; a longer hold without movement cancels.
    static let tapSeconds: TimeInterval = 0.35
    /// A panel without pointer movement closes after this long.
    static let idleSeconds: TimeInterval = 8

    var compasses: [String: CompassDefinition] = [:]
    var environment: Environment?

    private let panel = CompassPanel()
    private var session: Session?
    private var timer: Timer?

    var isOpen: Bool { session != nil }

    func handle(_ signal: CompassSignal) {
        switch signal {
        case let .open(id, held):
            open(id, held: held, at: NSEvent.mouseLocation)
        case .release:
            released()
        case let .pick(direction):
            guard let session, let slot = session.slots[direction] else {
                dismiss(closeEngine: false)
                return
            }
            perform(slot, from: session)
        case .confirm:
            update()
            guard let session, let direction = session.highlighted, let slot = session.slots[direction] else {
                dismiss(closeEngine: false)
                return
            }
            perform(slot, from: session)
        case .cancel:
            dismiss(closeEngine: false)
        }
    }

    /// Opens a compass from the menu bar or settings as a panel: at the
    /// pointer, or in the middle of its screen when the pointer is in the
    /// menu bar.
    func openPanel(_ id: String, centred: Bool) {
        guard compasses[id] != nil else { return }
        if session != nil { dismiss(closeEngine: true) }
        environment?.begin(id)
        var origin = NSEvent.mouseLocation
        if centred, let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            origin = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        }
        open(id, held: false, at: origin, returnsPointer: false)
    }

    /// Closes everything, e.g. when input handling stops.
    func reset() {
        timer?.invalidate()
        timer = nil
        panel.hide()
        session = nil
    }

    // MARK: - Session

    private func open(_ id: String, held: Bool, at origin: CGPoint, returnsPointer: Bool = true) {
        guard let compass = compasses[id] else {
            environment?.close()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        let slots = compass.slots(forApp: app?.bundleIdentifier)
        let hasPage = app?.bundleIdentifier.map { compass.apps[$0] != nil } ?? false
        let now = Date()
        session = Session(
            compass: compass, slots: slots, appName: hasPage ? app?.localizedName : nil, origin: origin,
            returnsPointer: returnsPointer && compass.returnPointer, held: held, openedAt: now, lastMove: now, lastPoint: origin, highlighted: nil,
            panelShown: false
        )
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A panel opened without a held trigger shows at once; a held one
        // waits, so a quick flick never flashes it.
        if !held || compass.hintDelayMilliseconds == 0 || slots.isEmpty { showPanel() }
    }

    private func update() {
        guard var current = session else { return }
        let point = NSEvent.mouseLocation
        let now = Date()
        if point != current.lastPoint {
            current.lastPoint = point
            current.lastMove = now
        }
        current.highlighted = CompassGeometry.direction(
            dx: point.x - current.origin.x, dy: point.y - current.origin.y,
            among: Set(current.slots.keys), deadZone: current.compass.deadZone
        )
        let highlightChanged = current.highlighted != session?.highlighted
        session = current
        if !current.panelShown, now.timeIntervalSince(current.openedAt) * 1000 >= Double(current.compass.hintDelayMilliseconds) {
            showPanel()
        } else if current.panelShown, highlightChanged {
            refreshPanel(announce: true)
        }
        if !current.held, now.timeIntervalSince(current.lastMove) >= Self.idleSeconds {
            dismiss(closeEngine: true)
        }
    }

    private func released() {
        update()
        guard var current = session else { return }
        if let direction = current.highlighted, let slot = current.slots[direction] {
            perform(slot, from: current)
        } else if Date().timeIntervalSince(current.openedAt) < Self.tapSeconds || current.slots.isEmpty {
            // A tap: keep it open as a panel to pick with a click or a number.
            current.held = false
            current.lastMove = Date()
            session = current
            showPanel()
        } else {
            // Released in the middle after holding: nothing was chosen.
            dismiss(closeEngine: true)
        }
    }

    private func perform(_ slot: CompassSlot, from current: Session) {
        dismiss(closeEngine: true)
        if current.returnsPointer, current.lastPoint != current.origin {
            Self.movePointer(to: current.origin)
        }
        guard case let .action(action) = slot.action else { return }
        if case let .openCompass(id) = action {
            environment?.begin(id)
            open(id, held: false, at: current.origin, returnsPointer: current.returnsPointer)
        } else {
            environment?.run(action)
        }
    }

    private func dismiss(closeEngine: Bool) {
        timer?.invalidate()
        timer = nil
        panel.hide()
        session = nil
        if closeEngine { environment?.close() }
    }

    // MARK: - Panel

    private func showPanel() {
        guard var current = session else { return }
        current.panelShown = true
        session = current
        refreshPanel(announce: false)
    }

    private func refreshPanel(announce: Bool) {
        guard let current = session, current.panelShown else { return }
        panel.show(CompassView.Model(
            title: current.compass.name, appName: current.appName,
            tiles: current.slots.mapValues { tile(for: $0) },
            highlighted: current.highlighted, held: current.held
        ), at: current.origin)
        if announce, NSWorkspace.shared.isVoiceOverEnabled, let direction = current.highlighted,
           let slot = current.slots[direction] {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: slot.title, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    func tile(for slot: CompassSlot) -> CompassView.Tile {
        guard case let .action(action) = slot.action else {
            return CompassView.Tile(title: slot.title, symbol: "circle.slash", appBundleID: nil)
        }
        var title = slot.title
        if slot.name.isEmpty, case let .openCompass(id) = action, let name = compasses[id]?.name {
            title = name
        }
        var bundleID: String?
        if case let .launchApp(id) = action { bundleID = id }
        return CompassView.Tile(title: title, symbol: action.symbol, appBundleID: bundleID)
    }

    /// Puts the pointer back where it was, so a pick never loses your place.
    private static func movePointer(to point: CGPoint) {
        // Quartz uses a top-left origin on the primary screen.
        let height = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: height - point.y))
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

extension CompassSlot {
    /// The slot's own name, or what its action does.
    var title: String {
        if !name.isEmpty { return name }
        switch action {
        case let .action(action): return action.localizedTitle
        case .none: return String(localized: "Nothing")
        }
    }
}
