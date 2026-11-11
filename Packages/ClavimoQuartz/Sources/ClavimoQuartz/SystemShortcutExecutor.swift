import AppKit
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
        case let .click(button):
            postClick(button)
        case let .media(key):
            postMediaKey(key)
        case let .launchApp(bundleID):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .toggleCapsLock:
            CapsLockState.toggle()
        }
    }

    /// Clicks at the pointer. Tagged as synthetic so Clavimo's own rules
    /// never react to it.
    private func postClick(_ button: MouseButton) {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = EventTapController.syntheticTag
        let location = CGEvent(source: nil)?.location ?? .zero
        let types: (down: CGEventType, up: CGEventType) = switch button {
        case .primary: (.leftMouseDown, .leftMouseUp)
        case .secondary: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        let cgButton = CGMouseButton(rawValue: UInt32(button.rawValue)) ?? .center
        for type in [types.down, types.up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton) else {
                continue
            }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
            event.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Media keys are "system defined" events (subtype 8) carrying the key
    /// type from IOKit's ev_keymap.h, the same events the top row sends.
    private func postMediaKey(_ key: MediaKey) {
        let keyType: Int = switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .nextTrack: 17
        case .previousTrack: 18
        }
        for (state, flags) in [(0xA, 0xA00), (0xB, 0xB00)] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (keyType << 16) | (state << 8), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
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
