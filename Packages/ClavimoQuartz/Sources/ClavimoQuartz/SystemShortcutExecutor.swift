import CoreGraphics
import ClavimoCore

/// Runs actions by posting the documented macOS keyboard shortcuts
/// (Control + Arrow keys). They depend on the matching entries being
/// enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission
/// Control; there is no public API to select a Space directly.
public struct SystemShortcutExecutor: Sendable {
    public init() {}

    public func run(_ action: ActionCommand) {
        switch action {
        case .nextWorkspace:
            postShortcut(.rightArrow, [.control], isArrow: true)
        case .previousWorkspace:
            postShortcut(.leftArrow, [.control], isArrow: true)
        case .missionControl:
            postShortcut(.upArrow, [.control], isArrow: true)
        case .applicationWindows:
            postShortcut(.downArrow, [.control], isArrow: true)
        case let .shortcut(key, modifiers):
            postShortcut(key, modifiers, isArrow: false)
        }
    }

    private func postShortcut(_ key: KeyCode, _ modifiers: GenericModifiers, isArrow: Bool) {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = EventTapController.syntheticTag
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        // Physical arrow keys report Fn and numeric pad flags; mirror them.
        if isArrow { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
