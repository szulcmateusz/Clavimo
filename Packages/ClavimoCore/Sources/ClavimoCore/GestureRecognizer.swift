/// A trackpad gesture recognized from touch frames.
public enum GestureEvent: Equatable, Hashable, Sendable {
    /// Several fingers touched down together and lifted quickly without
    /// moving.
    case tap(fingers: Int)
    /// One finger rests while another taps beside it.
    case tipTap(Side)
    /// Three or more fingers moved together in one direction.
    case swipe(fingers: Int, Direction)

    public enum Side: String, CaseIterable, Sendable { case left, right }
    public enum Direction: String, CaseIterable, Sendable { case up, down, left, right }
}

/// A corner of the trackpad surface.
public enum TrackpadCorner: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// What is on the trackpad right now, used to interpret physical clicks.
public struct TouchSnapshot: Equatable, Sendable {
    /// Fingers currently pressing on the surface.
    public var fingers: Int
    /// The corner the only finger rests in, if exactly one finger is down
    /// in a corner.
    public var corner: TrackpadCorner?
    /// The corner of a one-finger tap that just ended, for tap to click:
    /// macOS reports that click after the finger has lifted.
    public var tappedCorner: TrackpadCorner?

    public init(fingers: Int = 0, corner: TrackpadCorner? = nil, tappedCorner: TrackpadCorner? = nil) {
        self.fingers = fingers
        self.corner = corner
        self.tappedCorner = tappedCorner
    }

    public static let empty = TouchSnapshot()
}

/// Thresholds for gesture recognition, in seconds and normalized
/// trackpad units (the surface is 1 × 1).
public struct GestureTuning: Equatable, Sendable {
    /// A tap must end within this time after the first finger landed.
    public var maximumTapDuration = 0.35
    /// Fingers of a multi-finger tap must all land within this time.
    public var landingWindow = 0.15
    /// A tapping finger may move at most this far.
    public var maximumTapMovement: Float = 0.05
    /// A tip tap's resting finger must have been down this long.
    public var minimumAnchorTime = 0.12
    /// Centroid distance that makes a swipe.
    public var swipeDistance: Float = 0.12
    /// A swipe must cover `swipeDistance` within this time, so slow
    /// three-finger drags are not swipes.
    public var maximumSwipeDuration = 0.6
    /// The dominant axis must be at least this many times the other.
    public var swipeAxisRatio: Float = 2
    /// Size of the corner regions.
    public var cornerSize: Float = 0.2
    /// How long a finished one-finger tap counts for tap to click.
    public var tappedCornerLifetime = 0.4

    public init() {}

    public static let standard = GestureTuning()
}

/// Turns touch frames from one trackpad into gestures. Deterministic and
/// time-driven by frame timestamps, so it is fully testable. One gesture
/// is reported per touch session at most, except tip taps, which repeat
/// while the resting finger stays down.
public struct GestureRecognizer: Sendable {
    private struct Track: Sendable {
        var start: Point
        var last: Point
        var downAt: Double

        var movement: Float { start.distance(to: last) }
    }

    private struct Session: Sendable {
        var startedAt: Double
        var peak = 0
        var peakReachedAt: Double
        var everMoved = false
        var fired = false
        var swipeBase: Point?
        var swipeBaseCount = 0
        var swipeBaseTime = 0.0
    }

    public let tuning: GestureTuning
    private var tracks: [Int32: Track] = [:]
    private var session: Session?
    private var lastTap: (corner: TrackpadCorner?, at: Double)?
    public private(set) var snapshot = TouchSnapshot.empty

    public init(tuning: GestureTuning = .standard) {
        self.tuning = tuning
    }

    public var isIdle: Bool { tracks.isEmpty && session == nil }

    /// Forgets every finger, e.g. after the device was restarted.
    public mutating func reset() {
        tracks = [:]
        session = nil
        lastTap = nil
        snapshot = .empty
    }

    public mutating func process(_ frame: TouchFrame) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let now = frame.time
        let down = Dictionary(frame.down.map { ($0.id, Point(x: $0.x, y: $0.y)) }, uniquingKeysWith: { first, _ in first })

        // Lifted fingers.
        for (id, track) in tracks where down[id] == nil {
            tracks[id] = nil
            if let tip = tipTap(lifted: track, at: now) { events.append(tip) }
        }
        // New and moving fingers.
        for (id, point) in down {
            if var track = tracks[id] {
                track.last = point
                tracks[id] = track
            } else {
                tracks[id] = Track(start: point, last: point, downAt: now)
                if session == nil { session = Session(startedAt: now, peakReachedAt: now) }
            }
        }

        if var current = session {
            if tracks.count > current.peak {
                current.peak = tracks.count
                current.peakReachedAt = now
            }
            if tracks.values.contains(where: { $0.movement > tuning.maximumTapMovement }) {
                current.everMoved = true
            }
            if !current.fired, let swipe = swipe(in: &current, at: now) {
                current.fired = true
                events.append(swipe)
            }
            if tracks.isEmpty {
                if let tap = endSession(current, at: now) { events.append(tap) }
                session = nil
            } else {
                session = current
            }
        }
        if events.contains(where: { if case .tipTap = $0 { true } else { false } }) {
            session?.fired = true
        }

        updateSnapshot(at: now)
        return events
    }

    // MARK: - Gestures

    private func tipTap(lifted track: Track, at now: Double) -> GestureEvent? {
        guard tracks.count == 1, let anchor = tracks.values.first,
              now - track.downAt <= tuning.maximumTapDuration,
              track.movement <= tuning.maximumTapMovement,
              track.downAt - anchor.downAt >= tuning.minimumAnchorTime,
              anchor.movement <= tuning.maximumTapMovement
        else { return nil }
        return .tipTap(track.last.x < anchor.last.x ? .left : .right)
    }

    private func swipe(in session: inout Session, at now: Double) -> GestureEvent? {
        let count = tracks.count
        guard count >= 3 else {
            session.swipeBase = nil
            return nil
        }
        let centroid = Point.centroid(tracks.values.map(\.last))
        guard let base = session.swipeBase, session.swipeBaseCount == count,
              now - session.swipeBaseTime <= tuning.maximumSwipeDuration
        else {
            session.swipeBase = centroid
            session.swipeBaseCount = count
            session.swipeBaseTime = now
            return nil
        }
        let dx = centroid.x - base.x
        let dy = centroid.y - base.y
        guard (dx * dx + dy * dy).squareRoot() >= tuning.swipeDistance else { return nil }
        if abs(dx) >= abs(dy) * tuning.swipeAxisRatio {
            return .swipe(fingers: count, dx > 0 ? .right : .left)
        }
        if abs(dy) >= abs(dx) * tuning.swipeAxisRatio {
            return .swipe(fingers: count, dy > 0 ? .up : .down)
        }
        return nil
    }

    private mutating func endSession(_ session: Session, at now: Double) -> GestureEvent? {
        let quick = now - session.startedAt <= tuning.maximumTapDuration
        let still = !session.everMoved
        if session.peak == 1 {
            lastTap = quick && still ? (corner(of: lastSingleFinger ?? Point(x: 0.5, y: 0.5)), now) : nil
            return nil
        }
        guard !session.fired, session.peak >= 2, quick, still,
              session.peakReachedAt - session.startedAt <= tuning.landingWindow
        else { return nil }
        return .tap(fingers: session.peak)
    }

    // MARK: - Snapshot

    private var lastSingleFinger: Point?

    private mutating func updateSnapshot(at now: Double) {
        if tracks.count == 1 { lastSingleFinger = tracks.values.first?.last }
        let corner = tracks.count == 1 ? tracks.values.first.flatMap { corner(of: $0.last) } : nil
        var tapped: TrackpadCorner?
        if let lastTap, now - lastTap.at <= tuning.tappedCornerLifetime, tracks.isEmpty {
            tapped = lastTap.corner
        }
        snapshot = TouchSnapshot(fingers: tracks.count, corner: corner, tappedCorner: tapped)
    }

    /// The corner containing `point`, with y growing upwards.
    private func corner(of point: Point) -> TrackpadCorner? {
        let left = point.x <= tuning.cornerSize
        let right = point.x >= 1 - tuning.cornerSize
        let bottom = point.y <= tuning.cornerSize
        let top = point.y >= 1 - tuning.cornerSize
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }
}

struct Point: Equatable, Sendable {
    var x: Float
    var y: Float

    func distance(to other: Point) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func centroid(_ points: [Point]) -> Point {
        guard !points.isEmpty else { return Point(x: 0, y: 0) }
        let count = Float(points.count)
        return Point(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    }
}
