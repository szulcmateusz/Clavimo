import Testing
@testable import ClavimoCore

/// A guard against accidental linear scans on the event path: the engine
/// runs inside the system event tap, where every microsecond counts.
@Suite("Engine performance")
struct EnginePerformanceTests {
    /// 50 keys, each remapped differently in 20 apps: 1000 rules.
    static func thousandRules() throws -> CompiledRules {
        var definitions: [RuleDefinition] = []
        for key in 0..<50 {
            for app in 0..<20 {
                definitions.append(.remap(from: KeyCode(UInt16(key)), to: .escape,
                                          conditions: RuleConditions(onlyApps: ["com.example.app\(app)"])))
            }
        }
        return try CompiledRules.compile(definitions).get()
    }

    @Test func thousandRulesCompileAndMatchQuickly() throws {
        let clock = ContinuousClock()
        var rules: CompiledRules!
        let compileTime = try clock.measure { rules = try Self.thousandRules() }
        #expect(compileTime < .seconds(1), "compiling 1000 rules took \(compileTime)")

        var engine = InputEngine(rules: rules)
        engine.setFrontmostApp("com.example.app19")
        let key = KeyCode(25)
        let events = 50_000
        var matched = 0
        let elapsed = clock.measure {
            for index in 0..<events {
                let isDown = index % 2 == 0
                let output = engine.handle(InputEvent(kind: .key(key, isDown: isDown, isRepeat: false),
                                                      modifiers: [], time: UInt64(index) * 1_000_000))
                if output.items.first == .key(.escape, isDown: isDown, isRepeat: false, flags: []) { matched += 1 }
            }
        }
        #expect(matched == events)
        let perEvent = elapsed / events
        // Generous for unoptimized builds on shared CI machines; a release
        // build on Apple silicon is far below this.
        #expect(perEvent < .microseconds(50), "average \(perEvent) per event")
    }
}
