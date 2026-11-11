import ClavimoCore
import Foundation
import IOKit

/// Shares one `TouchBackend` between everything in the app that needs
/// touches: gesture rules and the live preview in settings. Touches are
/// read only while at least one subscriber exists. Connecting a trackpad
/// restarts the backend so new devices are picked up.
public final class TouchHub: @unchecked Sendable {
    public static let shared = TouchHub()

    /// Cancels itself when released.
    public final class Subscription: @unchecked Sendable {
        private let id: Int
        private weak var hub: TouchHub?
        private var cancelled = false

        fileprivate init(id: Int, hub: TouchHub) {
            self.id = id
            self.hub = hub
        }

        public func cancel() {
            guard !cancelled else { return }
            cancelled = true
            hub?.remove(id)
        }

        deinit { cancel() }
    }

    private let lock = NSLock()
    private var subscribers: [Int: TouchBackend.FrameHandler] = [:]
    private var nextID = 0
    private var backend: TouchBackend?
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let queue = DispatchQueue(label: "clavimo.touch")

    public init() {}

    /// Stopped when nobody subscribes.
    public var status: TouchBackend.Status {
        lock.withLock { backend?.status ?? .stopped }
    }

    public var devices: [TouchBackend.DeviceInfo] {
        lock.withLock { backend?.devices ?? [] }
    }

    /// `handler` runs on the framework's thread for every frame.
    public func subscribe(_ handler: @escaping TouchBackend.FrameHandler) -> Subscription {
        let (id, first) = lock.withLock {
            nextID += 1
            subscribers[nextID] = handler
            return (nextID, subscribers.count == 1)
        }
        if first { queue.async { self.startBackend() } }
        return Subscription(id: id, hub: self)
    }

    /// Re-reads the device list, for example after the Mac wakes.
    public func restart() {
        queue.async {
            guard self.lock.withLock({ !self.subscribers.isEmpty }) else { return }
            self.lock.withLock { self.backend }?.start()
        }
    }

    private func remove(_ id: Int) {
        let last = lock.withLock {
            subscribers[id] = nil
            return subscribers.isEmpty
        }
        if last { queue.async { self.stopBackend() } }
    }

    private func deliver(_ device: UInt64, _ frame: TouchFrame) {
        let handlers = lock.withLock { Array(subscribers.values) }
        for handler in handlers { handler(device, frame) }
    }

    // MARK: - Backend lifecycle (on `queue`)

    private func startBackend() {
        guard lock.withLock({ !self.subscribers.isEmpty && self.backend == nil }) else { return }
        let created = TouchBackend { [weak self] device, frame in self?.deliver(device, frame) }
        lock.withLock { self.backend = created }
        created.start()
        watchDevices()
    }

    private func stopBackend() {
        guard lock.withLock({ subscribers.isEmpty }) else { return }
        let stopping = lock.withLock {
            defer { self.backend = nil }
            return self.backend
        }
        stopping?.stop()
        unwatchDevices()
    }

    /// Restarts shortly after a multitouch device appears or disappears;
    /// the driver needs a moment before the device can be opened.
    private func devicesChanged() {
        queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let running = self.lock.withLock({ self.backend }) else { return }
            running.start()
        }
    }

    private func watchDevices() {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, queue)
        notificationPort = port
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"),
                                                          touchDevicesChanged, refcon, &iterator)
            guard result == KERN_SUCCESS else { continue }
            Self.drain(iterator)
            iterators.append(iterator)
        }
    }

    private func unwatchDevices() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
        notificationPort = nil
    }

    /// Notifications are re-armed only after the iterator is emptied.
    fileprivate static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    fileprivate func handleDeviceNotification(_ iterator: io_iterator_t) {
        Self.drain(iterator)
        devicesChanged()
    }
}

private let touchDevicesChanged: IOServiceMatchingCallback = { refcon, iterator in
    guard let refcon else { return }
    Unmanaged<TouchHub>.fromOpaque(refcon).takeUnretainedValue().handleDeviceNotification(iterator)
}

/// Turns frames from each trackpad into gestures and remembers what is on
/// the trackpad, for interpreting physical clicks. Thread safe.
final class TrackpadGestures: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizers: [UInt64: GestureRecognizer] = [:]
    private var snapshot = TouchSnapshot.empty
    private var snapshotTime: UInt64 = 0
    /// When fingers last turned as a rotation, for holding scrolling still.
    private var lastRotationTime: UInt64 = 0
    private var rotating = false

    /// Scrolling and its momentum stay still this long after a rotation.
    static let rotationScrollHold: UInt64 = 600_000_000

    /// A snapshot with fingers down is trusted this long without frames.
    static let fingersMaximumAge: UInt64 = 250_000_000
    /// A corner tap counts for tap to click this long.
    static let tappedCornerMaximumAge: UInt64 = 400_000_000

    func process(device: UInt64, frame: TouchFrame, now: UInt64) -> [(GestureEvent, TrackpadPoint?)] {
        lock.withLock {
            var recognizer = recognizers[device] ?? GestureRecognizer()
            let events = recognizer.process(frame)
            recognizers[device] = recognizer
            snapshot = recognizer.snapshot
            snapshotTime = now
            rotating = recognizers.values.contains { $0.isRotating }
            if rotating { lastRotationTime = now }
            return events.map { ($0, recognizer.lastGesturePoint) }
        }
    }

    /// Whether fingers are turning as a rotation, or just stopped.
    func holdsScrolling(now: UInt64) -> Bool {
        lock.withLock { rotating || (lastRotationTime != 0 && now &- lastRotationTime < Self.rotationScrollHold) }
    }

    func currentSnapshot(now: UInt64) -> TouchSnapshot {
        lock.withLock {
            let age = now &- snapshotTime
            var result = snapshot
            if age > Self.tappedCornerMaximumAge { result.tappedCorner = nil }
            if age > Self.fingersMaximumAge, result.fingers > 0 { return .empty }
            return result
        }
    }

    func reset() {
        lock.withLock {
            recognizers = [:]
            snapshot = .empty
        }
    }
}
