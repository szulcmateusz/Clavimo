import ClavimoCore
import CoreFoundation
import Darwin
import Foundation
import os

/// Reads finger positions from trackpads through Apple's private
/// MultitouchSupport framework, the same way MiddleClick, Jitouch and
/// BetterTouchTool do. There is no public API for raw touches.
///
/// The framework is loaded at run time with `dlopen`; if it or any symbol
/// is missing, the backend reports itself unavailable and does nothing.
/// Decoded frames are validated; if macOS changes the private structure
/// and frames stop making sense, the backend stops itself. It only
/// observes touches and never changes what macOS does with them.
///
/// Touch data stays in memory and is handed to `onFrame` on the
/// framework's own thread.
public final class TouchBackend: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case stopped
        case running(devices: Int)
        case unavailable(Unavailable)
    }

    public enum Unavailable: Equatable, Sendable {
        /// The private framework or one of its functions is missing.
        case frameworkMissing
        /// No multitouch device is connected.
        case noDevices
        /// Frames no longer decode to plausible values.
        case dataLayoutChanged
    }

    public struct DeviceInfo: Equatable, Sendable {
        public var id: UInt64
        public var familyID: Int32
        public var isBuiltIn: Bool
    }

    /// Called for every frame of every device: (device id, frame).
    public typealias FrameHandler = @Sendable (UInt64, TouchFrame) -> Void

    private let onFrame: FrameHandler
    /// Diagnostic hook for the probe: raw bytes of the first contacts of
    /// frames with touches, to inspect the private structure on new macOS
    /// versions. Never set by the app.
    private let rawDump: (@Sendable (Data) -> Void)?
    private let state = StateLock()

    /// CFArray and raw device pointers are not Sendable; every access goes
    /// through this lock.
    private final class StateLock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = State()

        func withLock<R>(_ body: (inout State) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private struct State {
        var list: CFArray?
        var devices: [UnsafeMutableRawPointer: DeviceInfo] = [:]
        var validator = TouchFrameValidator()
        var status: Status = .stopped
    }

    public init(onFrame: @escaping FrameHandler, rawDump: (@Sendable (Data) -> Void)? = nil) {
        self.onFrame = onFrame
        self.rawDump = rawDump
    }

    public var status: Status { state.withLock { $0.status } }

    /// Starts listening on every connected multitouch device. Safe to call
    /// again; it restarts with the current device list.
    @discardableResult
    public func start() -> Status {
        stop()
        guard let api = MultitouchAPI.shared else {
            return setStatus(.unavailable(.frameworkMissing))
        }
        guard let list = api.createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            return setStatus(.unavailable(.noDevices))
        }
        var devices: [UnsafeMutableRawPointer: DeviceInfo] = [:]
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index).map(UnsafeMutableRawPointer.init(mutating:)) else { continue }
            var family: Int32 = 0
            _ = api.getFamilyID(device, &family)
            var deviceID: UInt64 = 0
            _ = api.getDeviceID(device, &deviceID)
            devices[device] = DeviceInfo(id: deviceID, familyID: family, isBuiltIn: api.isBuiltIn(device))
        }
        state.withLock {
            $0.list = list
            $0.devices = devices
            $0.validator = TouchFrameValidator()
            $0.status = .running(devices: devices.count)
        }
        TouchBackendRegistry.current.withLock { $0 = self }
        for device in devices.keys {
            api.register(device, touchFrameCallback)
            api.start(device, 0)
        }
        return .running(devices: devices.count)
    }

    /// Stops listening and releases the devices.
    public func stop() {
        let devices: [UnsafeMutableRawPointer] = state.withLock { state in
            let devices = Array(state.devices.keys)
            state.devices = [:]
            return devices
        }
        if let api = MultitouchAPI.shared {
            for device in devices {
                api.unregister(device, touchFrameCallback)
                api.stop(device)
            }
        }
        TouchBackendRegistry.current.withLock { if $0 === self { $0 = nil } }
        state.withLock { state in
            state.list = nil
            if case .running = state.status { state.status = .stopped }
        }
    }

    public var devices: [DeviceInfo] {
        state.withLock { Array($0.devices.values) }.sorted { $0.id < $1.id }
    }

    /// Number of plausible frames received since start.
    public var validFrames: Int { state.withLock { $0.validator.validFrames } }

    private func setStatus(_ status: Status) -> Status {
        state.withLock { $0.status = status }
        return status
    }

    // MARK: - Frames (framework thread)

    fileprivate func receive(device: UnsafeMutableRawPointer, touches: UnsafeRawPointer?, count: Int, timestamp: Double) {
        if let rawDump, let touches, count > 0 {
            rawDump(Data(bytes: touches, count: min(count, 2) * MTTouchLayout.stride))
        }
        let decoded = MTTouchLayout.decode(touches, count: count)
        let outcome: (info: DeviceInfo, plausible: Bool, broken: Bool)? = state.withLock { state in
            guard let info = state.devices[device] else { return nil }
            let plausible = state.validator.check(count: count, states: decoded.map(\.rawState),
                                                  positions: decoded.map { ($0.x, $0.y) })
            return (info, plausible, state.validator.isBroken)
        }
        guard let outcome else { return }
        if outcome.broken {
            stop()
            _ = setStatus(.unavailable(.dataLayoutChanged))
            return
        }
        guard outcome.plausible else { return }
        let contacts = decoded.compactMap { touch -> TouchContact? in
            guard let state = TouchState(rawValue: touch.rawState) else { return nil }
            return TouchContact(id: touch.identifier, state: state, x: touch.x, y: touch.y, size: touch.majorAxis)
        }
        onFrame(outcome.info.id, TouchFrame(time: timestamp, contacts: contacts))
    }
}

/// The backend receiving frames. The framework's callback has no context
/// pointer in its unregister-able form, so the single running backend is
/// kept here.
private enum TouchBackendRegistry {
    static let current = OSAllocatedUnfairLock<TouchBackend?>(initialState: nil)
}

private let touchFrameCallback: MultitouchAPI.FrameCallback = { device, touches, count, timestamp, _ in
    guard let device, let backend = TouchBackendRegistry.current.withLock({ $0 }) else { return }
    backend.receive(device: device, touches: touches.map(UnsafeRawPointer.init), count: Int(count), timestamp: timestamp)
}

/// Field offsets of the private `MTTouch` structure (96 bytes), as
/// declared by open source projects using the framework.
enum MTTouchLayout {
    static let stride = 96
    static let identifier = 16
    static let state = 20
    static let normalizedX = 32
    static let normalizedY = 36
    static let majorAxis = 60

    struct Decoded {
        var identifier: Int32
        var rawState: Int32
        var x: Float
        var y: Float
        var majorAxis: Float
    }

    static func decode(_ pointer: UnsafeRawPointer?, count: Int) -> [Decoded] {
        guard let pointer, count > 0, count <= TouchFrameValidator.maximumContacts else { return [] }
        return (0..<count).map { index in
            let base = pointer + index * stride
            return Decoded(
                identifier: base.loadUnaligned(fromByteOffset: identifier, as: Int32.self),
                rawState: base.loadUnaligned(fromByteOffset: state, as: Int32.self),
                x: base.loadUnaligned(fromByteOffset: normalizedX, as: Float.self),
                y: base.loadUnaligned(fromByteOffset: normalizedY, as: Float.self),
                majorAxis: base.loadUnaligned(fromByteOffset: majorAxis, as: Float.self)
            )
        }
    }
}

/// Function pointers resolved from the private framework.
struct MultitouchAPI: @unchecked Sendable {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void

    let createList: @convention(c) () -> Unmanaged<CFArray>?
    let register: @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    let unregister: @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    let stop: @convention(c) (UnsafeMutableRawPointer) -> Void
    let isBuiltIn: @convention(c) (UnsafeMutableRawPointer) -> Bool
    let getFamilyID: @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32
    let getDeviceID: @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32

    static let shared: MultitouchAPI? = load()

    private static func load() -> MultitouchAPI? {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        guard
            let createList = symbol("MTDeviceCreateList", as: (@convention(c) () -> Unmanaged<CFArray>?).self),
            let register = symbol("MTRegisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void).self),
            let unregister = symbol("MTUnregisterContactFrameCallback", as: (@convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void).self),
            let start = symbol("MTDeviceStart", as: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void).self),
            let stop = symbol("MTDeviceStop", as: (@convention(c) (UnsafeMutableRawPointer) -> Void).self),
            let isBuiltIn = symbol("MTDeviceIsBuiltIn", as: (@convention(c) (UnsafeMutableRawPointer) -> Bool).self),
            let getFamilyID = symbol("MTDeviceGetFamilyID", as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32).self),
            let getDeviceID = symbol("MTDeviceGetDeviceID", as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32).self)
        else { return nil }
        return MultitouchAPI(createList: createList, register: register, unregister: unregister, start: start, stop: stop,
                             isBuiltIn: isBuiltIn, getFamilyID: getFamilyID, getDeviceID: getDeviceID)
    }
}
