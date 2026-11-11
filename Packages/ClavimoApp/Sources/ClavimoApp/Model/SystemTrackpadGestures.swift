import ClavimoCore
import Foundation

/// The macOS trackpad gestures that can overlap with Clavimo's, read from
/// the trackpad preferences. macOS keeps recognizing its own gestures, so
/// a rule using the same movement would do two things at once.
enum SystemTrackpadGestures {
    enum Gesture: CaseIterable {
        case threeFingerDrag, lookUp, threeFingerHorizontal, threeFingerVertical, fourFingerHorizontal, fourFingerVertical, rotate

        var title: String {
            switch self {
            case .threeFingerDrag: String(localized: "Three-finger drag")
            case .lookUp: String(localized: "Look up with three fingers")
            case .threeFingerHorizontal: String(localized: "Swipe between pages or full-screen apps with three fingers")
            case .threeFingerVertical: String(localized: "Mission Control and App Exposé with three fingers")
            case .fourFingerHorizontal: String(localized: "Swipe between full-screen apps with four fingers")
            case .fourFingerVertical: String(localized: "Mission Control and App Exposé with four fingers")
            case .rotate: String(localized: "Rotate (turns photos and maps in apps that support it)")
            }
        }

        /// Preference key and the value macOS assumes when it is missing.
        fileprivate var preference: (key: String, defaultValue: Int) {
            switch self {
            case .threeFingerDrag: ("TrackpadThreeFingerDrag", 0)
            case .lookUp: ("TrackpadThreeFingerTapGesture", 0)
            case .threeFingerHorizontal: ("TrackpadThreeFingerHorizSwipeGesture", 2)
            case .threeFingerVertical: ("TrackpadThreeFingerVertSwipeGesture", 2)
            case .fourFingerHorizontal: ("TrackpadFourFingerHorizSwipeGesture", 2)
            case .fourFingerVertical: ("TrackpadFourFingerVertSwipeGesture", 2)
            case .rotate: ("TrackpadRotate", 1)
            }
        }
    }

    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// macOS gestures that are turned on, from the built-in trackpad
    /// settings (the Bluetooth trackpad domain is used when it is set).
    static func enabled() -> Set<Gesture> {
        var result: Set<Gesture> = []
        for gesture in Gesture.allCases {
            let (key, defaultValue) = gesture.preference
            let values = domains.compactMap { UserDefaults(suiteName: $0)?.object(forKey: key) as? Int }
            let value = values.first ?? defaultValue
            if value != 0 { result.insert(gesture) }
        }
        return result
    }

    /// The enabled macOS gestures that `trigger` overlaps with.
    static func conflicts(with trigger: TrackpadTrigger, enabled: Set<Gesture> = enabled()) -> [Gesture] {
        let candidates: [Gesture] = switch trigger {
        case .gesture(.tap(fingers: 3)): [.lookUp]
        case let .gesture(.swipe(3, direction)):
            [.threeFingerDrag] + (direction == .left || direction == .right ? [.threeFingerHorizontal] : [.threeFingerVertical])
        case let .gesture(.swipe(4, direction)):
            direction == .left || direction == .right ? [.fourFingerHorizontal] : [.fourFingerVertical]
        case .click(fingers: 3): [.threeFingerDrag]
        case .gesture(.rotate): [.rotate]
        default: []
        }
        return candidates.filter(enabled.contains)
    }
}
