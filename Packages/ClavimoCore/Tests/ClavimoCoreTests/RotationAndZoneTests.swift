import Foundation
import Testing
@testable import ClavimoCore

extension TouchScript {
    /// Turns two fingers around their midpoint by `degrees` (positive is
    /// counterclockwise, y grows upwards), on a 1.6 wide surface.
    mutating func turn(_ a: Int32, _ b: Int32, degrees: Float, over seconds: Double) {
        let steps = max(1, Int((seconds / 0.01).rounded()))
        guard let first = fingers[a], let second = fingers[b] else { return }
        let aspect: Float = 1.6
        let center = ((first.x + second.x) / 2, (first.y + second.y) / 2)
        let radius = (((second.x - first.x) * aspect) * ((second.x - first.x) * aspect) + (second.y - first.y) * (second.y - first.y)).squareRoot() / 2
        let startAngle = atan2(second.y - first.y, (second.x - first.x) * aspect)
        for step in 1...steps {
            let angle = startAngle + degrees * .pi / 180 * Float(step) / Float(steps)
            let dx = cos(angle) * radius / aspect
            let dy = sin(angle) * radius
            fingers[b] = (center.0 + dx, center.1 + dy)
            fingers[a] = (center.0 - dx, center.1 - dy)
            frame()
        }
    }
}

@Suite("Rotation and trackpad zones")
struct RotationAndZoneTests {
    @Test func turningTwoFingersRepeatsLikeAKnob() {
        var script = TouchScript()
        script.down(1, 0.4, 0.5)
        script.down(2, 0.6, 0.5)
        script.turn(1, 2, degrees: -90, over: 0.6)
        // About 34 degrees to start, then one step every 15 degrees: 1 + 3.
        #expect(script.events == Array(repeating: .rotate(.clockwise), count: 4))
        #expect(script.recognizer.isRotating)
        script.events = []
        // 11 degrees were left over clockwise, so 45 back gives two steps.
        script.turn(1, 2, degrees: 45, over: 0.3)
        #expect(script.events == Array(repeating: .rotate(.counterclockwise), count: 2))
        script.up(1)
        script.up(2)
        #expect(!script.recognizer.isRotating)
        #expect(script.recognizer.isIdle)
    }

    @Test func restingThumbWithAMovingFingerIsNotRotation() {
        var script = TouchScript()
        script.down(1, 0.3, 0.2)
        script.down(2, 0.5, 0.25)
        // The finger sweeps an arc around the resting thumb.
        script.move([2], dx: -0.05, dy: 0.25, over: 0.4)
        script.move([2], dx: -0.15, dy: 0.1, over: 0.3)
        script.up(1)
        script.up(2)
        #expect(script.events.isEmpty)
    }

    @Test func curvedTwoFingerScrollIsNotRotation() {
        var script = TouchScript()
        script.down(1, 0.4, 0.3)
        script.down(2, 0.55, 0.3)
        // Both fingers scroll up while drifting apart at an angle.
        script.move([1], dx: 0.0, dy: 0.35, over: 0.35)
        script.move([2], dx: -0.06, dy: 0.42, over: 0.35)
        script.up(1)
        script.up(2)
        #expect(script.events.isEmpty)
    }

    @Test func cornersAreQuarters() {
        #expect(TrackpadZone.topRight.contains(x: 0.8, y: 0.9))
        #expect(!TrackpadZone.topRight.contains(x: 0.2, y: 0.9))
        #expect(!TrackpadZone.topRight.contains(x: 0.8, y: 0.1))
        #expect(TrackpadZone.bottomLeft.contains(x: 0.1, y: 0.1))
    }

    @Test func scrollingAndPinchingAreNotRotation() {
        var script = TouchScript()
        script.down(1, 0.4, 0.3)
        script.down(2, 0.5, 0.3)
        script.move([1, 2], dx: 0, dy: 0.4, over: 0.4)
        script.move([1, 2], dx: 0.2, dy: -0.2, over: 0.3)
        script.move([2], dx: 0.2, dy: 0, over: 0.3)
        script.up(1)
        script.up(2)
        #expect(script.events.isEmpty)
    }

    @Test func gesturesRememberWhereTheyStarted() {
        var script = TouchScript()
        script.tap(3, at: 0.1, y: 0.8)
        #expect(script.events == [.tap(fingers: 3)])
        let point = script.recognizer.lastGesturePoint
        #expect(point.map { TrackpadZone.left.contains(x: $0.x, y: $0.y) } == true)
        #expect(point.map { TrackpadZone.top.contains(x: $0.x, y: $0.y) } == true)
    }

    @Test func zoneRulesWinWhereTheyApply() throws {
        var harness = try EngineHarness([
            .trackpad(id: "any", trigger: .gesture(.rotate(.clockwise)), action: .media(.brightnessUp)),
            .trackpad(id: "left", trigger: .gesture(.rotate(.clockwise)), action: .media(.volumeUp), zone: .left),
        ])
        let left = TrackpadPoint(x: 0.2, y: 0.5)
        let right = TrackpadPoint(x: 0.8, y: 0.5)
        #expect(harness.engine.handleGesture(.rotate(.clockwise), at: left).actions == [.media(.volumeUp)])
        #expect(harness.engine.handleGesture(.rotate(.clockwise), at: right).actions == [.media(.brightnessUp)])
        #expect(harness.engine.handleGesture(.rotate(.clockwise)).actions == [.media(.brightnessUp)])
    }

    @Test func zonesAreForGesturesOnly() {
        let result = CompiledRules.compile([
            .trackpad(id: "click", trigger: .click(fingers: 3), action: .missionControl, zone: .left),
        ])
        if case let .failure(failure) = result {
            #expect(failure.errors == [.trackpadZoneOnClick(id: "click")])
        } else {
            Issue.record("a zone on a click must be rejected")
        }
        let rules = try? CompiledRules.compile([.trackpad(id: "r", trigger: .gesture(.rotate(.clockwise)), action: .missionControl)]).get()
        #expect(rules?.observesRotation == true)
    }

    @Test func rotationAndZonesAreReadFromTheConfiguration() throws {
        let json = ConfigTests.document(rules: ConfigTests.rule(
            trigger: #"{"kind": "trackpadGesture", "gesture": "rotate", "direction": "counterclockwise", "zone": "right"}"#,
            action: #"{"kind": "mediaKey", "key": "volumeDown"}"#
        ))
        let result = try ConfigDocument.decode(Data(json.utf8)).interpret()
        #expect(result.unsupported.isEmpty)
        #expect(result.definitions == [.trackpad(id: "r1", trigger: .gesture(.rotate(.counterclockwise)), action: .media(.volumeDown),
                                                 priority: 50, zone: .right)])
    }
}
