import CoreGraphics
import ModweaveCore
import Testing
@testable import ModweaveQuartz

@Suite("Quartz flag conversion")
struct QuartzFlagsTests {
    @Test func readsSideSpecificBits() {
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | QuartzFlags.deviceRightCommand
            | CGEventFlags.maskShift.rawValue | QuartzFlags.deviceLeftShift)
        #expect(QuartzFlags.modifiers(from: flags) == [.rightCommand, .leftShift])
    }

    @Test func genericBitWithoutSideFallsBackToLeft() {
        #expect(QuartzFlags.modifiers(from: .maskAlternate) == [.leftOption])
    }

    @Test func applyingReplacesOnlyModifierBits() {
        let original = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | QuartzFlags.deviceLeftCommand
            | CGEventFlags.maskAlphaShift.rawValue | CGEventFlags.maskSecondaryFn.rawValue)
        let result = QuartzFlags.applying([.leftOption], to: original)
        #expect(result.contains(.maskAlternate))
        #expect(!result.contains(.maskCommand))
        #expect(result.rawValue & QuartzFlags.deviceLeftCommand == 0)
        #expect(result.rawValue & QuartzFlags.deviceLeftOption != 0)
        #expect(result.contains(.maskAlphaShift), "Caps Lock state must survive")
        #expect(result.contains(.maskSecondaryFn), "Fn state must survive")
    }

    @Test func roundTripsEverySide() {
        for key in ModifierKey.allCases {
            #expect(QuartzFlags.modifiers(from: QuartzFlags.applying(key.set, to: [])) == key.set)
        }
    }

    @Test func eventMaskExcludesPointerAndPrimaryButtons() {
        let mask = EventTapController.eventMask
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                  .scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp] {
            #expect(mask & (CGEventMask(1) << CGEventMask(type.rawValue)) == 0, "\(type.rawValue) must not be observed")
        }
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged, .otherMouseDown, .otherMouseUp] {
            #expect(mask & (CGEventMask(1) << CGEventMask(type.rawValue)) != 0)
        }
    }
}

@Suite("Latency recorder")
struct LatencyRecorderTests {
    @Test func nearestRankPercentiles() throws {
        var recorder = LatencyRecorder(capacity: 100)
        for value in 1...100 { recorder.record(UInt64(value)) }
        let summary = try #require(recorder.summary())
        #expect(summary.p50 == 50)
        #expect(summary.p95 == 95)
        #expect(summary.p99 == 99)
        #expect(summary.max == 100)
    }

    @Test func keepsOnlyMostRecentWindow() throws {
        var recorder = LatencyRecorder(capacity: 4)
        for value in [1000, 1000, 1, 2, 3, 4] { recorder.record(UInt64(value)) }
        let summary = try #require(recorder.summary())
        #expect(summary.max == 4)
        #expect(recorder.totalCount == 6)
    }

    @Test func emptyRecorderHasNoSummary() {
        #expect(LatencyRecorder(capacity: 8).summary() == nil)
    }
}
