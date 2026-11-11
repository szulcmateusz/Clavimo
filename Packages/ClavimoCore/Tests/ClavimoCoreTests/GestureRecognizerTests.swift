import Testing
@testable import ClavimoCore

/// Plays fingers on a simulated trackpad at 100 frames per second.
struct TouchScript {
    var recognizer = GestureRecognizer()
    var time = 10.0
    var fingers: [Int32: (x: Float, y: Float)] = [:]
    var events: [GestureEvent] = []

    mutating func frame() {
        let contacts = fingers.map { TouchContact(id: $0.key, state: .touching, x: $0.value.x, y: $0.value.y) }
        events += recognizer.process(TouchFrame(time: time, contacts: contacts))
        time += 0.01
    }

    mutating func wait(_ seconds: Double) {
        let frames = Int((seconds / 0.01).rounded())
        for _ in 0..<frames { frame() }
    }

    mutating func down(_ id: Int32, _ x: Float, _ y: Float) {
        fingers[id] = (x, y)
        frame()
    }

    mutating func up(_ id: Int32) {
        fingers[id] = nil
        frame()
    }

    /// Moves the given fingers by (dx, dy) over `seconds`.
    mutating func move(_ ids: [Int32], dx: Float, dy: Float, over seconds: Double) {
        let steps = max(1, Int((seconds / 0.01).rounded()))
        for _ in 0..<steps {
            for id in ids {
                if let finger = fingers[id] {
                    fingers[id] = (finger.x + dx / Float(steps), finger.y + dy / Float(steps))
                }
            }
            frame()
        }
    }

    mutating func tap(_ count: Int, at x: Float = 0.5, y: Float = 0.5, hold: Double = 0.08) {
        let ids = (0..<count).map { Int32(100 + $0) }
        for (index, id) in ids.enumerated() { fingers[id] = (x + Float(index) * 0.08, y) }
        frame()
        wait(hold)
        for id in ids { fingers[id] = nil }
        frame()
    }
}

@Suite("Gesture recognition")
struct GestureRecognizerTests {
    @Test(arguments: [2, 3, 4, 5])
    func quickStillTapReportsFingerCount(fingers: Int) {
        var script = TouchScript()
        script.tap(fingers)
        #expect(script.events == [.tap(fingers: fingers)])
        #expect(script.recognizer.isIdle)
    }

    @Test func oneFingerTapIsLeftToMacOS() {
        var script = TouchScript()
        script.tap(1)
        #expect(script.events.isEmpty)
    }

    @Test func slowTapIsNotATap() {
        var script = TouchScript()
        script.tap(3, hold: 0.6)
        #expect(script.events.isEmpty)
    }

    @Test func movingFingersAreNotATap() {
        var script = TouchScript()
        script.down(1, 0.4, 0.5)
        script.down(2, 0.5, 0.5)
        script.down(3, 0.6, 0.5)
        script.move([1, 2, 3], dx: 0, dy: 0.07, over: 0.1)
        script.up(1); script.up(2); script.up(3)
        #expect(script.events.isEmpty)
    }

    @Test func fingersLandingFarApartAreNotATap() {
        var script = TouchScript()
        script.down(1, 0.4, 0.5)
        script.wait(0.25)
        script.down(2, 0.5, 0.5)
        script.down(3, 0.6, 0.5)
        script.up(1); script.up(2); script.up(3)
        #expect(!script.events.contains(.tap(fingers: 3)))
    }

    @Test(arguments: [
        (dx: Float(0.3), dy: Float(0), direction: GestureEvent.Direction.right),
        (dx: -0.3, dy: 0, direction: .left),
        (dx: 0, dy: 0.3, direction: .up),
        (dx: 0, dy: -0.3, direction: .down),
    ])
    func threeFingerSwipe(dx: Float, dy: Float, direction: GestureEvent.Direction) {
        var script = TouchScript()
        script.down(1, 0.4, 0.5)
        script.down(2, 0.5, 0.5)
        script.down(3, 0.6, 0.5)
        script.move([1, 2, 3], dx: dx, dy: dy, over: 0.2)
        script.up(1); script.up(2); script.up(3)
        #expect(script.events == [.swipe(fingers: 3, direction)])
    }

    @Test func fourFingerSwipeCountsFourFingers() {
        var script = TouchScript()
        for id: Int32 in 1...4 { script.down(id, 0.3 + Float(id) * 0.1, 0.5) }
        script.move([1, 2, 3, 4], dx: 0, dy: 0.25, over: 0.15)
        for id: Int32 in 1...4 { script.up(id) }
        #expect(script.events == [.swipe(fingers: 4, .up)])
    }

    @Test func diagonalMovementIsNotASwipe() {
        var script = TouchScript()
        script.down(1, 0.3, 0.3)
        script.down(2, 0.4, 0.3)
        script.down(3, 0.5, 0.3)
        script.move([1, 2, 3], dx: 0.2, dy: 0.2, over: 0.2)
        script.up(1); script.up(2); script.up(3)
        #expect(script.events.isEmpty)
    }

    @Test func slowThreeFingerDragIsNotASwipe() {
        var script = TouchScript()
        script.down(1, 0.3, 0.5)
        script.down(2, 0.4, 0.5)
        script.down(3, 0.5, 0.5)
        script.move([1, 2, 3], dx: 0.3, dy: 0, over: 3)
        script.up(1); script.up(2); script.up(3)
        #expect(script.events.isEmpty)
    }

    @Test func twoFingerScrollIsNeverASwipe() {
        var script = TouchScript()
        script.down(1, 0.4, 0.5)
        script.down(2, 0.5, 0.5)
        script.move([1, 2], dx: 0, dy: 0.4, over: 0.2)
        script.up(1); script.up(2)
        #expect(script.events.isEmpty)
    }

    @Test func onlyOneSwipePerSession() {
        var script = TouchScript()
        script.down(1, 0.2, 0.5)
        script.down(2, 0.3, 0.5)
        script.down(3, 0.4, 0.5)
        script.move([1, 2, 3], dx: 0.25, dy: 0, over: 0.15)
        script.move([1, 2, 3], dx: -0.25, dy: 0, over: 0.15)
        script.up(1); script.up(2); script.up(3)
        #expect(script.events == [.swipe(fingers: 3, .right)])
    }

    @Test(arguments: [(x: Float(0.7), side: GestureEvent.Side.right), (x: 0.3, side: .left)])
    func tipTapReportsSide(x: Float, side: GestureEvent.Side) {
        var script = TouchScript()
        script.down(1, 0.5, 0.4)
        script.wait(0.2)
        script.down(2, x, 0.45)
        script.wait(0.06)
        script.up(2)
        script.wait(0.1)
        script.up(1)
        #expect(script.events == [.tipTap(side)])
    }

    @Test func repeatedTipTapsWhileResting() {
        var script = TouchScript()
        script.down(1, 0.5, 0.4)
        script.wait(0.2)
        for _ in 0..<3 {
            script.down(2, 0.7, 0.4)
            script.wait(0.05)
            script.up(2)
            script.wait(0.1)
        }
        script.up(1)
        #expect(script.events == Array(repeating: .tipTap(.right), count: 3))
    }

    @Test func movingAnchorCancelsTipTap() {
        var script = TouchScript()
        script.down(1, 0.5, 0.4)
        script.move([1], dx: 0.2, dy: 0, over: 0.2)
        script.down(2, 0.8, 0.4)
        script.wait(0.05)
        script.up(2)
        script.up(1)
        #expect(script.events.isEmpty)
    }

    @Test func snapshotCountsFingersAndCorners() {
        var script = TouchScript()
        script.down(1, 0.95, 0.95)
        #expect(script.recognizer.snapshot == TouchSnapshot(fingers: 1, corner: .topRight))
        script.down(2, 0.5, 0.5)
        #expect(script.recognizer.snapshot == TouchSnapshot(fingers: 2))
        script.up(1); script.up(2)
        #expect(script.recognizer.snapshot.fingers == 0)
    }

    @Test(arguments: [
        (x: Float(0.05), y: Float(0.95), corner: TrackpadCorner.topLeft),
        (x: 0.95, y: 0.95, corner: .topRight),
        (x: 0.05, y: 0.05, corner: .bottomLeft),
        (x: 0.95, y: 0.05, corner: .bottomRight),
    ])
    func oneFingerTapInCornerIsRememberedBriefly(x: Float, y: Float, corner: TrackpadCorner) {
        var script = TouchScript()
        script.tap(1, at: x, y: y)
        #expect(script.recognizer.snapshot.tappedCorner == corner)
        script.wait(0.5)
        #expect(script.recognizer.snapshot.tappedCorner == nil)
    }

    @Test func tapInTheMiddleHasNoCorner() {
        var script = TouchScript()
        script.tap(1, at: 0.5, y: 0.5)
        #expect(script.recognizer.snapshot.tappedCorner == nil)
    }

    @Test func resetForgetsEverything() {
        var script = TouchScript()
        script.down(1, 0.5, 0.5)
        script.down(2, 0.6, 0.5)
        script.recognizer.reset()
        #expect(script.recognizer.isIdle)
        #expect(script.recognizer.snapshot == .empty)
    }

    /// Random finger activity: the recognizer must never report a gesture
    /// that contradicts the fingers it saw, and must be idle once every
    /// finger has lifted.
    @Test func randomTouchesStayConsistent() {
        for seed in 0..<300 {
            var rng = SplitMix64(seed: UInt64(seed))
            var script = TouchScript()
            var maxDown = 0
            for _ in 0..<300 {
                switch rng.next(10) {
                case 0..<3:
                    let id = Int32(rng.next(6))
                    if script.fingers[id] == nil {
                        script.fingers[id] = (Float(rng.next(100)) / 100, Float(rng.next(100)) / 100)
                    } else {
                        script.fingers[id] = nil
                    }
                case 3..<7:
                    for id in script.fingers.keys {
                        let finger = script.fingers[id]!
                        script.fingers[id] = (min(1, max(0, finger.x + Float(rng.next(21) - 10) / 200)),
                                              min(1, max(0, finger.y + Float(rng.next(21) - 10) / 200)))
                    }
                default:
                    break
                }
                maxDown = max(maxDown, script.fingers.count)
                script.frame()
            }
            script.fingers = [:]
            script.frame()
            #expect(script.recognizer.isIdle, "seed \(seed)")
            for event in script.events {
                switch event {
                case let .tap(fingers): #expect((2...maxDown).contains(fingers), "seed \(seed)")
                case let .swipe(fingers, _): #expect((3...maxDown).contains(fingers), "seed \(seed)")
                case .tipTap: #expect(maxDown >= 2, "seed \(seed)")
                }
            }
        }
    }
}
