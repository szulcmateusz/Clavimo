import Foundation

/// Turns discrete wheel notches into a short, smooth scroll animation.
///
/// Each notch adds `pixelsPerNotch` of distance to travel. Every frame the
/// scroller emits a fraction of the remaining distance (exponential
/// ease-out), so it settles in about `duration`. Pure and time-driven, so
/// it is fully testable; the platform adapter calls `step` from a timer.
///
/// Safety limits: the pending distance is capped, scrolling the other way
/// cancels the remaining movement immediately, and the animation always
/// ends after `maximumDuration` even if impulses keep arriving.
public struct SmoothScroller: Sendable {
    public struct Settings: Equatable, Hashable, Sendable {
        public var pixelsPerNotch: Double
        /// Time to cover about 95% of the distance, in seconds.
        public var duration: Double

        public init(pixelsPerNotch: Double, duration: Double) {
            self.pixelsPerNotch = pixelsPerNotch
            self.duration = duration
        }

        public static let pixelsRange: ClosedRange<Double> = 10...300
        public static let durationRange: ClosedRange<Double> = 0.05...1.0
        public static let standard = Settings(pixelsPerNotch: 60, duration: 0.25)

        var clamped: Settings {
            Settings(pixelsPerNotch: min(max(pixelsPerNotch, Self.pixelsRange.lowerBound), Self.pixelsRange.upperBound),
                     duration: min(max(duration, Self.durationRange.lowerBound), Self.durationRange.upperBound))
        }
    }

    public enum Phase: Equatable, Sendable {
        case began, changed, ended
    }

    public struct Frame: Equatable, Sendable {
        /// Pixels to scroll on this frame; positive is the wheel's
        /// natural "up/left" direction as reported by the event.
        public var vertical: Double
        public var horizontal: Double
        public var phase: Phase
    }

    /// The most distance that may be pending, in notches.
    public static let maximumPendingNotches = 25.0
    /// An animation never runs longer than this, in seconds.
    public static let maximumDuration = 3.0

    private var remaining = (vertical: 0.0, horizontal: 0.0)
    private var carry = (vertical: 0.0, horizontal: 0.0)
    private var lastStep: Double?
    private var startedAt: Double?
    private var settings = (vertical: Settings.standard, horizontal: Settings.standard)

    public init() {}

    public var isActive: Bool { startedAt != nil }

    /// Adds wheel notches (signed, already reversed if configured) on one
    /// or both axes. Returns true when this starts a new animation.
    @discardableResult
    public mutating func addImpulse(vertical: Double, horizontal: Double, verticalSettings: Settings,
                                    horizontalSettings: Settings, now: Double) -> Bool {
        settings = (verticalSettings.clamped, horizontalSettings.clamped)
        if Self.reverses(remaining.vertical, notches: vertical) { carry.vertical = 0 }
        if Self.reverses(remaining.horizontal, notches: horizontal) { carry.horizontal = 0 }
        remaining.vertical = Self.accumulate(remaining.vertical, notches: vertical, settings: settings.vertical)
        remaining.horizontal = Self.accumulate(remaining.horizontal, notches: horizontal, settings: settings.horizontal)
        guard startedAt == nil else { return false }
        startedAt = now
        lastStep = now
        return true
    }

    private static func reverses(_ pending: Double, notches: Double) -> Bool {
        pending != 0 && notches != 0 && (pending > 0) != (notches > 0)
    }

    private static func accumulate(_ pending: Double, notches: Double, settings: Settings) -> Double {
        guard notches != 0 else { return pending }
        let distance = notches * settings.pixelsPerNotch
        // Reversing direction stops the current movement at once.
        let base = (pending != 0 && (pending > 0) != (distance > 0)) ? 0 : pending
        let limit = maximumPendingNotches * settings.pixelsPerNotch
        return min(max(base + distance, -limit), limit)
    }

    /// Advances the animation to `now`. Returns nil when idle.
    public mutating func step(now: Double) -> Frame? {
        guard let start = startedAt, let previous = lastStep else { return nil }
        let isFirst = previous == start
        let elapsed = max(0, now - previous)
        lastStep = now

        var vertical = advance(&remaining.vertical, carry: &carry.vertical, elapsed: elapsed, settings: settings.vertical)
        var horizontal = advance(&remaining.horizontal, carry: &carry.horizontal, elapsed: elapsed, settings: settings.horizontal)
        let settled = abs(remaining.vertical) < 0.5 && abs(remaining.horizontal) < 0.5
        if settled || now - start >= Self.maximumDuration {
            if settled {
                // Pay out what is left so the total distance is exact.
                vertical += (remaining.vertical + carry.vertical).rounded()
                horizontal += (remaining.horizontal + carry.horizontal).rounded()
            }
            cancel()
            return Frame(vertical: vertical, horizontal: horizontal, phase: .ended)
        }
        return Frame(vertical: vertical, horizontal: horizontal, phase: isFirst ? .began : .changed)
    }

    /// Emits whole pixels and carries the fraction to the next frame, so
    /// the total distance is exact.
    private func advance(_ pending: inout Double, carry: inout Double, elapsed: Double, settings: Settings) -> Double {
        guard pending != 0 else { return 0 }
        // 95% of the distance in `duration`: e^(-3) ≈ 0.05.
        let fraction = 1 - exp(-3 * elapsed / settings.duration)
        var move = pending * fraction
        if abs(pending - move) < 0.5 { move = pending }
        pending -= move
        let total = move + carry
        let whole = total.rounded(.towardZero)
        carry = total - whole
        return whole
    }

    /// Stops immediately and discards pending distance.
    public mutating func cancel() {
        remaining = (0, 0)
        carry = (0, 0)
        startedAt = nil
        lastStep = nil
    }
}
