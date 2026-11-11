import Testing
@testable import ClavimoCore

@Suite("Scroll transform")
struct ScrollTransformTests {
    static let notchDown = ScrollDeltas(lines: -1, fixed: -1, points: -10)
    static let fastSpinUp = ScrollDeltas(lines: 4, fixed: 4.5, points: 45)

    @Test func unchangedSettingsKeepEventIntact() {
        #expect(ScrollTransform.apply(.unchanged, to: Self.fastSpinUp) == Self.fastSpinUp)
    }

    @Test func reverseNegatesAllFields() {
        let reversed = ScrollTransform.apply(ScrollAxisSettings(reverse: true), to: Self.fastSpinUp)
        #expect(reversed == ScrollDeltas(lines: -4, fixed: -4.5, points: -45))
    }

    @Test func byLinesIgnoresAccelerationAndKeepsDirection() {
        let settings = ScrollAxisSettings(mode: .byLines(3))
        #expect(ScrollTransform.apply(settings, to: Self.notchDown) == ScrollDeltas(lines: -3, fixed: -3, points: -30))
        #expect(ScrollTransform.apply(settings, to: Self.fastSpinUp) == ScrollDeltas(lines: 3, fixed: 3, points: 30),
                "a fast spin scrolls the same distance per notch")
    }

    @Test func byLinesWithReverse() {
        let settings = ScrollAxisSettings(reverse: true, mode: .byLines(3))
        #expect(ScrollTransform.apply(settings, to: Self.notchDown) == ScrollDeltas(lines: 3, fixed: 3, points: 30))
    }

    @Test func fixedModesAbsorbHighResolutionFragments() {
        let fragment = ScrollDeltas(lines: 0, fixed: 0.1, points: 1)
        #expect(ScrollTransform.apply(ScrollAxisSettings(mode: .byLines(3)), to: fragment) == .zero)
        #expect(ScrollTransform.apply(ScrollAxisSettings(mode: .byPixels(40)), to: fragment) == .zero)
    }

    @Test func byPixelsSetsPixelDistance() {
        let result = ScrollTransform.apply(ScrollAxisSettings(mode: .byPixels(40)), to: Self.notchDown)
        #expect(result == ScrollDeltas(lines: -4, fixed: -4, points: -40))
    }

    @Test func acceleratedScalesSystemCurve() {
        let result = ScrollTransform.apply(ScrollAxisSettings(mode: .accelerated(speed: 2)), to: Self.fastSpinUp)
        #expect(result == ScrollDeltas(lines: 9, fixed: 9, points: 90))
        let slow = ScrollTransform.apply(ScrollAxisSettings(mode: .accelerated(speed: 0.1)), to: Self.notchDown)
        #expect(slow.lines == -1, "a whole notch never rounds down to nothing")
    }

    @Test func zeroEventStaysZero() {
        #expect(ScrollTransform.apply(ScrollAxisSettings(reverse: true, mode: .byLines(5)), to: .zero) == .zero)
    }
}
