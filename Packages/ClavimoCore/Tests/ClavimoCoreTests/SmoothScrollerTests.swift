import Testing
@testable import ClavimoCore

@Suite("Smooth scrolling")
struct SmoothScrollerTests {
    static let settings = SmoothScroller.Settings(pixelsPerNotch: 60, duration: 0.25)

    func run(_ scroller: inout SmoothScroller, from start: Double, frames: Int, interval: Double = 1.0 / 120) -> [SmoothScroller.Frame] {
        var result: [SmoothScroller.Frame] = []
        for index in 1...frames {
            guard let frame = scroller.step(now: start + Double(index) * interval) else { break }
            result.append(frame)
            if frame.phase == .ended { break }
        }
        return result
    }

    @Test func oneNotchScrollsExactlyItsDistanceAndEnds() {
        var scroller = SmoothScroller()
        let started = scroller.addImpulse(vertical: 1, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        #expect(started)
        let frames = run(&scroller, from: 0, frames: 600)
        #expect(frames.first?.phase == .began)
        #expect(frames.last?.phase == .ended)
        #expect(frames.map(\.vertical).reduce(0, +) == 60, "whole pixels add up to the exact distance")
        #expect(frames.allSatisfy { $0.horizontal == 0 })
        #expect(!scroller.isActive)
        let duration = Double(frames.count) / 120
        #expect(duration < 0.5, "settles shortly after the configured duration: \(duration)s")
    }

    @Test func movementEasesOut() {
        var scroller = SmoothScroller()
        scroller.addImpulse(vertical: 2, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        let frames = run(&scroller, from: 0, frames: 600).map(\.vertical)
        #expect(frames.first! > frames[frames.count / 2], "faster at the start than in the middle")
    }

    @Test func impulsesInTheSameDirectionAccumulate() {
        var scroller = SmoothScroller()
        scroller.addImpulse(vertical: 1, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        _ = scroller.step(now: 0.01)
        let restarted = scroller.addImpulse(vertical: 1, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0.01)
        #expect(!restarted, "an impulse during an animation extends it")
        let rest = run(&scroller, from: 0.01, frames: 600)
        #expect(rest.last?.phase == .ended)
    }

    @Test func reversingDirectionCancelsRemainingDistance() {
        var scroller = SmoothScroller()
        scroller.addImpulse(vertical: 5, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        let first = scroller.step(now: 1.0 / 120)!.vertical
        scroller.addImpulse(vertical: -1, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 1.0 / 120)
        let rest = run(&scroller, from: 1.0 / 120, frames: 600)
        #expect(first > 0)
        #expect(rest.allSatisfy { $0.vertical <= 0 }, "no movement continues in the old direction")
        #expect(rest.map(\.vertical).reduce(0, +) == -60)
    }

    @Test func pendingDistanceIsCappedAndAnimationEnds() {
        var scroller = SmoothScroller()
        for _ in 0..<200 {
            scroller.addImpulse(vertical: 1, horizontal: 0, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        }
        let frames = run(&scroller, from: 0, frames: 10_000)
        #expect(frames.map(\.vertical).reduce(0, +) <= SmoothScroller.maximumPendingNotches * 60)
        #expect(Double(frames.count) / 120 <= SmoothScroller.maximumDuration + 0.01)
        #expect(frames.last?.phase == .ended)
    }

    @Test func cancelStopsImmediately() {
        var scroller = SmoothScroller()
        scroller.addImpulse(vertical: 3, horizontal: 1, verticalSettings: Self.settings, horizontalSettings: Self.settings, now: 0)
        scroller.cancel()
        let frame = scroller.step(now: 0.1)
        #expect(frame == nil)
        #expect(!scroller.isActive)
    }

    @Test func settingsAreClampedToSafeRanges() {
        var scroller = SmoothScroller()
        let extreme = SmoothScroller.Settings(pixelsPerNotch: 10_000, duration: 100)
        scroller.addImpulse(vertical: 1, horizontal: 0, verticalSettings: extreme, horizontalSettings: extreme, now: 0)
        let frames = run(&scroller, from: 0, frames: 10_000)
        #expect(frames.map(\.vertical).reduce(0, +) == SmoothScroller.Settings.pixelsRange.upperBound)
    }
}
