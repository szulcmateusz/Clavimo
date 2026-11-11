/// A macOS virtual key code (the `kVK_*` namespace from Carbon's `Events.h`).
///
/// The core deliberately stores raw codes instead of characters: the same
/// physical key produces different characters under different keyboard
/// layouts, while rules describe physical keys.
public struct KeyCode: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt16

    public init(_ rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public var description: String { "KeyCode(\(rawValue))" }

    public static let a = KeyCode(0x00)
    public static let f = KeyCode(0x03)
    public static let g = KeyCode(0x05)
    public static let c = KeyCode(0x08)
    public static let v = KeyCode(0x09)
    public static let escape = KeyCode(0x35)
    public static let leftArrow = KeyCode(0x7B)
    public static let rightArrow = KeyCode(0x7C)
    public static let downArrow = KeyCode(0x7D)
    public static let upArrow = KeyCode(0x7E)

    public static let rightCommand = KeyCode(0x36)
    public static let leftCommand = KeyCode(0x37)
    public static let leftShift = KeyCode(0x38)
    public static let capsLock = KeyCode(0x39)
    public static let leftOption = KeyCode(0x3A)
    public static let leftControl = KeyCode(0x3B)
    public static let rightShift = KeyCode(0x3C)
    public static let rightOption = KeyCode(0x3D)
    public static let rightControl = KeyCode(0x3E)
    public static let function = KeyCode(0x3F)

    /// The side-specific modifier this key produces, if it is one of the
    /// eight remappable modifier keys. Caps Lock and Fn are intentionally
    /// excluded: they have toggle or firmware-specific semantics.
    public var modifierKey: ModifierKey? { ModifierKey(keyCode: self) }
}

/// A raw Quartz mouse button number (`kCGMouseEventButtonNumber`).
///
/// Raw numbers start at zero: 0 is the primary button, 1 the secondary,
/// 2 the middle button, and 3 is what most vendors label "Button 4".
/// Use `userFacingNumber` for display so labels and indexing never diverge.
public struct MouseButton: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt16

    public init(raw: UInt16) {
        self.rawValue = raw
    }

    /// Creates a button from the one-based number shown to users.
    public init?(userFacingNumber: Int) {
        guard userFacingNumber >= 1, userFacingNumber <= Int(UInt16.max) else { return nil }
        self.rawValue = UInt16(userFacingNumber - 1)
    }

    public var userFacingNumber: Int { Int(rawValue) + 1 }

    /// Primary and secondary buttons are protected: remapping them can make
    /// the computer impossible to operate with the mouse.
    public var isProtected: Bool { rawValue <= 1 }

    public var description: String { "MouseButton(\(userFacingNumber))" }

    public static let primary = MouseButton(raw: 0)
    public static let secondary = MouseButton(raw: 1)
    public static let middle = MouseButton(raw: 2)
    public static let button4 = MouseButton(raw: 3)
    public static let button5 = MouseButton(raw: 4)
}

/// One of the eight side-specific modifier keys.
public enum ModifierKey: CaseIterable, Sendable {
    case leftControl, rightControl
    case leftShift, rightShift
    case leftOption, rightOption
    case leftCommand, rightCommand

    public init?(keyCode: KeyCode) {
        switch keyCode {
        case .leftControl: self = .leftControl
        case .rightControl: self = .rightControl
        case .leftShift: self = .leftShift
        case .rightShift: self = .rightShift
        case .leftOption: self = .leftOption
        case .rightOption: self = .rightOption
        case .leftCommand: self = .leftCommand
        case .rightCommand: self = .rightCommand
        default: return nil
        }
    }

    public var keyCode: KeyCode {
        switch self {
        case .leftControl: .leftControl
        case .rightControl: .rightControl
        case .leftShift: .leftShift
        case .rightShift: .rightShift
        case .leftOption: .leftOption
        case .rightOption: .rightOption
        case .leftCommand: .leftCommand
        case .rightCommand: .rightCommand
        }
    }

    public var set: ModifierSet {
        switch self {
        case .leftControl: .leftControl
        case .rightControl: .rightControl
        case .leftShift: .leftShift
        case .rightShift: .rightShift
        case .leftOption: .leftOption
        case .rightOption: .rightOption
        case .leftCommand: .leftCommand
        case .rightCommand: .rightCommand
        }
    }
}

/// Side-specific modifier state. The core never collapses left and right
/// into one generic flag until a rule explicitly asks for generic matching.
///
/// `function` tracks the Fn/Globe key. It can be matched by chords but is
/// never remapped or emitted: adapters preserve it from the original event.
public struct ModifierSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftControl = ModifierSet(rawValue: 1 << 0)
    public static let rightControl = ModifierSet(rawValue: 1 << 1)
    public static let leftShift = ModifierSet(rawValue: 1 << 2)
    public static let rightShift = ModifierSet(rawValue: 1 << 3)
    public static let leftOption = ModifierSet(rawValue: 1 << 4)
    public static let rightOption = ModifierSet(rawValue: 1 << 5)
    public static let leftCommand = ModifierSet(rawValue: 1 << 6)
    public static let rightCommand = ModifierSet(rawValue: 1 << 7)
    public static let function = ModifierSet(rawValue: 1 << 8)

    public var keys: [ModifierKey] {
        ModifierKey.allCases.filter { contains($0.set) }
    }

    public var generic: GenericModifiers {
        var result: GenericModifiers = []
        if !intersection([.leftControl, .rightControl]).isEmpty { result.insert(.control) }
        if !intersection([.leftShift, .rightShift]).isEmpty { result.insert(.shift) }
        if !intersection([.leftOption, .rightOption]).isEmpty { result.insert(.option) }
        if !intersection([.leftCommand, .rightCommand]).isEmpty { result.insert(.command) }
        if contains(.function) { result.insert(.function) }
        return result
    }
}

/// Side-agnostic modifiers, used for shortcut-style matching and output.
public struct GenericModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = GenericModifiers(rawValue: 1 << 0)
    public static let shift = GenericModifiers(rawValue: 1 << 1)
    public static let option = GenericModifiers(rawValue: 1 << 2)
    public static let command = GenericModifiers(rawValue: 1 << 3)
    public static let function = GenericModifiers(rawValue: 1 << 4)
}

/// A normalized physical input event. Platform adapters convert Quartz
/// events into this type; `flagsChanged` events become key down/up events
/// for the modifier key whose state changed.
public struct InputEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case key(KeyCode, isDown: Bool, isRepeat: Bool)
        case mouseButton(MouseButton, isDown: Bool)
    }

    public var kind: Kind
    /// Physical side-specific modifier state *after* this event, as
    /// reported by the platform.
    public var modifiers: ModifierSet
    /// Monotonic timestamp in nanoseconds.
    public var time: UInt64
    /// The physical device, only when the adapter could attribute it
    /// reliably. Nil never matches a device-scoped rule.
    public var device: DeviceID?
    /// Fingers on the trackpad when a button event came from a trackpad
    /// click, if the adapter knows it. Nil means unknown, which never
    /// matches a trackpad click rule.
    public var touch: TouchSnapshot?

    public init(kind: Kind, modifiers: ModifierSet, time: UInt64, device: DeviceID? = nil, touch: TouchSnapshot? = nil) {
        self.kind = kind
        self.modifiers = modifiers
        self.time = time
        self.device = device
        self.touch = touch
    }
}

/// A side effect that the agent runs outside the event callback.
public enum ActionCommand: Equatable, Sendable {
    case nextWorkspace
    case previousWorkspace
    case missionControl
    case applicationWindows
    case shortcut(KeyCode, GenericModifiers)
    /// Clicks a mouse button at the pointer.
    case click(MouseButton)
    /// Opens or activates the app with this bundle identifier.
    case launchApp(String)
    /// Presses a media or brightness key.
    case media(MediaKey)
}

/// Keys from the top row of Apple keyboards.
public enum MediaKey: String, CaseIterable, Hashable, Sendable {
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute, brightnessUp, brightnessDown
}

extension ActionCommand: Hashable {}
