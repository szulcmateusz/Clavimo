import ClavimoCore
import Foundation
import Testing
@testable import ClavimoQuartz

@Suite("Multitouch decoding")
struct TouchDecodingTests {
    /// Builds raw MTTouch records the way the framework lays them out.
    func record(id: Int32, state: Int32, x: Float, y: Float, major: Float) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: MTTouchLayout.stride)
        func put<T>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value) { raw in
                for (index, byte) in raw.enumerated() { bytes[offset + index] = byte }
            }
        }
        put(id, at: MTTouchLayout.identifier)
        put(state, at: MTTouchLayout.state)
        put(x, at: MTTouchLayout.normalizedX)
        put(y, at: MTTouchLayout.normalizedY)
        put(major, at: MTTouchLayout.majorAxis)
        return bytes
    }

    @Test func decodesFieldsAtTheirOffsets() {
        let buffer = record(id: 7, state: 4, x: 0.25, y: 0.75, major: 9.5) + record(id: 8, state: 5, x: 0.9, y: 0.1, major: 8)
        let decoded = buffer.withUnsafeBytes { MTTouchLayout.decode($0.baseAddress, count: 2) }
        #expect(decoded.count == 2)
        #expect(decoded[0].identifier == 7 && decoded[0].rawState == 4)
        #expect(decoded[0].x == 0.25 && decoded[0].y == 0.75 && decoded[0].majorAxis == 9.5)
        #expect(decoded[1].identifier == 8 && decoded[1].rawState == 5)
    }

    @Test func refusesImplausibleCounts() {
        #expect(MTTouchLayout.decode(nil, count: 3).isEmpty)
        let buffer = record(id: 1, state: 4, x: 0.5, y: 0.5, major: 9)
        #expect(buffer.withUnsafeBytes { MTTouchLayout.decode($0.baseAddress, count: 0) }.isEmpty)
    }

    @Test func validatorAcceptsRealisticFrames() {
        var validator = TouchFrameValidator()
        let first = validator.check(count: 2, states: [3, 4], positions: [(0.1, 0.2), (0.8, 0.9)])
        let empty = validator.check(count: 0, states: [], positions: [])
        #expect(first && empty)
        #expect(!validator.isBroken)
        #expect(validator.validFrames == 2)
    }

    @Test func validatorGivesUpOnGarbage() {
        var validator = TouchFrameValidator()
        for _ in 0..<TouchFrameValidator.failureLimit {
            let plausible = validator.check(count: 1, states: [912], positions: [(Float.nan, 4000)])
            #expect(!plausible)
        }
        #expect(validator.isBroken)
    }

    @Test func oneGoodFrameResetsTheFailureCount() {
        var validator = TouchFrameValidator()
        for _ in 0..<(TouchFrameValidator.failureLimit - 1) {
            validator.check(count: 1, states: [4], positions: [(5, 5)])
        }
        validator.check(count: 1, states: [4], positions: [(0.5, 0.5)])
        #expect(!validator.isBroken)
    }
}

@Suite("Trackpad gesture state")
struct TrackpadGesturesTests {
    func frame(_ time: Double, _ points: [(Int32, Float, Float)]) -> TouchFrame {
        TouchFrame(time: time, contacts: points.map { TouchContact(id: $0.0, state: .touching, x: $0.1, y: $0.2) })
    }

    @Test func snapshotExpiresWhenFramesStop() {
        let gestures = TrackpadGestures()
        _ = gestures.process(device: 1, frame: frame(1, [(1, 0.3, 0.5), (2, 0.4, 0.5), (3, 0.5, 0.5)]), now: 1_000_000_000)
        #expect(gestures.currentSnapshot(now: 1_100_000_000).fingers == 3)
        #expect(gestures.currentSnapshot(now: 1_400_000_000) == .empty, "fingers without fresh frames are not trusted")
    }

    @Test func cornerTapIsForgottenAfterAWhile() {
        let gestures = TrackpadGestures()
        _ = gestures.process(device: 1, frame: frame(1, [(1, 0.95, 0.95)]), now: 1_000_000_000)
        _ = gestures.process(device: 1, frame: frame(1.05, []), now: 1_050_000_000)
        #expect(gestures.currentSnapshot(now: 1_100_000_000).tappedCorner == .topRight)
        #expect(gestures.currentSnapshot(now: 1_600_000_000).tappedCorner == nil)
    }

    @Test func gesturesAreRecognizedPerDevice() {
        let gestures = TrackpadGestures()
        var events: [GestureEvent] = []
        events += gestures.process(device: 1, frame: frame(1, [(1, 0.3, 0.5), (2, 0.4, 0.5), (3, 0.5, 0.5)]), now: 1)
        events += gestures.process(device: 2, frame: frame(1.01, [(9, 0.5, 0.5)]), now: 2)
        events += gestures.process(device: 1, frame: frame(1.08, []), now: 3)
        #expect(events == [.tap(fingers: 3)])
    }
}
