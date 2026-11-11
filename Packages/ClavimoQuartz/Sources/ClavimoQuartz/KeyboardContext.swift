import AppKit
import Carbon
import CoreGraphics
import Foundation
import IOKit
import IOKit.hidsystem

/// Keyboard input sources (layouts and input methods), for rules limited
/// to one of them.
public enum InputSources {
    public struct Source: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
    }

    /// Posted on the main thread when the selected input source changes.
    public static let selectionChanged = Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")

    /// The identifier of the selected keyboard input source.
    public static func current() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }

    /// Input sources the user has enabled, in the order macOS lists them.
    public static func enabled() -> [Source] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        var seen: Set<String> = []
        return list.compactMap { source in
            guard let id = string(source, kTISPropertyInputSourceID), seen.insert(id).inserted,
                  let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue()) else { return nil }
            return Source(id: id, name: string(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

/// Secure keyboard entry: while a password field (or an app that asks for
/// it, such as Terminal's option) has it on, macOS hides keystrokes from
/// event taps, so keyboard rules cannot run.
public enum SecureInput {
    public struct Status: Equatable, Sendable {
        public let isEnabled: Bool
        /// The app holding it, when macOS reports one other than the login window.
        public let appName: String?

        public init(isEnabled: Bool, appName: String?) {
            self.isEnabled = isEnabled
            self.appName = appName
        }
    }

    public static func current() -> Status {
        guard IsSecureEventInputEnabled() else { return Status(isEnabled: false, appName: nil) }
        var name: String?
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let pid = session["kCGSSessionSecureInputPID"] as? Int32,
           let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier != "com.apple.loginwindow" {
            name = app.localizedName
        }
        return Status(isEnabled: true, appName: name)
    }
}

/// Toggles Caps Lock through the HID system, as the physical key does.
public enum CapsLockState {
    public static func toggle() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connection) }
        var state = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS else { return }
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), !state)
    }
}
