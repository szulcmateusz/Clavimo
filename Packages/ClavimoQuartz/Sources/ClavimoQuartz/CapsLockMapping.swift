import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import ClavimoCore

/// Moves Caps Lock to F18 on every keyboard while Caps Lock rules are
/// active, because macOS toggles Caps Lock below the event tap. Rules then
/// see `KeyCode.capsLockProxy`.
///
/// The mapping is a HID service property (`UserKeyMapping`), the same one
/// System Settings > Keyboard > Modifier Keys and `hidutil` use. Entries
/// already there are kept; a keyboard whose Caps Lock is already changed
/// in System Settings is left alone and reported. The mapping is removed
/// whenever remapping stops; after a crash it lasts until the next login
/// at most, and Caps Lock then types nothing until Clavimo starts again.
public final class CapsLockMapping: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        /// Keyboards whose Caps Lock now goes to Clavimo.
        public var mappedKeyboards: [String] = []
        /// Keyboards whose Caps Lock is changed in System Settings.
        public var conflictingKeyboards: [String] = []

        public init(mappedKeyboards: [String] = [], conflictingKeyboards: [String] = []) {
            self.mappedKeyboards = mappedKeyboards
            self.conflictingKeyboards = conflictingKeyboards
        }
    }

    static let capsLockUsage: UInt64 = 0x7_0000_0039
    static let proxyUsage: UInt64 = 0x7_0000_006D // F18
    private static var property: CFString { "UserKeyMapping" as CFString }
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    private let lock = NSLock()
    private var active = false
    private var manager: IOHIDManager?
    private var currentStatus = Status()

    public init() {}

    public var status: Status {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus
    }

    /// Maps Caps Lock on every keyboard now and on keyboards connected
    /// later. Call from the main thread.
    public func start() {
        lock.lock()
        active = true
        lock.unlock()
        apply()
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let mapping = Unmanaged<CapsLockMapping>.fromOpaque(context).takeUnretainedValue()
            // The new keyboard's service appears a moment after the device.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { mapping.applyIfActive() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Opening is not needed for matching notifications; nothing is read.
        self.manager = manager
    }

    /// Removes Clavimo's entries from every keyboard.
    public func stop() {
        lock.lock()
        active = false
        lock.unlock()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        }
        manager = nil
        Self.removeAll()
        lock.lock()
        currentStatus = Status()
        lock.unlock()
    }

    private func applyIfActive() {
        lock.lock()
        let isActive = active
        lock.unlock()
        if isActive { apply() }
    }

    private func apply() {
        var result = Status()
        for (service, name) in Self.keyboards() {
            var entries = Self.entries(of: service)
            if let existing = entries.first(where: { $0[Self.sourceKey] == Self.capsLockUsage }) {
                if existing[Self.destinationKey] == Self.proxyUsage {
                    result.mappedKeyboards.append(name)
                } else {
                    result.conflictingKeyboards.append(name)
                }
                continue
            }
            entries.append([Self.sourceKey: Self.capsLockUsage, Self.destinationKey: Self.proxyUsage])
            if IOHIDServiceClientSetProperty(service, Self.property, entries as CFArray) {
                result.mappedKeyboards.append(name)
            }
        }
        lock.lock()
        currentStatus = result
        lock.unlock()
    }

    /// Removes Clavimo's entry from every keyboard, also one left behind by
    /// an earlier run that did not stop cleanly. Safe to call at launch.
    public static func removeAll() {
        for (service, _) in keyboards() {
            let entries = entries(of: service)
            let kept = entries.filter { !($0[sourceKey] == capsLockUsage && $0[destinationKey] == proxyUsage) }
            if kept.count != entries.count {
                IOHIDServiceClientSetProperty(service, property, kept as CFArray)
            }
        }
    }

    private static func keyboards() -> [(IOHIDServiceClient, String)] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        return services.compactMap { service in
            guard IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 else {
                return nil
            }
            let name = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String ?? "Keyboard"
            return (service, name)
        }
    }

    private static func entries(of service: IOHIDServiceClient) -> [[String: UInt64]] {
        guard let array = IOHIDServiceClientCopyProperty(service, property) as? [[String: Any]] else { return [] }
        return array.compactMap { entry in
            guard let source = (entry[sourceKey] as? NSNumber)?.uint64Value,
                  let destination = (entry[destinationKey] as? NSNumber)?.uint64Value else { return nil }
            return [sourceKey: source, destinationKey: destination]
        }
    }
}
