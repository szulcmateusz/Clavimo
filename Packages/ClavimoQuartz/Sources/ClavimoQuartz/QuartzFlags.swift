import CoreGraphics
import ClavimoCore

/// Converts between Quartz event flags and the core's side-specific
/// modifier set. Device-dependent bits come from IOKit's `IOLLEvent.h`
/// (`NX_DEVICE*KEYMASK`), verified against the macOS SDK.
public enum QuartzFlags {
    static let deviceLeftControl: UInt64 = 0x0000_0001
    static let deviceLeftShift: UInt64 = 0x0000_0002
    static let deviceRightShift: UInt64 = 0x0000_0004
    static let deviceLeftCommand: UInt64 = 0x0000_0008
    static let deviceRightCommand: UInt64 = 0x0000_0010
    static let deviceLeftOption: UInt64 = 0x0000_0020
    static let deviceRightOption: UInt64 = 0x0000_0040
    static let deviceRightControl: UInt64 = 0x0000_2000

    private static let sides: [(ModifierSet, UInt64, CGEventFlags)] = [
        (.leftControl, deviceLeftControl, .maskControl),
        (.rightControl, deviceRightControl, .maskControl),
        (.leftShift, deviceLeftShift, .maskShift),
        (.rightShift, deviceRightShift, .maskShift),
        (.leftOption, deviceLeftOption, .maskAlternate),
        (.rightOption, deviceRightOption, .maskAlternate),
        (.leftCommand, deviceLeftCommand, .maskCommand),
        (.rightCommand, deviceRightCommand, .maskCommand),
    ]

    private static let allModifierBits: UInt64 = sides.reduce(0) { $0 | $1.1 | $1.2.rawValue }

    /// Reads the physical side-specific modifiers. Some keyboards report
    /// only the generic bit; that case is attributed to the left key.
    public static func modifiers(from flags: CGEventFlags) -> ModifierSet {
        let raw = flags.rawValue
        var result: ModifierSet = []
        for (side, deviceBit, _) in sides where raw & deviceBit != 0 {
            result.insert(side)
        }
        let fallbacks: [(CGEventFlags, ModifierSet, ModifierSet)] = [
            (.maskControl, [.leftControl, .rightControl], .leftControl),
            (.maskShift, [.leftShift, .rightShift], .leftShift),
            (.maskAlternate, [.leftOption, .rightOption], .leftOption),
            (.maskCommand, [.leftCommand, .rightCommand], .leftCommand),
        ]
        for (generic, bothSides, fallback) in fallbacks
        where flags.contains(generic) && result.intersection(bothSides).isEmpty {
            result.insert(fallback)
        }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }

    /// Replaces only the modifier bits of `flags`, preserving unrelated
    /// state such as Caps Lock, Fn, and the numeric pad flag. The core's
    /// `.function` member is ignored here: Fn is never remapped.
    public static func applying(_ modifiers: ModifierSet, to flags: CGEventFlags) -> CGEventFlags {
        var raw = flags.rawValue & ~allModifierBits
        for (side, deviceBit, generic) in sides where modifiers.contains(side) {
            raw |= deviceBit | generic.rawValue
        }
        return CGEventFlags(rawValue: raw)
    }
}
