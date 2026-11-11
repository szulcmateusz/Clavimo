/// How discrete mouse wheel scrolling on one axis is changed.
public enum ScrollMode: Hashable, Sendable {
    /// Keep the system's distance and acceleration.
    case system
    /// Keep the system's acceleration curve, scaled by `speed` (0-10].
    case accelerated(speed: Double)
    /// Scroll a fixed number of lines per wheel notch, without acceleration.
    case byLines(Int)
    /// Scroll a fixed number of pixels per wheel notch, without
    /// acceleration. The event is delivered as precise scrolling.
    case byPixels(Double)

    public static let speedRange: ClosedRange<Double> = 0.1...10
    public static let linesRange: ClosedRange<Int> = 1...30
    public static let pixelsRange: ClosedRange<Double> = 1...512
}

public struct ScrollAxisSettings: Hashable, Sendable {
    public var reverse: Bool
    public var mode: ScrollMode

    public init(reverse: Bool = false, mode: ScrollMode = .system) {
        self.reverse = reverse
        self.mode = mode
    }

    public static let unchanged = ScrollAxisSettings()

    public var changesEvents: Bool { reverse || mode != .system }
}

/// The scroll fields of one axis of a wheel event.
public struct ScrollDeltas: Equatable, Sendable {
    /// Whole lines (`kCGScrollWheelEventDeltaAxis*`).
    public var lines: Int64
    /// Lines in fixed-point precision (`kCGScrollWheelEventFixedPtDeltaAxis*`).
    public var fixed: Double
    /// Pixels (`kCGScrollWheelEventPointDeltaAxis*`).
    public var points: Int64

    public init(lines: Int64, fixed: Double, points: Int64) {
        self.lines = lines
        self.fixed = fixed
        self.points = points
    }

    public static let zero = ScrollDeltas(lines: 0, fixed: 0, points: 0)
}

public enum ScrollTransform {
    /// macOS reports about ten points per line for discrete wheels.
    public static let pointsPerLine = 10.0

    /// Transforms one axis of a discrete wheel event. Returns the new
    /// deltas; a result of `.zero` for a non-zero input means the movement
    /// is absorbed (a fragment smaller than one notch in a fixed mode).
    public static func apply(_ settings: ScrollAxisSettings, to deltas: ScrollDeltas) -> ScrollDeltas {
        let direction = deltas.fixed != 0 ? deltas.fixed : Double(deltas.lines != 0 ? deltas.lines : deltas.points)
        guard direction != 0 else { return deltas }
        let sign: Double = (direction > 0) != settings.reverse ? 1 : -1

        switch settings.mode {
        case .system:
            guard settings.reverse else { return deltas }
            return ScrollDeltas(lines: -deltas.lines, fixed: -deltas.fixed, points: -deltas.points)

        case let .accelerated(speed):
            let factor = min(max(speed, ScrollMode.speedRange.lowerBound), ScrollMode.speedRange.upperBound)
            let fixed = abs(deltas.fixed != 0 ? deltas.fixed : Double(deltas.lines)) * factor
            let points = abs(Double(deltas.points != 0 ? deltas.points : deltas.lines * 10)) * factor
            // Whole notches stay at least one line; high-resolution
            // fragments keep their fractional size.
            let lines = deltas.lines != 0 ? max(1, fixed.rounded()) : fixed.rounded()
            return ScrollDeltas(lines: Int64(sign * lines), fixed: sign * fixed, points: Int64((sign * points).rounded()))

        case let .byLines(count):
            // Sub-line fragments from high-resolution wheels would otherwise
            // each become a full notch; only whole lines count as notches.
            guard deltas.lines != 0 else { return .zero }
            let lines = Double(min(max(count, ScrollMode.linesRange.lowerBound), ScrollMode.linesRange.upperBound))
            return ScrollDeltas(lines: Int64(sign * lines), fixed: sign * lines, points: Int64(sign * lines * pointsPerLine))

        case let .byPixels(pixels):
            guard deltas.lines != 0 else { return .zero }
            let pixels = min(max(pixels, ScrollMode.pixelsRange.lowerBound), ScrollMode.pixelsRange.upperBound)
            let lines = pixels / pointsPerLine
            return ScrollDeltas(lines: Int64((sign * lines).rounded()), fixed: sign * lines, points: Int64((sign * pixels).rounded()))
        }
    }
}
