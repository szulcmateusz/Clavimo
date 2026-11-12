import Foundation

/// One of the eight directions of an action compass.
public enum CompassDirection: String, CaseIterable, Hashable, Sendable, Codable {
    case up, upRight, right, downRight, down, downLeft, left, upLeft

    /// Angle in degrees, counterclockwise from right (mathematical, y up).
    public var degrees: Double {
        switch self {
        case .right: 0
        case .upRight: 45
        case .up: 90
        case .upLeft: 135
        case .left: 180
        case .downLeft: 225
        case .down: 270
        case .downRight: 315
        }
    }

    /// The number key that picks this direction, 1 to 8, clockwise from up.
    public var number: Int {
        Self.clockwise.firstIndex(of: self)! + 1
    }

    /// Directions clockwise from up, the order of the number keys.
    public static let clockwise: [CompassDirection] = [.up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft]

    public init?(number: Int) {
        guard Self.clockwise.indices.contains(number - 1) else { return nil }
        self = Self.clockwise[number - 1]
    }
}

/// What a compass slot does.
public enum CompassAction: Hashable, Sendable {
    case action(ActionCommand)
    /// Hides an inherited slot on an app page.
    case none
}

public struct CompassSlot: Hashable, Sendable {
    public var name: String
    public var action: CompassAction

    public init(name: String, action: CompassAction) {
        self.name = name
        self.action = action
    }
}

/// A validated compass: a default page and pages for apps.
public struct CompassDefinition: Hashable, Sendable {
    public var id: String
    public var name: String
    public var slots: [CompassDirection: CompassSlot]
    /// App pages by bundle identifier. A direction missing on an app page
    /// keeps the default page's slot.
    public var apps: [String: [CompassDirection: CompassSlot]]
    public var hintDelayMilliseconds: Int
    /// Pointer travel, in points, below which nothing is picked.
    public var deadZone: Double
    /// Whether the pointer goes back to where it was after a pick.
    public var returnPointer: Bool

    public static let defaultHintDelay = 250
    public static let hintDelayRange = 0...2000
    public static let defaultDeadZone = 40.0
    public static let deadZoneRange = 10.0...200.0

    public init(
        id: String, name: String,
        slots: [CompassDirection: CompassSlot],
        apps: [String: [CompassDirection: CompassSlot]] = [:],
        hintDelayMilliseconds: Int = Self.defaultHintDelay,
        deadZone: Double = Self.defaultDeadZone,
        returnPointer: Bool = true
    ) {
        self.id = id
        self.name = name
        self.slots = slots
        self.apps = apps
        self.hintDelayMilliseconds = hintDelayMilliseconds
        self.deadZone = deadZone
        self.returnPointer = returnPointer
    }

    /// The slots shown in `app`: its page over the default page, without
    /// the slots the page turns off.
    public func slots(forApp app: String?) -> [CompassDirection: CompassSlot] {
        var result = slots
        if let app, let page = apps[app] {
            for (direction, slot) in page { result[direction] = slot }
        }
        return result.filter { $0.value.action != .none }
    }
}

/// Picks a slot from how far and where the pointer moved.
public enum CompassGeometry {
    /// The defined direction nearest to the movement, or nil inside the
    /// dead zone or when nothing is defined. `dx` grows to the right and
    /// `dy` grows upwards. With fewer slots, each one covers a wider angle.
    public static func direction(dx: Double, dy: Double, among defined: Set<CompassDirection>, deadZone: Double) -> CompassDirection? {
        guard !defined.isEmpty, (dx * dx + dy * dy).squareRoot() >= deadZone else { return nil }
        var angle = atan2(dy, dx) * 180 / .pi
        if angle < 0 { angle += 360 }
        func distance(_ direction: CompassDirection) -> Double {
            let difference = abs(direction.degrees - angle).truncatingRemainder(dividingBy: 360)
            return min(difference, 360 - difference)
        }
        // Ties go to the earlier direction clockwise from up, so the
        // result never depends on set order.
        return CompassDirection.clockwise.filter(defined.contains).min { distance($0) < distance($1) }
    }
}

/// What the engine tells the adapter about an open compass.
public enum CompassSignal: Hashable, Sendable {
    /// Open the compass. `held` is true while its trigger is held down;
    /// the adapter then picks by pointer movement on `release`.
    case open(id: String, held: Bool)
    /// The held trigger was released. The engine keeps the compass open as
    /// a panel until the adapter calls `closeCompass()`.
    case release
    /// A number key picked a direction.
    case pick(CompassDirection)
    /// Return, Space or a primary click: run the highlighted slot.
    case confirm
    /// Escape, a secondary click, another key, a timeout or a reset.
    case cancel
}
