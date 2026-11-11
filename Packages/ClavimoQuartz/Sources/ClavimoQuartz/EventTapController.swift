import CoreGraphics
import Darwin
import Foundation
import ClavimoCore

/// Owns one session-level `CGEventTap` on a dedicated run loop thread and
/// feeds it through `InputEngine`. All engine access happens on that
/// thread, so the event path needs no locks.
///
/// Safety properties:
/// - Only key, flagsChanged, and other-mouse-button events are observed;
///   pointer movement, scrolling and primary/secondary clicks are never in
///   the mask.
/// - Our own synthetic events carry `syntheticTag` and are passed through
///   without evaluation.
/// - If macOS disables the tap, transient state is reset immediately and
///   re-enabling is rate limited; repeated failures stop the tap.
public final class EventTapController: @unchecked Sendable {
    public enum FlagRewriteMode: String, Sendable {
        /// Rewrite the modifier flags of the incoming event in place.
        case inPlace = "inplace"
        /// Consume the incoming key event and post a fresh one with the
        /// logical flags, so macOS derives characters from them.
        case repost
    }

    public enum StopReason: Equatable, Sendable {
        case requested
        case tooManyTapFailures
    }

    /// One input event as shown by the diagnostics inspector: a symbolic
    /// description only, kept in memory while the inspector is open.
    public struct InspectedEvent: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case key, modifier, mouse, scroll, gesture }
        public enum Outcome: Sendable, Equatable { case unchanged, changed, consumed, action }
        public let kind: Kind
        /// Key code, or mouse button number starting at 1.
        public let code: UInt16
        public let isDown: Bool
        public let outcome: Outcome
        public let callbackNanoseconds: UInt64
        /// The recognized trackpad gesture, for `.gesture` events.
        public var gesture: GestureEvent?
    }

    public struct Statistics: Sendable {
        public var passThrough: LatencyRecorder.Summary?
        public var handled: LatencyRecorder.Summary?
        public var eventsSeen: UInt64
        public var tapDisabledByTimeout: Int
        public var tapDisabledByUserInput: Int
        public var tapReenabled: Int
        /// Nil when no rule needs device attribution.
        public var deviceAttributionAvailable: Bool?
        /// Nil when no rule uses the trackpad.
        public var trackpad: TouchBackend.Status?
        public var gesturesRecognized: Int = 0
    }

    /// Marks events posted by Clavimo ("CLV1").
    public static let syntheticTag: Int64 = 0x434C_5631

    /// Events observed for every rule set.
    public static let baseEventMask: CGEventMask = mask(of: [.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp])

    /// The minimal mask for `rules`: primary and secondary clicks are added
    /// only when a rule explicitly uses them.
    public static func eventMask(for rules: CompiledRules) -> CGEventMask {
        var result = baseEventMask
        if rules.observesProtectedButtons || rules.observesTrackpadClicks {
            result |= mask(of: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
        }
        if rules.observesScrollWheel {
            result |= mask(of: [.scrollWheel])
        }
        return result
    }

    private static func mask(of types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }

    private let flagRewrite: FlagRewriteMode
    private let actionHandler: @Sendable (ActionCommand) -> Void
    private let onStop: @Sendable (StopReason) -> Void
    private let actionQueue = DispatchQueue(label: "clavimo.actions", qos: .userInteractive)
    private let source: CGEventSource?
    private let eventMask: CGEventMask
    private let keysNeedingDevice: Set<KeyCode>
    private let buttonsNeedingDevice: Set<MouseButton>
    private let usesDeviceConditions: Bool
    private let observesTrackpad: Bool
    private let observesTrackpadClicks: Bool
    private let gestures = TrackpadGestures()
    private var touchSubscription: TouchHub.Subscription?
    private var gesturesRecognized = 0

    // Tap-thread state.
    private var engine: InputEngine
    private var paused = false
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var deadlineTimer: CFRunLoopTimer?
    private var passThroughLatency = LatencyRecorder()
    private var handledLatency = LatencyRecorder()
    private var eventsSeen: UInt64 = 0
    private var disabledByTimeout = 0
    private var disabledByUserInput = 0
    private var reenableTimes: [UInt64] = []
    private var attributor: HIDDeviceAttributor?
    private var deviceAttributionAvailable = false
    private var smoothScroller = SmoothScroller()
    private var smoothTimer: CFRunLoopTimer?
    private var inspectorEnabled = false
    private var inspected: [InspectedEvent] = []
    private static let inspectorCapacity = 30

    public init(
        rules: CompiledRules,
        flagRewrite: FlagRewriteMode = .inPlace,
        actionHandler: @escaping @Sendable (ActionCommand) -> Void,
        onStop: @escaping @Sendable (StopReason) -> Void = { _ in }
    ) {
        engine = InputEngine(rules: rules)
        eventMask = Self.eventMask(for: rules)
        keysNeedingDevice = rules.keysNeedingDevice
        buttonsNeedingDevice = rules.buttonsNeedingDevice
        usesDeviceConditions = rules.usesDeviceConditions
        observesTrackpad = rules.observesTrackpad
        observesTrackpadClicks = rules.observesTrackpadClicks
        self.flagRewrite = flagRewrite
        self.actionHandler = actionHandler
        self.onStop = onStop
        source = CGEventSource(stateID: .privateState)
        source?.userData = Self.syntheticTag
    }

    public enum StartError: Error, Equatable {
        /// `CGEvent.tapCreate` returned nil, typically because the process
        /// lacks Accessibility or Input Monitoring permission.
        case tapCreationFailed
    }

    /// Creates the tap on a new thread and returns once it is installed.
    public func start() throws {
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var created = false
        let thread = Thread { [self] in
            created = installTap()
            ready.signal()
            if created { CFRunLoopRun() }
        }
        thread.name = "clavimo.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if !created { throw StartError.tapCreationFailed }
    }

    /// Releases held output, removes the tap and stops its thread.
    public func stop() {
        perform { [self] in shutDown(reason: .requested) }
    }

    /// Pausing resets transient state and forwards every event untouched.
    public func setPaused(_ isPaused: Bool) {
        perform { [self] in
            guard paused != isPaused else { return }
            if isPaused { resetEngine(insideCallback: nil) }
            paused = isPaused
        }
    }

    /// Updates the frontmost app used by app conditions. Called from
    /// workspace notifications, never looked up on the event path.
    public func setFrontmostApp(_ bundleID: String?) {
        perform { [self] in engine.setFrontmostApp(bundleID) }
    }

    /// Turns the input inspector on or off. Turning it off discards every
    /// recorded event.
    public func setInspectorEnabled(_ enabled: Bool) {
        perform { [self] in
            inspectorEnabled = enabled
            inspected.removeAll()
        }
    }

    public func inspectedEvents(_ completion: @escaping @Sendable ([InspectedEvent]) -> Void) {
        perform { [self] in completion(inspected) }
    }

    public func statistics(_ completion: @escaping @Sendable (Statistics) -> Void) {
        perform { [self] in
            completion(Statistics(
                passThrough: passThroughLatency.summary(),
                handled: handledLatency.summary(),
                eventsSeen: eventsSeen,
                tapDisabledByTimeout: disabledByTimeout,
                tapDisabledByUserInput: disabledByUserInput,
                tapReenabled: reenableTimes.count,
                deviceAttributionAvailable: usesDeviceConditions ? deviceAttributionAvailable : nil,
                trackpad: observesTrackpad ? TouchHub.shared.status : nil,
                gesturesRecognized: gesturesRecognized
            ))
        }
    }

    // MARK: - Tap lifecycle (tap thread)

    private func installTap() -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }
        guard let loop = CFRunLoopGetCurrent() else {
            CFMachPortInvalidate(port)
            return false
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(loop, runLoopSource, .commonModes)
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, .infinity, 1_000_000, 0, 0) { [weak self] _ in
            self?.deadlineFired()
        }
        CFRunLoopAddTimer(loop, timer, .commonModes)
        let smooth = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, .infinity, 1.0 / 120, 0, 0) { [weak self] _ in
            self?.smoothScrollFrame()
        }
        CFRunLoopAddTimer(loop, smooth, .commonModes)
        smoothTimer = smooth
        tap = port
        runLoop = loop
        deadlineTimer = timer
        if usesDeviceConditions {
            let attributor = HIDDeviceAttributor()
            deviceAttributionAvailable = attributor.start(on: loop)
            self.attributor = attributor
        }
        if observesTrackpad {
            touchSubscription = TouchHub.shared.subscribe { [weak self] device, frame in
                self?.receiveTouch(device: device, frame: frame)
            }
        }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    // MARK: - Trackpad (framework thread, then tap thread)

    private func receiveTouch(device: UInt64, frame: TouchFrame) {
        let events = gestures.process(device: device, frame: frame, now: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        for gesture in events {
            perform { [self] in handleGesture(gesture) }
        }
    }

    private func handleGesture(_ gesture: GestureEvent) {
        guard tap != nil, !paused else { return }
        gesturesRecognized += 1
        let output = engine.handleGesture(gesture)
        dispatchActions(output.actions)
        if inspectorEnabled {
            var event = InspectedEvent(kind: .gesture, code: 0, isDown: true,
                                       outcome: output.actions.isEmpty ? .unchanged : .action, callbackNanoseconds: 0)
            event.gesture = gesture
            if inspected.count >= Self.inspectorCapacity { inspected.removeFirst() }
            inspected.append(event)
        }
    }

    private func shutDown(reason: StopReason) {
        guard let port = tap else { return }
        resetEngine(insideCallback: nil)
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let deadlineTimer { CFRunLoopTimerInvalidate(deadlineTimer) }
        if let smoothTimer { CFRunLoopTimerInvalidate(smoothTimer) }
        smoothTimer = nil
        tap = nil
        deadlineTimer = nil
        attributor?.stop()
        attributor = nil
        touchSubscription?.cancel()
        touchSubscription = nil
        gestures.reset()
        if let runLoop { CFRunLoopStop(runLoop) }
        onStop(reason)
    }

    private func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Event path (tap thread)

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapWasDisabled(byTimeout: type == .tapDisabledByTimeout)
            return Unmanaged.passUnretained(event)
        }
        if paused || event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag {
            return Unmanaged.passUnretained(event)
        }
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        eventsSeen &+= 1
        if type == .scrollWheel {
            let keep = applyWheelSettings(event)
            passThroughLatency.record(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- start)
            return keep ? Unmanaged.passUnretained(event) : nil
        }
        guard let input = normalize(type: type, event: event, time: start) else {
            return Unmanaged.passUnretained(event)
        }
        let output = engine.handle(input)
        let isPlainPassThrough = output.items == [.original(flags: nil)] && output.actions.isEmpty
        let result = isPlainPassThrough ? Unmanaged.passUnretained(event) : apply(output, to: event, proxy: proxy)
        if !isPlainPassThrough || output.nextDeadline != nil {
            scheduleDeadline(output.nextDeadline, now: start)
        }
        let elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- start
        if isPlainPassThrough {
            passThroughLatency.record(elapsed)
        } else {
            handledLatency.record(elapsed)
        }
        if inspectorEnabled {
            inspect(input, type: type, output: output, plain: isPlainPassThrough, elapsed: elapsed)
        }
        return result
    }

    /// Applies wheel settings to discrete wheel events in place. Returns
    /// false when the event is consumed because smooth scrolling animates
    /// it instead. Continuous scrolling (trackpads, Magic Mouse) is
    /// identified by the system's continuous flag and left untouched; it
    /// also stops a running smooth animation.
    private func applyWheelSettings(_ event: CGEvent) -> Bool {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            if smoothScroller.isActive { stopSmoothScrolling() }
            return applyTrackpadScroll(event)
        }
        guard let settings = engine.wheelSettings(isContinuous: false, device: nil) else { return true }

        if case let .smoothed(vertical) = settings.vertical.mode {
            let notches = Self.notches(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, reverse: settings.vertical.reverse)
            addSmoothImpulse(vertical: notches, horizontal: 0, verticalSettings: vertical, horizontalSettings: .standard)
            Self.clear(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
        }
        if case let .smoothed(horizontal) = settings.horizontal.mode {
            let notches = Self.notches(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, reverse: settings.horizontal.reverse)
            addSmoothImpulse(vertical: 0, horizontal: notches, verticalSettings: .standard, horizontalSettings: horizontal)
            Self.clear(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        }

        var precise = false
        if settings.vertical.changesEvents, !settings.vertical.mode.isSmoothed {
            precise = Self.transform(event, settings.vertical, .scrollWheelEventDeltaAxis1,
                                     .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1) || precise
        }
        if settings.horizontal.changesEvents, !settings.horizontal.mode.isSmoothed {
            precise = Self.transform(event, settings.horizontal, .scrollWheelEventDeltaAxis2,
                                     .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2) || precise
        }
        if precise {
            // Pixel distances are only honored for precise (continuous)
            // scroll events; apps treat other wheel events as line counts.
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        }
        // Drop events that no longer move anything (fully animated).
        return event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) != 0
            || event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) != 0
            || event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0
            || event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) != 0
    }

    /// Continuous scrolling from trackpads and Magic Mouse: direction,
    /// speed and momentum. Phases are left untouched so apps still see a
    /// complete gesture. Returns false to drop a momentum event.
    private func applyTrackpadScroll(_ event: CGEvent) -> Bool {
        guard let settings = engine.trackpadScrollSettings() else { return true }
        if !settings.momentum, event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return false
        }
        for (vertical, fields) in [
            (true, (CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventFixedPtDeltaAxis1, CGEventField.scrollWheelEventPointDeltaAxis1)),
            (false, (CGEventField.scrollWheelEventDeltaAxis2, CGEventField.scrollWheelEventFixedPtDeltaAxis2, CGEventField.scrollWheelEventPointDeltaAxis2)),
        ] {
            let input = ScrollDeltas(lines: event.getIntegerValueField(fields.0), fixed: event.getDoubleValueField(fields.1),
                                     points: event.getIntegerValueField(fields.2))
            let output = settings.apply(to: input, vertical: vertical)
            guard output != input else { continue }
            event.setIntegerValueField(fields.0, value: output.lines)
            event.setDoubleValueField(fields.1, value: output.fixed)
            event.setIntegerValueField(fields.2, value: output.points)
        }
        return true
    }

    /// One notch per wheel event in its direction, ignoring the system's
    /// acceleration; fragments from high-resolution wheels count partially.
    private static func notches(_ event: CGEvent, _ lineField: CGEventField, _ fixedField: CGEventField, reverse: Bool) -> Double {
        let lines = event.getIntegerValueField(lineField)
        let fixed = event.getDoubleValueField(fixedField)
        var value = lines != 0 ? (lines > 0 ? 1.0 : -1.0) : fixed
        if reverse { value = -value }
        return value
    }

    private static func clear(_ event: CGEvent, _ line: CGEventField, _ fixed: CGEventField, _ point: CGEventField) {
        event.setIntegerValueField(line, value: 0)
        event.setDoubleValueField(fixed, value: 0)
        event.setIntegerValueField(point, value: 0)
    }

    private func addSmoothImpulse(vertical: Double, horizontal: Double, verticalSettings: SmoothScroller.Settings,
                                  horizontalSettings: SmoothScroller.Settings) {
        guard vertical != 0 || horizontal != 0 else { return }
        let started = smoothScroller.addImpulse(vertical: vertical, horizontal: horizontal, verticalSettings: verticalSettings,
                                                horizontalSettings: horizontalSettings, now: CFAbsoluteTimeGetCurrent())
        if started, let smoothTimer {
            CFRunLoopTimerSetNextFireDate(smoothTimer, CFAbsoluteTimeGetCurrent())
        }
    }

    private func smoothScrollFrame() {
        guard let frame = smoothScroller.step(now: CFAbsoluteTimeGetCurrent()) else {
            if let smoothTimer { CFRunLoopTimerSetNextFireDate(smoothTimer, .infinity) }
            return
        }
        postSmoothFrame(vertical: Int32(frame.vertical), horizontal: Int32(frame.horizontal), phase: frame.phase)
        if frame.phase == .ended, let smoothTimer {
            CFRunLoopTimerSetNextFireDate(smoothTimer, .infinity)
        }
    }

    /// Stops a running animation, ending its gesture cleanly.
    private func stopSmoothScrolling() {
        guard smoothScroller.isActive else { return }
        smoothScroller.cancel()
        postSmoothFrame(vertical: 0, horizontal: 0, phase: .ended)
        if let smoothTimer { CFRunLoopTimerSetNextFireDate(smoothTimer, .infinity) }
    }

    private func postSmoothFrame(vertical: Int32, horizontal: Int32, phase: SmoothScroller.Phase) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: vertical, wheel2: horizontal, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // kCGScrollPhaseBegan = 1, Changed = 2, Ended = 4.
        let phaseValue: Int64 = switch phase {
        case .began: 1
        case .changed: 2
        case .ended: 4
        }
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phaseValue)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        event.post(tap: .cgSessionEventTap)
    }

    /// Returns true when the axis now carries a pixel distance.
    private static func transform(
        _ event: CGEvent,
        _ settings: ScrollAxisSettings,
        _ lineField: CGEventField,
        _ fixedField: CGEventField,
        _ pointField: CGEventField
    ) -> Bool {
        let input = ScrollDeltas(
            lines: event.getIntegerValueField(lineField),
            fixed: event.getDoubleValueField(fixedField),
            points: event.getIntegerValueField(pointField)
        )
        let output = ScrollTransform.apply(settings, to: input)
        guard output != input else { return false }
        event.setIntegerValueField(lineField, value: output.lines)
        event.setDoubleValueField(fixedField, value: output.fixed)
        event.setIntegerValueField(pointField, value: output.points)
        if case .byPixels = settings.mode { return true }
        return false
    }

    private func normalize(type: CGEventType, event: CGEvent, time: UInt64) -> InputEvent? {
        let physical = QuartzFlags.modifiers(from: event.flags)
        switch type {
        case .keyDown, .keyUp:
            let code = KeyCode(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let isDown = type == .keyDown
            let device = isDown && !isRepeat ? attributedDevice(for: code) : nil
            return InputEvent(kind: .key(code, isDown: isDown, isRepeat: isRepeat), modifiers: physical, time: time, device: device)
        case .flagsChanged:
            let code = KeyCode(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
            // Caps Lock, Fn and unknown keys are forwarded uninterpreted.
            guard let modifier = code.modifierKey else { return nil }
            let isDown = physical.contains(modifier.set)
            let device = isDown ? attributedDevice(for: code) : nil
            return InputEvent(kind: .key(code, isDown: isDown, isRepeat: false), modifiers: physical, time: time, device: device)
        case .otherMouseDown, .otherMouseUp:
            let button = MouseButton(raw: UInt16(truncatingIfNeeded: event.getIntegerValueField(.mouseEventButtonNumber)))
            return mouseEvent(button, isDown: type == .otherMouseDown, physical: physical, time: time)
        case .leftMouseDown, .leftMouseUp:
            return mouseEvent(.primary, isDown: type == .leftMouseDown, physical: physical, time: time)
        case .rightMouseDown, .rightMouseUp:
            return mouseEvent(.secondary, isDown: type == .rightMouseDown, physical: physical, time: time)
        default:
            return nil
        }
    }

    private func inspect(_ input: InputEvent, type: CGEventType, output: EngineOutput, plain: Bool, elapsed: UInt64) {
        let outcome: InspectedEvent.Outcome = if !output.actions.isEmpty {
            .action
        } else if plain {
            .unchanged
        } else if output.items.isEmpty {
            .consumed
        } else {
            .changed
        }
        let event: InspectedEvent
        switch input.kind {
        case let .key(code, isDown, _):
            event = InspectedEvent(kind: type == .flagsChanged ? .modifier : .key, code: code.rawValue, isDown: isDown,
                                   outcome: outcome, callbackNanoseconds: elapsed)
        case let .mouseButton(button, isDown):
            event = InspectedEvent(kind: .mouse, code: UInt16(button.userFacingNumber), isDown: isDown,
                                   outcome: outcome, callbackNanoseconds: elapsed)
        }
        if inspected.count >= Self.inspectorCapacity { inspected.removeFirst() }
        inspected.append(event)
    }

    private func mouseEvent(_ button: MouseButton, isDown: Bool, physical: ModifierSet, time: UInt64) -> InputEvent {
        var device: DeviceID?
        if isDown, buttonsNeedingDevice.contains(button) {
            device = attributor?.deviceHolding(button: button)
        }
        var touch: TouchSnapshot?
        if isDown, observesTrackpadClicks, button.isProtected {
            touch = gestures.currentSnapshot(now: time)
        }
        return InputEvent(kind: .mouseButton(button, isDown: isDown), modifiers: physical, time: time, device: device, touch: touch)
    }

    /// Only keys used by device-scoped rules pay for the device query.
    private func attributedDevice(for key: KeyCode) -> DeviceID? {
        guard keysNeedingDevice.contains(key) else { return nil }
        return attributor?.deviceHolding(key: key)
    }

    private func apply(_ output: EngineOutput, to event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        dispatchActions(output.actions)
        let items = output.items
        if items.isEmpty { return nil }

        // One modifier output for one keyboard event: rewrite in place so
        // no synthetic event is needed.
        if items.count == 1, case let .key(code, isDown, _, flags) = items[0], code.modifierKey != nil, event.type.isKeyboard {
            _ = isDown
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(code.rawValue))
            event.flags = QuartzFlags.applying(flags, to: event.flags)
            return Unmanaged.passUnretained(event)
        }

        for (index, item) in items.enumerated() {
            switch item {
            case let .key(code, isDown, isRepeat, flags):
                if let synthetic = makeKeyEvent(code, isDown: isDown, isRepeat: isRepeat, flags: flags, base: event.flags) {
                    synthetic.tapPostEvent(proxy)
                }
            case let .original(flags):
                let isLast = index == items.count - 1
                if isLast, flags == nil {
                    return Unmanaged.passUnretained(event)
                }
                if isLast, let flags, flagRewrite == .inPlace || !event.type.isKeyboard {
                    event.flags = QuartzFlags.applying(flags, to: event.flags)
                    return Unmanaged.passUnretained(event)
                }
                if let flags, event.type.isKeyboard, flagRewrite == .repost {
                    let code = KeyCode(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    makeKeyEvent(code, isDown: event.type == .keyDown, isRepeat: isRepeat, flags: flags, base: event.flags)?
                        .tapPostEvent(proxy)
                } else if let copy = event.copy() {
                    if let flags { copy.flags = QuartzFlags.applying(flags, to: copy.flags) }
                    copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
                    copy.tapPostEvent(proxy)
                }
            }
        }
        return nil
    }

    private func makeKeyEvent(_ code: KeyCode, isDown: Bool, isRepeat: Bool, flags: ModifierSet, base: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code.rawValue, keyDown: isDown) else { return nil }
        if code.modifierKey != nil { event.type = .flagsChanged }
        event.flags = QuartzFlags.applying(flags, to: base)
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        return event
    }

    /// Posts engine output produced outside the tap callback (timers,
    /// resets). These events re-enter the tap and pass by their tag.
    private func postOutsideCallback(_ output: EngineOutput) {
        dispatchActions(output.actions)
        let base = CGEventSource.flagsState(.combinedSessionState)
        for case let .key(code, isDown, isRepeat, flags) in output.items {
            makeKeyEvent(code, isDown: isDown, isRepeat: isRepeat, flags: flags, base: base)?.post(tap: .cgSessionEventTap)
        }
    }

    private func dispatchActions(_ actions: [ActionCommand]) {
        guard !actions.isEmpty else { return }
        let handler = actionHandler
        actionQueue.async {
            for action in actions { handler(action) }
        }
    }

    // MARK: - Deadlines and recovery (tap thread)

    private func scheduleDeadline(_ deadline: UInt64?, now: UInt64) {
        guard let deadlineTimer else { return }
        guard let deadline else {
            CFRunLoopTimerSetNextFireDate(deadlineTimer, .infinity)
            return
        }
        let delay = deadline > now ? Double(deadline - now) / 1_000_000_000 : 0
        CFRunLoopTimerSetNextFireDate(deadlineTimer, CFAbsoluteTimeGetCurrent() + delay)
    }

    private func deadlineFired() {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let output = engine.handleDeadline(now: now)
        postOutsideCallback(output)
        scheduleDeadline(output.nextDeadline, now: now)
    }

    private func resetEngine(insideCallback _: CGEventTapProxy?) {
        stopSmoothScrolling()
        let output = engine.reset()
        postOutsideCallback(output)
        if let deadlineTimer { CFRunLoopTimerSetNextFireDate(deadlineTimer, .infinity) }
    }

    private static let maxReenablesPerMinute = 5

    private func tapWasDisabled(byTimeout: Bool) {
        if byTimeout { disabledByTimeout += 1 } else { disabledByUserInput += 1 }
        // State is uncertain once events were missed: fail open first.
        resetEngine(insideCallback: nil)
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        reenableTimes.removeAll { now &- $0 > 60_000_000_000 }
        guard reenableTimes.count < Self.maxReenablesPerMinute, let tap else {
            shutDown(reason: .tooManyTapFailures)
            return
        }
        reenableTimes.append(now)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.handle(proxy: proxy, type: type, event: event)
}

extension CGEventType {
    var isKeyboard: Bool {
        self == .keyDown || self == .keyUp || self == .flagsChanged
    }
}
