/// One finger on a multitouch surface, as reported in a single frame.
public struct TouchContact: Equatable, Sendable {
    /// Stable for the lifetime of the finger on the surface.
    public var id: Int32
    public var state: TouchState
    /// Normalized position: 0...1 from left to right and bottom to top.
    public var x: Float
    public var y: Float
    /// Contact size (major axis, in the device's units). Large values
    /// suggest a palm rather than a fingertip.
    public var size: Float

    public init(id: Int32, state: TouchState, x: Float, y: Float, size: Float = 1) {
        self.id = id
        self.state = state
        self.x = x
        self.y = y
        self.size = size
    }
}

/// Contact states as reported by the multitouch driver.
public enum TouchState: Int32, Sendable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7

    /// True while the finger presses on the surface.
    public var isDown: Bool { self == .makeTouch || self == .touching }
}

/// Every contact on one device at one moment.
public struct TouchFrame: Equatable, Sendable {
    /// Seconds, monotonic.
    public var time: Double
    public var contacts: [TouchContact]

    public init(time: Double, contacts: [TouchContact]) {
        self.time = time
        self.contacts = contacts
    }

    /// Contacts currently pressing on the surface.
    public var down: [TouchContact] { contacts.filter(\.state.isDown) }
}

/// Checks that raw frames decoded from the private multitouch structure
/// make sense. If macOS changes that structure, decoded values become
/// garbage; the backend turns itself off instead of acting on them.
public struct TouchFrameValidator: Sendable {
    public static let maximumContacts = 20
    /// Consecutive implausible frames before the data is considered broken.
    public static let failureLimit = 20

    public private(set) var consecutiveFailures = 0
    public private(set) var validFrames = 0

    public init() {}

    public var isBroken: Bool { consecutiveFailures >= Self.failureLimit }

    /// Records a frame and returns true when it is plausible.
    @discardableResult
    public mutating func check(count: Int, states: [Int32], positions: [(Float, Float)]) -> Bool {
        let plausible = Self.isPlausible(count: count, states: states, positions: positions)
        if plausible {
            consecutiveFailures = 0
            validFrames += 1
        } else {
            consecutiveFailures += 1
        }
        return plausible
    }

    public static func isPlausible(count: Int, states: [Int32], positions: [(Float, Float)]) -> Bool {
        guard (0...maximumContacts).contains(count) else { return false }
        for state in states where TouchState(rawValue: state) == nil { return false }
        let range: ClosedRange<Float> = -0.1...1.1
        for (x, y) in positions where !(x.isFinite && y.isFinite && range.contains(x) && range.contains(y)) {
            return false
        }
        return true
    }
}
