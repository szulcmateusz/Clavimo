import Foundation
import Testing
@testable import ClavimoCore

@Suite("Compass geometry")
struct CompassGeometryTests {
    let all = Set(CompassDirection.allCases)

    @Test func movementInsideTheDeadZonePicksNothing() {
        #expect(CompassGeometry.direction(dx: 20, dy: 20, among: all, deadZone: 40) == nil)
        #expect(CompassGeometry.direction(dx: 0, dy: 0, among: all, deadZone: 40) == nil)
    }

    @Test func eachDirectionIsPickedByItsAngle() {
        let cases: [(Double, Double, CompassDirection)] = [
            (0, 100, .up), (70, 70, .upRight), (100, 0, .right), (70, -70, .downRight),
            (0, -100, .down), (-70, -70, .downLeft), (-100, 0, .left), (-70, 70, .upLeft),
        ]
        for (dx, dy, expected) in cases {
            #expect(CompassGeometry.direction(dx: dx, dy: dy, among: all, deadZone: 40) == expected)
        }
    }

    @Test func fewerSlotsCoverWiderAngles() {
        let four: Set<CompassDirection> = [.up, .right, .down, .left]
        // 40 degrees above right is nearer to right than to up.
        #expect(CompassGeometry.direction(dx: 100, dy: 84, among: four, deadZone: 40) == .right)
        #expect(CompassGeometry.direction(dx: 84, dy: 100, among: four, deadZone: 40) == .up)
        #expect(CompassGeometry.direction(dx: -100, dy: -10, among: [.up], deadZone: 40) == .up)
        #expect(CompassGeometry.direction(dx: 100, dy: 0, among: [], deadZone: 40) == nil)
    }

    @Test func tiesGoToTheEarlierDirectionClockwise() {
        // Exactly between up and right.
        #expect(CompassGeometry.direction(dx: 100, dy: 100, among: [.up, .right], deadZone: 40) == .up)
    }

    @Test func numberKeysFollowTheClockwiseOrder() {
        #expect(CompassDirection.up.number == 1)
        #expect(CompassDirection.right.number == 3)
        #expect(CompassDirection.upLeft.number == 8)
        #expect(CompassDirection(number: 5) == .down)
        #expect(CompassDirection(number: 9) == nil)
    }

    @Test func appPagesReplaceAndHideDefaultSlots() {
        let compass = CompassDefinition(
            id: "main", name: "Main",
            slots: [.up: CompassSlot(name: "Mission Control", action: .action(.missionControl)),
                    .left: CompassSlot(name: "Back", action: .action(.shortcut(.leftArrow, .command)))],
            apps: ["com.apple.Safari": [.up: CompassSlot(name: "New tab", action: .action(.menuItem(["File", "New Tab"]))),
                                        .left: CompassSlot(name: "", action: .none)]]
        )
        #expect(compass.slots(forApp: nil).count == 2)
        let safari = compass.slots(forApp: "com.apple.Safari")
        #expect(safari.count == 1)
        #expect(safari[.up]?.action == .action(.menuItem(["File", "New Tab"])))
    }
}

@Suite("Action compass in the engine")
struct CompassEngineTests {
    static let hyperKey = KeyCode(0x6D) // F10
    static let rules: [RuleDefinition] = [
        .keyOutput(id: "k", key: hyperKey, output: .action(.openCompass("main"))),
        .mouseChord(id: "b", leader: .modifiers([]), button: .button4, action: .openCompass("main"), priority: 1),
        .trackpad(id: "t", trigger: .gesture(.tap(fingers: 4)), action: .openCompass("main")),
        .tapHold(id: "caps", key: .capsLock, tap: .key(.escape), hold: .action(.openCompass("main")),
                 settings: TapHoldSettings(holdAfterMilliseconds: 200)),
    ]

    @Test func holdingAKeyOpensAndReleasingItReleases() throws {
        var h = try EngineHarness(Self.rules)
        let down = h.down(Self.hyperKey)
        #expect(down.items.isEmpty)
        #expect(down.compass == [.open(id: "main", held: true)])
        #expect(h.down(Self.hyperKey, repeat: true).items.isEmpty)
        let up = h.up(Self.hyperKey)
        #expect(up.items.isEmpty)
        #expect(up.compass == [.release])
        #expect(h.engine.openCompassID == "main", "it stays open as a panel until the adapter closes it")
        h.engine.closeCompass()
        #expect(!h.engine.hasTransientState)
    }

    @Test func numberKeysPickAndAreSwallowed() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        let three = h.down(KeyCode.digits[2])
        #expect(three.items.isEmpty)
        #expect(three.compass == [.pick(.right)])
        #expect(h.engine.openCompassID == nil)
        #expect(h.up(KeyCode.digits[2]).items.isEmpty)
        #expect(h.up(Self.hyperKey).compass.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func escapeReturnAndSpaceDecide() throws {
        for (key, signal) in [(KeyCode.escape, CompassSignal.cancel), (.returnKey, .confirm), (.space, .confirm)] {
            var h = try EngineHarness(Self.rules)
            h.down(Self.hyperKey)
            h.up(Self.hyperKey)
            let output = h.down(key)
            #expect(output.items.isEmpty)
            #expect(output.compass == [signal])
            #expect(h.up(key).items.isEmpty)
            #expect(!h.engine.hasTransientState)
        }
    }

    @Test func anotherKeyClosesTheCompassAndTypes() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        h.up(Self.hyperKey)
        let a = h.down(.a)
        #expect(a.compass == [.cancel])
        #expect(a.items == [passThrough])
        #expect(h.up(.a).items == [passThrough])
    }

    @Test func modifiersDoNotCloseTheCompass() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        #expect(h.down(.leftShift).compass.isEmpty)
        #expect(h.engine.openCompassID == "main")
    }

    @Test func pressingTheTriggerAgainClosesThePanel() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        h.up(Self.hyperKey)
        let again = h.down(Self.hyperKey)
        #expect(again.compass == [.cancel])
        #expect(again.items.isEmpty)
        #expect(h.up(Self.hyperKey).items.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func aMouseButtonAloneHoldsTheCompass() throws {
        var h = try EngineHarness(Self.rules)
        let down = h.press(.button4)
        #expect(down.items.isEmpty)
        #expect(down.compass == [.open(id: "main", held: true)])
        let up = h.release(.button4)
        #expect(up.items.isEmpty)
        #expect(up.compass == [.release])
        let click = h.press(.primary)
        #expect(click.compass == [.confirm])
        #expect(click.items.isEmpty)
        #expect(h.release(.primary).items.isEmpty, "the click's release is swallowed too")
        #expect(!h.engine.hasTransientState)
    }

    @Test func secondaryClickOrTheSameButtonCancels() throws {
        var h = try EngineHarness(Self.rules)
        h.press(.button4)
        h.release(.button4)
        #expect(h.press(.secondary).compass == [.cancel])
        #expect(h.release(.secondary).items.isEmpty)

        h.press(.button4)
        h.release(.button4)
        let again = h.press(.button4)
        #expect(again.compass == [.cancel])
        #expect(again.items.isEmpty)
        #expect(h.release(.button4).items.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func aGestureOpensAPanelAndClosesIt() throws {
        var h = try EngineHarness(Self.rules)
        #expect(h.engine.handleGesture(.tap(fingers: 4), time: h.now).compass == [.open(id: "main", held: false)])
        #expect(h.engine.handleGesture(.tap(fingers: 4), time: h.now).compass == [.cancel])
        #expect(!h.engine.hasTransientState)
    }

    @Test func tapHoldOpensWhenHeldAndTypesWhenTapped() throws {
        var h = try EngineHarness(Self.rules)
        h.down(.capsLockProxy)
        h.advance(ms: 250)
        #expect(h.fireDeadline().compass == [.open(id: "main", held: true)])
        #expect(h.up(.capsLockProxy).compass == [.release])
        h.engine.closeCompass()

        h.down(.capsLockProxy)
        h.advance(ms: 50)
        #expect(h.up(.capsLockProxy).items == [keyDown(.escape), keyUp(.escape)])
    }

    @Test func aGestureCompassDoesNotTakeTheLastTypedKey() throws {
        var h = try EngineHarness(Self.rules)
        h.down(.a)
        h.up(.a)
        #expect(h.engine.handleGesture(.tap(fingers: 4), time: h.now).compass == [.open(id: "main", held: false)])
        let a = h.down(.a)
        #expect(a.compass == [.cancel], "a letter closes the panel")
        #expect(a.items == [passThrough], "and still types")
    }

    @Test func aTappedCompassClosesWithItsOwnKey() throws {
        let f12 = KeyCode(0x6F)
        var h = try EngineHarness([
            .tapHold(id: "t", key: f12, tap: .action(.openCompass("main")), hold: .modifiers(.hyper),
                     settings: TapHoldSettings(holdAfterMilliseconds: 200)),
        ])
        h.down(f12)
        h.advance(ms: 50)
        #expect(h.up(f12).compass == [.open(id: "main", held: false)], "a tap opens the panel")
        let again = h.down(f12)
        #expect(again.compass == [.cancel], "the same key closes it")
        #expect(again.items.isEmpty)
        #expect(h.up(f12).items.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func theCompassClosesItselfAfterItsTimeout() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        h.up(Self.hyperKey)
        h.advance(ms: UInt64(InputEngine.compassTimeoutMilliseconds) + 1)
        #expect(h.fireDeadline().compass == [.cancel])
        #expect(!h.engine.hasTransientState)
    }

    @Test func resetCancels() throws {
        var h = try EngineHarness(Self.rules)
        h.down(Self.hyperKey)
        #expect(h.engine.reset().compass == [.cancel])
        #expect(h.up(Self.hyperKey).items.isEmpty)
        #expect(!h.engine.hasTransientState)
    }

    @Test func aNestedCompassOpensAsAPanel() throws {
        var h = try EngineHarness(Self.rules)
        let output = h.engine.beginCompass("windows", now: h.now)
        #expect(output.nextDeadline != nil)
        #expect(h.engine.openCompassID == "windows")
        #expect(h.down(KeyCode.digits[0]).compass == [.pick(.up)])
    }

    @Test func rulesReportTheCompassesTheyOpen() throws {
        let rules = try CompiledRules.compile(Self.rules).get()
        #expect(rules.openedCompasses == ["main"])
        #expect(rules.usesCompass)
        #expect(!(try CompiledRules.compile([.remap(from: .a, to: .f)]).get()).usesCompass)
    }

    @Test func protectedButtonsStillNeedAModifier() {
        let result = CompiledRules.compile([
            .mouseChord(id: "x", leader: .modifiers([]), button: .primary, action: .openCompass("main"),
                        priority: 1, allowProtectedButton: true),
        ])
        guard case let .failure(failure) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.errors.contains(.emptyModifierLeader(id: "x")))
    }
}

@Suite("Compasses in the configuration")
struct CompassConfigTests {
    static func document(rules: String = "", compasses: String, extra: String = "") -> String {
        """
        {
          "schemaVersion": 1,
          "configId": "00000000-0000-4000-8000-000000000001",
          "engine": {"enabledOnLaunch": true, "failOpen": true},
          "activeProfileId": "default",
          "profiles": [{"id": "default", "name": "Default", "inherits": null}],
          "rules": [\(rules)],
          "macros": [],
          "compasses": \(compasses)\(extra)
        }
        """
    }

    static let main = """
    [{"id": "main", "name": "Main", "hintDelayMs": 300, "slots": [
      {"direction": "up", "name": "Mission Control", "action": {"kind": "missionControl"}},
      {"direction": "left", "action": {"kind": "sendShortcut", "key": {"codeNamespace": "macVirtualKeyCode", "code": 123}, "modifiers": ["command"]}},
      {"direction": "down", "action": {"kind": "openCompass", "compassId": "windows"}}
     ],
     "apps": [{"bundleId": "com.apple.Safari", "slots": [
      {"direction": "right", "name": "New tab", "action": {"kind": "menuItem", "path": ["File", "New Tab"]}},
      {"direction": "left", "action": {"kind": "none"}}
     ]}]},
     {"id": "windows", "name": "Windows", "slots": [{"direction": "up", "action": {"kind": "applicationWindows"}}]}]
    """

    @Test func compassesAreRead() throws {
        let config = try ConfigDocument.decode(Data(Self.document(compasses: Self.main).utf8)).interpret()
        #expect(config.unsupported.isEmpty)
        let main = try #require(config.compasses["main"])
        #expect(main.hintDelayMilliseconds == 300)
        #expect(main.deadZone == CompassDefinition.defaultDeadZone)
        #expect(main.slots[.up] == CompassSlot(name: "Mission Control", action: .action(.missionControl)))
        #expect(main.slots[.down]?.action == .action(.openCompass("windows")))
        let safari = main.slots(forApp: "com.apple.Safari")
        #expect(safari[.right]?.action == .action(.menuItem(["File", "New Tab"])))
        #expect(safari[.left] == nil)
        #expect(config.compasses["windows"] != nil)
    }

    @Test func badSlotsAreReportedAndLeftOut() throws {
        let compasses = """
        [{"id": "main", "name": "Main", "slots": [
          {"direction": "north", "action": {"kind": "missionControl"}},
          {"direction": "up", "action": {"kind": "missionControl"}},
          {"direction": "up", "action": {"kind": "applicationWindows"}},
          {"direction": "left", "action": {"kind": "openCompass", "compassId": "nope"}},
          {"direction": "right", "action": {"kind": "teleport"}}
        ]}]
        """
        let config = try ConfigDocument.decode(Data(Self.document(compasses: compasses).utf8)).interpret()
        #expect(config.unsupported.map(\.reason) == [
            .invalidCompassDirection("north"), .duplicateCompassDirection("up"),
            .unknownCompass("nope"), .unsupportedAction("teleport"),
        ])
        #expect(config.compasses["main"]?.slots.keys.sorted { $0.number < $1.number } == [.up])
    }

    @Test func aRuleOpeningAMissingCompassIsReported() throws {
        let rule = ConfigTests.rule(trigger: #"{"kind": "mouseButton", "mouseButton": 4}"#,
                                    action: #"{"kind": "openCompass", "compassId": "nope"}"#)
        let config = try ConfigDocument.decode(Data(Self.document(rules: rule, compasses: Self.main).utf8)).interpret()
        #expect(config.definitions.isEmpty)
        #expect(config.unsupported.map(\.reason) == [.unknownCompass("nope")])
    }

    @Test func mouseButtonTriggersAreRead() throws {
        let rule = ConfigTests.rule(trigger: #"{"kind": "mouseButton", "mouseButton": 4, "requiredModifiers": ["option"]}"#,
                                    action: #"{"kind": "openCompass", "compassId": "main"}"#)
        let config = try ConfigDocument.decode(Data(Self.document(rules: rule, compasses: Self.main).utf8)).interpret()
        #expect(config.definitions == [
            .mouseChord(id: "r1", leader: .modifiers(.option), button: .button4, action: .openCompass("main"), priority: 50),
        ])
        let alone = ConfigTests.rule(trigger: #"{"kind": "mouseButton", "mouseButton": 5, "phase": "down"}"#,
                                     action: #"{"kind": "missionControl"}"#)
        let second = try ConfigDocument.decode(Data(Self.document(rules: alone, compasses: "[]").utf8)).interpret()
        #expect(second.definitions == [
            .mouseChord(id: "r1", leader: .modifiers([]), button: .button5, action: .missionControl, priority: 50),
        ])
        #expect((try CompiledRules.compile(second.definitions).get()).chordsByButton[.button5]?.count == 1)
    }

    @Test func unknownTopLevelFieldsSurviveASave() throws {
        let json = Self.document(compasses: "[]", extra: #", "futureThing": {"a": [1, 2]}"#)
        let document = try ConfigDocument.decode(Data(json.utf8))
        #expect(document.otherFields["futureThing"] == .object(["a": .array([.number(1), .number(2)])]))
        let again = try ConfigDocument.decode(try document.encoded())
        #expect(again == document)
        #expect(String(decoding: try document.encoded(), as: UTF8.self).contains("futureThing"))
    }

    @Test func documentsWithoutCompassesStayWithout() throws {
        let document = try ConfigDocument.decode(Data(ConfigTests.document(rules: "").utf8))
        #expect(document.compasses == nil)
        #expect(!String(decoding: try document.encoded(), as: UTF8.self).contains("compasses"))
    }
}
