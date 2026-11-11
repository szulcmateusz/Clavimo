import ClavimoCore
import Foundation
import IOKit.hid

/// A keyboard or pointing device as reported by IOKit. Discovery is
/// informational; it does not imply that events can be attributed to it.
public struct HIDDeviceInfo: Hashable, Sendable, Identifiable {
    public let id: DeviceID
    public let name: String
    public let transport: String?
    public let isKeyboard: Bool
    public let isPointer: Bool
}

public enum HIDDeviceCatalog {
    /// Lists connected keyboards and pointing devices, merged by vendor and
    /// product ID (a device often exposes several HID interfaces).
    public static func connectedDevices() -> [HIDDeviceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDMatching.keyboardsAndPointers as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var merged: [DeviceID: HIDDeviceInfo] = [:]
        for device in set {
            guard let id = HIDMatching.deviceID(device) else { continue }
            let usagePage = HIDMatching.intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0
            let usage = HIDMatching.intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
            let isKeyboard = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Keyboard || usage == kHIDUsage_GD_Keypad)
            let isPointer = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == kHIDUsage_GD_Pointer)
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown device"
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
            if let existing = merged[id] {
                merged[id] = HIDDeviceInfo(id: id, name: existing.name, transport: existing.transport ?? transport,
                                           isKeyboard: existing.isKeyboard || isKeyboard, isPointer: existing.isPointer || isPointer)
            } else {
                merged[id] = HIDDeviceInfo(id: id, name: name, transport: transport, isKeyboard: isKeyboard, isPointer: isPointer)
            }
        }
        return merged.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

enum HIDMatching {
    static let keyboardsAndPointers: [[String: Int]] = [
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keypad],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
    ]

    static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    static func deviceID(_ device: IOHIDDevice) -> DeviceID? {
        guard let vendor = intProperty(device, kIOHIDVendorIDKey), let product = intProperty(device, kIOHIDProductIDKey) else {
            return nil
        }
        return DeviceID(vendorID: vendor, productID: product)
    }
}

/// Experimental attribution of a key or button press to a physical device.
///
/// Quartz events do not carry a public device identity. When a rule needs
/// one, this asks every open HID device whether it currently reports the
/// pressed key or button as down (`IOHIDDeviceGetValue`). The answer is
/// used only when exactly one device model reports it; otherwise the
/// result is nil and device-scoped rules do not match, so input falls back
/// to unchanged behavior. Requires Input Monitoring.
///
/// All methods must be called on the run loop thread passed to `start`.
public final class HIDDeviceAttributor: @unchecked Sendable {
    private struct TrackedDevice {
        let device: IOHIDDevice
        let id: DeviceID
        var keyElements: [UInt32: IOHIDElement]
        var buttonElements: [UInt32: IOHIDElement]
    }

    private let manager: IOHIDManager
    private var tracked: [ObjectIdentifier: TrackedDevice] = [:]
    /// Reused output slot for IOHIDDeviceGetValue, so queries on the event
    /// path do not allocate.
    private let valueSlot = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        valueSlot.deallocate()
    }

    /// Returns false when the devices cannot be opened (no permission).
    public func start(on runLoop: CFRunLoop) -> Bool {
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDMatching.keyboardsAndPointers as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceAttributor>.fromOpaque(context).takeUnretainedValue().add(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDDeviceAttributor>.fromOpaque(context).takeUnretainedValue().remove(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.commonModes.rawValue)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    public func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        tracked.removeAll()
    }

    public func deviceHolding(key: KeyCode) -> DeviceID? {
        guard let usage = HIDUsage.keyboardUsage(for: key) else { return nil }
        return uniqueDevice { $0.keyElements[usage] }
    }

    public func deviceHolding(button: MouseButton) -> DeviceID? {
        uniqueDevice { $0.buttonElements[UInt32(button.rawValue) + 1] }
    }

    private func uniqueDevice(_ element: (TrackedDevice) -> IOHIDElement?) -> DeviceID? {
        var found: DeviceID?
        for device in tracked.values {
            guard let element = element(device) else { continue }
            // IOHIDDeviceGetValue returns +0 for the value reference.
            guard IOHIDDeviceGetValue(device.device, element, valueSlot) == kIOReturnSuccess,
                  IOHIDValueGetIntegerValue(valueSlot.pointee.takeUnretainedValue()) != 0 else { continue }
            if let found, found != device.id { return nil }
            found = device.id
        }
        return found
    }

    private func add(_ device: IOHIDDevice) {
        guard let id = HIDMatching.deviceID(device) else { return }
        var keys: [UInt32: IOHIDElement] = [:]
        var buttons: [UInt32: IOHIDElement] = [:]
        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for element in elements {
                let type = IOHIDElementGetType(element)
                guard type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_Misc else { continue }
                let page = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)
                if page == UInt32(kHIDPage_KeyboardOrKeypad), keys[usage] == nil {
                    keys[usage] = element
                } else if page == UInt32(kHIDPage_Button), buttons[usage] == nil {
                    buttons[usage] = element
                }
            }
        }
        tracked[ObjectIdentifier(device)] = TrackedDevice(device: device, id: id, keyElements: keys, buttonElements: buttons)
    }

    private func remove(_ device: IOHIDDevice) {
        tracked[ObjectIdentifier(device)] = nil
    }
}

/// Mac virtual key code to USB HID keyboard usage (page 0x07).
enum HIDUsage {
    static func keyboardUsage(for key: KeyCode) -> UInt32? {
        table[key.rawValue]
    }

    private static let table: [UInt16: UInt32] = [
        0x00: 0x04, 0x01: 0x16, 0x02: 0x07, 0x03: 0x09, 0x04: 0x0B, 0x05: 0x0A, 0x06: 0x1D, 0x07: 0x1B,
        0x08: 0x06, 0x09: 0x19, 0x0A: 0x64, 0x0B: 0x05, 0x0C: 0x14, 0x0D: 0x1A, 0x0E: 0x08, 0x0F: 0x15,
        0x10: 0x1C, 0x11: 0x17, 0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x16: 0x23, 0x17: 0x22,
        0x18: 0x2E, 0x19: 0x26, 0x1A: 0x24, 0x1B: 0x2D, 0x1C: 0x25, 0x1D: 0x27, 0x1E: 0x30, 0x1F: 0x12,
        0x20: 0x18, 0x21: 0x2F, 0x22: 0x0C, 0x23: 0x13, 0x24: 0x28, 0x25: 0x0F, 0x26: 0x0D, 0x27: 0x34,
        0x28: 0x0E, 0x29: 0x33, 0x2A: 0x31, 0x2B: 0x36, 0x2C: 0x38, 0x2D: 0x11, 0x2E: 0x10, 0x2F: 0x37,
        0x30: 0x2B, 0x31: 0x2C, 0x32: 0x35, 0x33: 0x2A, 0x35: 0x29,
        0x36: 0xE7, 0x37: 0xE3, 0x38: 0xE1, 0x39: 0x39, 0x3A: 0xE2, 0x3B: 0xE0, 0x3C: 0xE5, 0x3D: 0xE6, 0x3E: 0xE4,
        0x40: 0x6C, 0x4F: 0x6D, 0x50: 0x6E, 0x5A: 0x6F,
        0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x63: 0x3C, 0x64: 0x41, 0x65: 0x42, 0x67: 0x44, 0x69: 0x68,
        0x6A: 0x6B, 0x6B: 0x69, 0x6D: 0x43, 0x6F: 0x45, 0x71: 0x6A, 0x72: 0x75, 0x73: 0x4A, 0x74: 0x4B,
        0x75: 0x4C, 0x76: 0x3D, 0x77: 0x4D, 0x78: 0x3B, 0x79: 0x4E, 0x7A: 0x3A,
        0x7B: 0x50, 0x7C: 0x4F, 0x7D: 0x51, 0x7E: 0x52,
    ]
}
