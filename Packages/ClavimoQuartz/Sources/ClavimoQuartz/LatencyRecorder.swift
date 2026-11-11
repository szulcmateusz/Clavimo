/// Fixed-capacity sample store for callback durations. Recording never
/// allocates, so it is safe to call from the event tap callback.
public struct LatencyRecorder: Sendable {
    private var samples: [UInt64]
    private var next = 0
    private var filled = false
    public private(set) var totalCount: UInt64 = 0

    public init(capacity: Int = 16_384) {
        samples = [UInt64](repeating: 0, count: max(1, capacity))
    }

    public mutating func record(_ nanoseconds: UInt64) {
        samples[next] = nanoseconds
        next += 1
        totalCount &+= 1
        if next == samples.count {
            next = 0
            filled = true
        }
    }

    public struct Summary: Equatable, Sendable {
        public let count: Int
        public let p50: UInt64
        public let p95: UInt64
        public let p99: UInt64
        public let max: UInt64
    }

    /// Nearest-rank percentiles over the retained window. Call off the
    /// event path; it sorts a copy.
    public func summary() -> Summary? {
        let window = filled ? samples : Array(samples[0..<next])
        guard !window.isEmpty else { return nil }
        let sorted = window.sorted()
        func rank(_ percentile: Double) -> UInt64 {
            let index = Int((percentile * Double(sorted.count)).rounded(.up)) - 1
            return sorted[min(max(index, 0), sorted.count - 1)]
        }
        return Summary(count: sorted.count, p50: rank(0.50), p95: rank(0.95), p99: rank(0.99), max: sorted[sorted.count - 1])
    }
}
