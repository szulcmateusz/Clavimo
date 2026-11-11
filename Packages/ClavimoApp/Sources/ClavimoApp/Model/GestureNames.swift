import ClavimoCore
import Foundation

/// Localized names of trackpad gestures, triggers and their parts.
enum GestureNames {
    static func title(_ gesture: GestureEvent) -> String {
        switch gesture {
        case let .tap(fingers): String(localized: "Tap with \(fingers) fingers")
        case let .tipTap(side): side == .left ? String(localized: "Tip tap left") : String(localized: "Tip tap right")
        case let .swipe(fingers, .up): String(localized: "Swipe up with \(fingers) fingers")
        case let .swipe(fingers, .down): String(localized: "Swipe down with \(fingers) fingers")
        case let .swipe(fingers, .left): String(localized: "Swipe left with \(fingers) fingers")
        case let .swipe(fingers, .right): String(localized: "Swipe right with \(fingers) fingers")
        case .rotate(.clockwise): String(localized: "Turn two fingers clockwise")
        case .rotate(.counterclockwise): String(localized: "Turn two fingers counterclockwise")
        }
    }

    static func rotation(_ rotation: GestureEvent.Rotation) -> String {
        switch rotation {
        case .clockwise: String(localized: "Clockwise")
        case .counterclockwise: String(localized: "Counterclockwise")
        }
    }

    /// "on the left half" and so on, for sentences.
    static func zone(_ zone: TrackpadZone) -> String {
        switch zone {
        case .left: String(localized: "on the left half")
        case .right: String(localized: "on the right half")
        case .top: String(localized: "on the top half")
        case .bottom: String(localized: "on the bottom half")
        case .topLeft: String(localized: "in the top left corner")
        case .topRight: String(localized: "in the top right corner")
        case .bottomLeft: String(localized: "in the bottom left corner")
        case .bottomRight: String(localized: "in the bottom right corner")
        }
    }

    static func zoneName(_ zone: TrackpadZone?) -> String {
        switch zone {
        case nil: String(localized: "Anywhere")
        case .left: String(localized: "Left half")
        case .right: String(localized: "Right half")
        case .top: String(localized: "Top half")
        case .bottom: String(localized: "Bottom half")
        case .topLeft: String(localized: "Top left corner")
        case .topRight: String(localized: "Top right corner")
        case .bottomLeft: String(localized: "Bottom left corner")
        case .bottomRight: String(localized: "Bottom right corner")
        }
    }

    static func title(_ trigger: TrackpadTrigger) -> String {
        switch trigger {
        case let .gesture(gesture): title(gesture)
        case let .click(fingers): String(localized: "Click with \(fingers) fingers")
        case .cornerClick(.topLeft): String(localized: "Click in the top left corner")
        case .cornerClick(.topRight): String(localized: "Click in the top right corner")
        case .cornerClick(.bottomLeft): String(localized: "Click in the bottom left corner")
        case .cornerClick(.bottomRight): String(localized: "Click in the bottom right corner")
        }
    }

    static func direction(_ direction: GestureEvent.Direction) -> String {
        switch direction {
        case .up: String(localized: "direction.up", defaultValue: "Up")
        case .down: String(localized: "direction.down", defaultValue: "Down")
        case .left: String(localized: "direction.left", defaultValue: "Left")
        case .right: String(localized: "direction.right", defaultValue: "Right")
        }
    }

    static func name(_ corner: TrackpadCorner) -> String {
        switch corner {
        case .topLeft: String(localized: "Top left")
        case .topRight: String(localized: "Top right")
        case .bottomLeft: String(localized: "Bottom left")
        case .bottomRight: String(localized: "Bottom right")
        }
    }
}
