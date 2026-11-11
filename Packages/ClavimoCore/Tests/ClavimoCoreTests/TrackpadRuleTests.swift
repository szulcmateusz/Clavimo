import Testing
@testable import ClavimoCore

@Suite("Trackpad rules")
struct TrackpadRuleTests {
    func engine(_ definitions: [RuleDefinition]) throws -> EngineHarness {
        try EngineHarness(definitions)
    }

    @Test func gestureRunsItsAction() throws {
        var h = try engine([.trackpad(id: "t", trigger: .gesture(.tap(fingers: 3)), action: .click(.middle))])
        #expect(h.engine.handleGesture(.tap(fingers: 3)).actions == [.click(.middle)])
        #expect(h.engine.handleGesture(.tap(fingers: 4)).actions.isEmpty)
    }

    @Test func modifiersMustMatchExactly() throws {
        var h = try engine([
            .trackpad(id: "plain", trigger: .gesture(.swipe(fingers: 3, .left)), action: .previousWorkspace),
            .trackpad(id: "fn", trigger: .gesture(.swipe(fingers: 3, .left)), modifiers: .function, action: .shortcut(.leftArrow, .command)),
        ])
        #expect(h.engine.handleGesture(.swipe(fingers: 3, .left)).actions == [.previousWorkspace])
        h.engine = InputEngine(rules: h.engine.rules)
        _ = h.engine.handle(InputEvent(kind: .key(.a, isDown: true, isRepeat: false), modifiers: .function, time: 1))
        #expect(h.engine.handleGesture(.swipe(fingers: 3, .left)).actions == [.shortcut(.leftArrow, .command)])
        h.down(.leftShift)
        #expect(h.engine.handleGesture(.swipe(fingers: 3, .left)).actions.isEmpty, "Shift is not part of either rule")
    }

    @Test func appConditionsApply() throws {
        var h = try engine([
            .trackpad(id: "safari", trigger: .gesture(.tipTap(.right)), action: .shortcut(KeyCode(0x11), .command),
                      conditions: RuleConditions(onlyApps: ["com.apple.Safari"])),
        ])
        #expect(h.engine.handleGesture(.tipTap(.right)).actions.isEmpty)
        h.engine.setFrontmostApp("com.apple.Safari")
        #expect(h.engine.handleGesture(.tipTap(.right)).actions == [.shortcut(KeyCode(0x11), .command)])
    }

    @Test func higherPriorityWins() throws {
        var h = try engine([
            .trackpad(id: "low", trigger: .gesture(.tap(fingers: 4)), action: .missionControl, priority: 10),
            .trackpad(id: "high", trigger: .gesture(.tap(fingers: 4)), action: .applicationWindows, priority: 50,
                      conditions: RuleConditions(exceptApps: ["x"])),
        ])
        #expect(h.engine.handleGesture(.tap(fingers: 4)).actions == [.applicationWindows])
    }

    @Test func threeFingerClickReplacesTheClickAndItsRelease() throws {
        var h = try engine([.trackpad(id: "c", trigger: .click(fingers: 3), action: .click(.middle))])
        let down = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: true), modifiers: [], time: 1,
                                              touch: TouchSnapshot(fingers: 3)))
        #expect(down.items.isEmpty && down.actions == [.click(.middle)])
        let up = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: false), modifiers: [], time: 2,
                                            touch: TouchSnapshot(fingers: 3)))
        #expect(up.items.isEmpty && up.actions.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func ordinaryClicksPassThrough() throws {
        var h = try engine([.trackpad(id: "c", trigger: .click(fingers: 3), action: .click(.middle))])
        for touch in [TouchSnapshot(fingers: 1), TouchSnapshot(fingers: 2), nil] {
            let down = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: true), modifiers: [], time: 1, touch: touch))
            let up = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: false), modifiers: [], time: 2, touch: touch))
            #expect(down.items == [passThrough] && up.items == [passThrough])
        }
    }

    @Test func cornerClickAndCornerTap() throws {
        var h = try engine([.trackpad(id: "corner", trigger: .cornerClick(.topRight), action: .shortcut(KeyCode(0x0D), .command))])
        let press = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: true), modifiers: [], time: 1,
                                               touch: TouchSnapshot(fingers: 1, corner: .topRight)))
        #expect(press.actions == [.shortcut(KeyCode(0x0D), .command)])
        _ = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: false), modifiers: [], time: 2))
        let tap = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: true), modifiers: [], time: 3,
                                             touch: TouchSnapshot(fingers: 0, tappedCorner: .topRight)))
        #expect(tap.actions == [.shortcut(KeyCode(0x0D), .command)])
        _ = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: false), modifiers: [], time: 4))
        let other = h.engine.handle(InputEvent(kind: .mouseButton(.primary, isDown: true), modifiers: [], time: 5,
                                               touch: TouchSnapshot(fingers: 1, corner: .bottomLeft)))
        #expect(other.items == [passThrough])
    }

    @Test func mouseButtonsAreNeverTrackpadClicks() throws {
        var h = try engine([.trackpad(id: "c", trigger: .click(fingers: 3), action: .missionControl)])
        let side = h.engine.handle(InputEvent(kind: .mouseButton(.button4, isDown: true), modifiers: [], time: 1,
                                              touch: TouchSnapshot(fingers: 3)))
        #expect(side.items == [passThrough])
    }

    @Test func compilerRejectsImpossibleGestures() {
        func errors(_ definition: RuleDefinition) -> [RuleValidationError] {
            if case let .failure(failure) = CompiledRules.compile([definition]) { failure.errors } else { [] }
        }
        #expect(errors(.trackpad(id: "a", trigger: .gesture(.tap(fingers: 1)), action: .missionControl)) == [.trackpadFingersOutOfRange(id: "a")])
        #expect(errors(.trackpad(id: "b", trigger: .gesture(.swipe(fingers: 2, .up)), action: .missionControl)) == [.trackpadFingersOutOfRange(id: "b")])
        #expect(errors(.trackpad(id: "c", trigger: .click(fingers: 2), action: .missionControl)) == [.trackpadFingersOutOfRange(id: "c")])
        #expect(errors(.trackpad(id: "d", trigger: .gesture(.tap(fingers: 2)), action: .missionControl)) == [.twoFingerTapNeedsModifiers(id: "d")])
        #expect(errors(.trackpad(id: "e", trigger: .gesture(.tap(fingers: 2)), modifiers: .command, action: .missionControl)).isEmpty)
        let duplicate = CompiledRules.compile([
            .trackpad(id: "x", trigger: .gesture(.tap(fingers: 3)), action: .missionControl),
            .trackpad(id: "y", trigger: .gesture(.tap(fingers: 3)), action: .applicationWindows),
        ])
        if case let .failure(failure) = duplicate {
            #expect(failure.errors == [.duplicateTrackpadRule(ids: ["x", "y"])])
        } else {
            Issue.record("duplicate trackpad rules compiled")
        }
    }

    @Test func flagsDescribeWhatTheAdapterMustObserve() throws {
        let gestures = try CompiledRules.compile([.trackpad(id: "g", trigger: .gesture(.tap(fingers: 3)), action: .missionControl)]).get()
        #expect(gestures.observesTrackpad && !gestures.observesTrackpadClicks)
        let clicks = try CompiledRules.compile([.trackpad(id: "c", trigger: .cornerClick(.bottomLeft), action: .missionControl)]).get()
        #expect(clicks.observesTrackpad && clicks.observesTrackpadClicks)
        #expect(!CompiledRules.empty.observesTrackpad)
    }
}
