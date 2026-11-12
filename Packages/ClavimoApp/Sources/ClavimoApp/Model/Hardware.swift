import AppKit
import ClavimoCore
import ClavimoQuartz

/// What is connected, as far as ready-made setups need to know: a
/// trackpad, a separate mouse, keyboards with a PC layout, and other input
/// apps that may handle the same buttons.
struct Hardware: Equatable {
    struct Device: Equatable {
        var id: DeviceID
        var name: String
        var transport: String?
        var isKeyboard: Bool
        var isPointer: Bool
    }

    static let appleVendor = 1452
    static let logitechVendor = 1133

    var hasTrackpad = false
    var hasMouse = false
    /// Keyboards that are not made by Apple or Logitech and are not built
    /// in, usually with Alt and Windows keys where a Mac has Option and
    /// Command.
    var pcKeyboards: [Device] = []
    var hasLogitech = false
    /// Other input apps that are running, by name.
    var otherApps: [String] = []
    /// macOS trackpad gestures that are turned on.
    var systemGestures: Set<SystemTrackpadGestures.Gesture> = []

    var usesLogiOptions: Bool { otherApps.contains("Logi Options+") }

    init() {}

    init(devices: [Device], otherApps: [String] = [], systemGestures: Set<SystemTrackpadGestures.Gesture> = []) {
        self.otherApps = otherApps
        self.systemGestures = systemGestures
        for device in devices {
            let name = device.name.lowercased()
            let transport = device.transport?.lowercased() ?? ""
            let builtIn = transport.contains("spi") || transport.contains("fifo")
            let isTrackpad = (builtIn && device.isPointer) || name.contains("trackpad")
            if isTrackpad { hasTrackpad = true }
            if device.id.vendorID == Self.logitechVendor { hasLogitech = true }
            guard !builtIn, !isTrackpad else { continue }
            if device.isPointer {
                // Mice often expose a keyboard interface too; a Logitech
                // receiver looks like both.
                if name.contains("mouse") || !device.isKeyboard || device.id.vendorID == Self.logitechVendor {
                    hasMouse = true
                }
            } else if device.isKeyboard, device.id.vendorID != Self.appleVendor, device.id.vendorID != Self.logitechVendor {
                // Logitech keyboards switch to a Mac layout by themselves.
                pcKeyboards.append(device)
            }
        }
    }

    /// The devices connected now and the input apps running now.
    @MainActor
    static func current() -> Hardware {
        let devices = HIDDeviceCatalog.connectedDevices().map {
            Device(id: $0.id, name: $0.name, transport: $0.transport, isKeyboard: $0.isKeyboard, isPointer: $0.isPointer)
        }
        return Hardware(devices: devices, otherApps: AgentController.runningRemappers(),
                        systemGestures: SystemTrackpadGestures.enabled())
    }
}
