/// What a key, a layer key, a combo or a sequence produces.
///
/// Outputs fall into two groups. Held outputs (`key`, `modifiers`, `layer`)
/// start when the trigger is pressed and end when it is released. Every
/// other output happens once, when the trigger fires.
public enum KeyOutput: Hashable, Sendable {
    /// Presses a key, with extra modifiers applied to that key only.
    case key(KeyCode, GenericModifiers)
    /// Holds side-specific modifiers, e.g. all four for a Hyper key.
    case modifiers(ModifierSet)
    /// Activates a layer while held.
    case layer(String)
    /// Turns a layer on, or off when it is already on.
    case toggleLayer(String)
    /// Applies modifiers to the next key or click only.
    case oneShot(ModifierSet)
    /// Starts a key sequence (leader key).
    case startSequence
    /// Runs an action once.
    case action(ActionCommand)
    /// Does nothing: the key is disabled.
    case none

    public static func key(_ code: KeyCode) -> KeyOutput { .key(code, []) }

    /// Outputs that last while their trigger is held.
    public var isHeld: Bool {
        switch self {
        case .key, .modifiers, .layer, .action(.openCompass): true
        default: false
        }
    }

    /// The layer this output can switch on, if any.
    var activatedLayer: String? {
        switch self {
        case let .layer(name), let .toggleLayer(name): name
        default: nil
        }
    }
}

extension ModifierSet {
    /// Control, Option, Shift and Command on the left side.
    public static let hyper: ModifierSet = [.leftControl, .leftOption, .leftShift, .leftCommand]

    /// Generic modifiers as left-side modifiers, for output.
    public init(leftSideOf generic: GenericModifiers) {
        var result: ModifierSet = []
        if generic.contains(.control) { result.insert(.leftControl) }
        if generic.contains(.option) { result.insert(.leftOption) }
        if generic.contains(.shift) { result.insert(.leftShift) }
        if generic.contains(.command) { result.insert(.leftCommand) }
        self = result
    }
}

/// How a tap-hold key decides between its tap and its hold.
public struct TapHoldSettings: Hashable, Sendable {
    public enum Interrupt: String, CaseIterable, Hashable, Sendable {
        /// Another key pressed while this one is held means hold. Best for
        /// keys rarely typed quickly, such as Caps Lock or Space layers.
        case holdOnOtherKey
        /// Hold only when another key is pressed and released while this
        /// one is still held. Best for letter keys (home row modifiers):
        /// overlapping keystrokes while typing fast stay taps.
        case permissive
        /// Only time decides: other keys wait until it is a tap or a hold.
        case timeOnly
    }

    /// Held longer than this, the key is a hold.
    public var holdAfterMilliseconds: Int
    public var interrupt: Interrupt
    /// A key from the same hand pressed meanwhile means tap. Prevents
    /// misfires of home row modifiers during rolls.
    public var oppositeHandsOnly: Bool
    /// Pressed within this many milliseconds of the previous key, the key
    /// is a tap at once (you are typing). Zero turns the check off.
    public var typingStreakMilliseconds: Int
    /// The window for a second tap when a double-tap output exists.
    public var doubleTapMilliseconds: Int

    public init(
        holdAfterMilliseconds: Int = 200,
        interrupt: Interrupt = .holdOnOtherKey,
        oppositeHandsOnly: Bool = false,
        typingStreakMilliseconds: Int = 0,
        doubleTapMilliseconds: Int = 250
    ) {
        self.holdAfterMilliseconds = holdAfterMilliseconds
        self.interrupt = interrupt
        self.oppositeHandsOnly = oppositeHandsOnly
        self.typingStreakMilliseconds = typingStreakMilliseconds
        self.doubleTapMilliseconds = doubleTapMilliseconds
    }

    public static let holdRange = 50...2000
    public static let typingStreakRange = 0...500
    public static let doubleTapRange = 100...600

    /// Defaults for letter keys used as modifiers.
    public static let homeRow = TapHoldSettings(
        holdAfterMilliseconds: 220, interrupt: .permissive, oppositeHandsOnly: true, typingStreakMilliseconds: 150
    )
}

public struct TapHoldBinding: Hashable, Sendable {
    public let id: String
    public let tap: KeyOutput
    public let hold: KeyOutput
    public let doubleTap: KeyOutput?
    public let settings: TapHoldSettings
}

/// What pressing a key does, other than a plain remap.
public enum KeyBehavior: Hashable, Sendable {
    case output(id: String, KeyOutput)
    case tapHold(TapHoldBinding)
}

public struct KeyBinding: Hashable, Sendable {
    public let behavior: KeyBehavior
    public let conditions: RuleConditions
}

public struct LayerBinding: Hashable, Sendable {
    public let id: String
    public let output: KeyOutput
    public let conditions: RuleConditions
}

public struct ComboRule: Hashable, Sendable {
    public let id: String
    public let keys: Set<KeyCode>
    public let output: KeyOutput
    public let windowMilliseconds: Int
    public let conditions: RuleConditions

    public static let keyCount = 2...3
    public static let windowRange = 20...200
    public static let defaultWindowMilliseconds = 50
}

public struct SequenceRule: Hashable, Sendable {
    public let id: String
    public let keys: [KeyCode]
    public let output: KeyOutput
    public let conditions: RuleConditions

    public static let keyCount = 1...4
    /// The sequence is cancelled after this long without a key.
    public static let timeoutMilliseconds = 4000
}

/// Which hand types a key on a standard Mac keyboard, for home row
/// modifiers. Unknown keys (Space, arrows, function keys) have no hand.
public enum KeyHand: Sendable {
    case left, right

    public init?(_ key: KeyCode) {
        if Self.leftKeys.contains(key.rawValue) {
            self = .left
        } else if Self.rightKeys.contains(key.rawValue) {
            self = .right
        } else {
            return nil
        }
    }

    // ANSI and ISO positions: number row, three letter rows, Tab, `, §.
    private static let leftKeys: Set<UInt16> = [
        0x0C, 0x0D, 0x0E, 0x0F, 0x11, // q w e r t
        0x00, 0x01, 0x02, 0x03, 0x05, // a s d f g
        0x06, 0x07, 0x08, 0x09, 0x0B, // z x c v b
        0x12, 0x13, 0x14, 0x15, 0x17, // 1 2 3 4 5
        0x32, 0x30, 0x0A,             // ` tab §
    ]
    private static let rightKeys: Set<UInt16> = [
        0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E, 0x2A, // y u i o p [ ] \
        0x04, 0x26, 0x28, 0x25, 0x29, 0x27,             // h j k l ; '
        0x2D, 0x2E, 0x2B, 0x2F, 0x2C,                   // n m , . /
        0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18,       // 6 7 8 9 0 - =
        0x24, 0x33,                                     // return delete
    ]
}

/// What the overlay in the menu bar shows: active layers, a sequence in
/// progress and pending one-shot modifiers.
public struct KeyboardOverlay: Equatable, Sendable {
    public var layers: [String] = []
    /// Keys typed after the leader, or nil when no sequence is running.
    public var sequence: [KeyCode]?
    /// Sequences that can still complete, with their remaining keys.
    public var sequenceOptions: [(keys: [KeyCode], output: KeyOutput)] = []
    public var oneShot: ModifierSet = []

    public init() {}

    public var isEmpty: Bool { layers.isEmpty && sequence == nil && oneShot.isEmpty }

    public static func == (lhs: KeyboardOverlay, rhs: KeyboardOverlay) -> Bool {
        lhs.layers == rhs.layers && lhs.sequence == rhs.sequence && lhs.oneShot == rhs.oneShot
            && lhs.sequenceOptions.map(\.keys) == rhs.sequenceOptions.map(\.keys)
            && lhs.sequenceOptions.map(\.output) == rhs.sequenceOptions.map(\.output)
    }
}

extension KeyCode {
    /// Caps Lock is moved to F18 at the HID level (see `KeyMapping` in the
    /// Quartz package), because macOS handles the Caps Lock toggle below
    /// the event tap. Rules on Caps Lock listen to this key instead.
    public static let capsLockProxy = KeyCode(0x4F)
    public static let f18 = KeyCode(0x4F)
    public static let jisEisu = KeyCode(0x66)
    public static let jisKana = KeyCode(0x68)
    public static let space = KeyCode(0x31)
    public static let returnKey = KeyCode(0x24)
    public static let tab = KeyCode(0x30)
    public static let delete = KeyCode(0x33)
}
