import Testing
@testable import ClavimoCore

@Suite("Command and Option swap")
struct ModifierSwapTests {
    func leftSwap() throws -> EngineHarness {
        try EngineHarness([.swap(.leftCommand, .leftOption)])
    }

    @Test func commandBecomesOption() throws {
        var h = try leftSwap()
        #expect(h.down(.leftCommand).items == [keyDown(.leftOption, [.leftOption])])
        #expect(h.up(.leftCommand).items == [keyUp(.leftOption, [])])
    }

    @Test func optionBecomesCommand() throws {
        var h = try leftSwap()
        #expect(h.down(.leftOption).items == [keyDown(.leftCommand, [.leftCommand])])
        #expect(h.up(.leftOption).items == [keyUp(.leftCommand, [])])
    }

    @Test func commandCProducesOptionCWithoutCommand() throws {
        var h = try leftSwap()
        h.down(.leftCommand)
        // The physical event reports Command; the adapter must rewrite it.
        #expect(h.down(.c).items == [.original(flags: [.leftOption])])
        #expect(h.up(.c).items == [.original(flags: [.leftOption])])
        h.up(.leftCommand)
        #expect(h.down(.c).items == [passThrough])
    }

    @Test func bothHeldAndReleasedInReverseOrderEndsWithNothingHeld() throws {
        var h = try leftSwap()
        #expect(h.down(.leftCommand).items == [keyDown(.leftOption, [.leftOption])])
        #expect(h.down(.leftOption).items == [keyDown(.leftCommand, [.leftOption, .leftCommand])])
        #expect(h.down(.c).items == [.original(flags: nil)], "both held: logical equals physical")
        h.up(.c)
        #expect(h.up(.leftCommand).items == [keyUp(.leftOption, [.leftCommand])])
        #expect(h.up(.leftOption).items == [keyUp(.leftCommand, [])])
        #expect(!h.engine.hasTransientState)
    }

    @Test func rightSideIsUnaffectedByLeftSwap() throws {
        var h = try leftSwap()
        #expect(h.down(.rightCommand).items == [passThrough])
        #expect(h.up(.rightCommand).items == [passThrough])
    }

    @Test func rightSideSwapWorksIndependently() throws {
        var h = try EngineHarness([.swap(.leftCommand, .leftOption), .swap(.rightCommand, .rightOption)])
        #expect(h.down(.rightCommand).items == [keyDown(.rightOption, [.rightOption])])
        #expect(h.down(.leftOption).items == [keyDown(.leftCommand, [.rightOption, .leftCommand])])
        h.up(.leftOption)
        #expect(h.up(.rightCommand).items == [keyUp(.rightOption, [])])
    }

    @Test func unmappedModifierPassesWhileNoRemapIsActive() throws {
        var h = try leftSwap()
        #expect(h.down(.leftShift).items == [passThrough])
        #expect(h.up(.leftShift).items == [passThrough])
    }

    @Test func unmappedModifierCarriesSwappedFlagsWhileSwapIsHeld() throws {
        var h = try leftSwap()
        h.down(.leftCommand)
        #expect(h.down(.leftShift).items == [keyDown(.leftShift, [.leftOption, .leftShift])])
        #expect(h.up(.leftShift).items == [keyUp(.leftShift, [.leftOption])])
    }

    @Test func profileSwitchMidHoldReleasesOriginalMappingOnce() throws {
        var h = try leftSwap()
        h.down(.leftCommand)
        h.engine.install(.empty)
        #expect(h.up(.leftCommand).items == [keyUp(.leftOption, [])])
        #expect(h.down(.leftCommand).items == [passThrough])
    }

    @Test func toggling100TimesLeavesNoStaleState() throws {
        let rules = try CompiledRules.compile([.swap(.leftCommand, .leftOption)]).get()
        var h = try leftSwap()
        var keyboard = LogicalKeyboard()
        for index in 0..<100 {
            keyboard.apply(h.down(.leftCommand), original: .leftCommand, originalIsDown: true)
            if index.isMultiple(of: 2) {
                keyboard.apply(h.engine.reset())
                h.engine.install(.empty)
            }
            keyboard.apply(h.up(.leftCommand), original: .leftCommand, originalIsDown: false)
            h.engine.install(rules)
        }
        #expect(keyboard.violations.isEmpty)
        #expect(keyboard.down.isEmpty)
    }
}
