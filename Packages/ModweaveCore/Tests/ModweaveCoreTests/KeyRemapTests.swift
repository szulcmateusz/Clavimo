import Testing
@testable import ModweaveCore

@Suite("Simple key remapping")
struct KeyRemapTests {
    @Test func unmappedKeysPassThroughUntouched() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g)])
        #expect(h.down(.c).items == [passThrough])
        #expect(h.up(.c).items == [passThrough])
    }

    @Test func remapsDownRepeatAndUp() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g)])
        #expect(h.down(.a).items == [keyDown(.g)])
        #expect(h.down(.a, repeat: true).items == [keyRepeat(.g)])
        #expect(h.up(.a).items == [keyUp(.g)])
        #expect(!h.engine.hasTransientState)
    }

    @Test func keyUpUsesMappingFromKeyDownAfterRuleSwap() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g)])
        h.down(.a)
        h.engine.install(try CompiledRules.compile([.remap(from: .a, to: .v)]).get())
        #expect(h.up(.a).items == [keyUp(.g)])
        #expect(h.down(.a).items == [keyDown(.v)])
    }

    @Test func keyHeldBeforeRuleInstallStaysUnmappedUntilReleased() throws {
        var h = try EngineHarness([])
        #expect(h.down(.a).items == [passThrough])
        h.engine.install(try CompiledRules.compile([.remap(from: .a, to: .g)]).get())
        // Autorepeat of a key whose down was passed through stays passthrough.
        #expect(h.down(.a, repeat: true).items == [passThrough])
        #expect(h.up(.a).items == [passThrough])
    }

    @Test func twoPhysicalKeysSharingAnOutputAreReferenceCounted() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g), .remap(from: .c, to: .g)])
        #expect(h.down(.a).items == [keyDown(.g)])
        #expect(h.down(.c).items == [])
        #expect(h.up(.a).items == [], "G must stay down while C still holds it")
        #expect(h.up(.c).items == [keyUp(.g)])
    }

    @Test func remappedRegularKeyCarriesLogicalModifierFlags() throws {
        var h = try EngineHarness([.remap(from: .a, to: .g)])
        h.down(.leftShift)
        #expect(h.down(.a).items == [keyDown(.g, [.leftShift])])
    }

    @Test func regularKeyCanProduceModifier() throws {
        var h = try EngineHarness([.remap(from: .a, to: .leftControl)])
        #expect(h.down(.a).items == [keyDown(.leftControl, [.leftControl])])
        #expect(h.down(.a, repeat: true).items == [], "modifiers do not autorepeat")
        #expect(h.down(.c).items == [.original(flags: [.leftControl])])
        h.up(.c)
        #expect(h.up(.a).items == [keyUp(.leftControl, [])])
    }

    @Test func modifierCanProduceRegularKey() throws {
        var h = try EngineHarness([.remap(from: .rightCommand, to: .escape)])
        #expect(h.down(.rightCommand).items == [keyDown(.escape)])
        #expect(h.up(.rightCommand).items == [keyUp(.escape)])
    }
}
