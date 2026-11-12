import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Ready-made setups")
struct PresetTests {
    static let empty = ConfigDocument(configId: "c", engine: .init(enabledOnLaunch: true), activeProfileId: "default",
                                      profiles: [.init(id: "default", name: "Default")])

    static let builtIn = Hardware.Device(id: DeviceID(vendorID: 1452, productID: 832), name: "Apple Internal Keyboard / Trackpad",
                                         transport: "FIFO", isKeyboard: true, isPointer: true)
    static let receiver = Hardware.Device(id: DeviceID(vendorID: 1133, productID: 50475), name: "USB Receiver", transport: "USB",
                                          isKeyboard: true, isPointer: true)
    static let everything = Hardware(devices: [builtIn, receiver])

    static var example: ConfigDocument {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../examples/example-config.json").standardized
        return try! ConfigDocument.decode(Data(contentsOf: url))
    }

    func check(_ document: ConfigDocument) throws {
        let interpreted = try document.interpret()
        #expect(interpreted.unsupported.isEmpty, "\(interpreted.unsupported)")
        if case let .failure(failure) = CompiledRules.compile(interpreted.definitions) {
            Issue.record("\(failure.errors)")
        }
    }

    @Test func hardwareIsRecognized() {
        let laptop = Hardware(devices: [Self.builtIn])
        #expect(laptop.hasTrackpad && !laptop.hasMouse)
        let desk = Self.everything
        #expect(desk.hasTrackpad && desk.hasMouse && desk.hasLogitech)
        let magic = Hardware(devices: [Hardware.Device(id: DeviceID(vendorID: 1452, productID: 613), name: "Magic Trackpad",
                                                       transport: "Bluetooth", isKeyboard: false, isPointer: true)])
        #expect(magic.hasTrackpad && !magic.hasMouse)
        #expect(Hardware(devices: [], otherApps: ["Logi Options+"]).usesLogiOptions)
    }

    @Test func recommendationsFollowTheHardware() {
        #expect(Presets.ordered(for: Hardware(devices: [Self.builtIn])).first?.id == "trackpad")
        let mouseOnly = Hardware(devices: [Self.receiver])
        #expect(Presets.ordered(for: mouseOnly).first?.id == "mouse")
    }

    @Test(arguments: ["trackpad", "mouse"])
    func everyItemWorksOnAnEmptyAndAFullConfiguration(preset id: String) throws {
        let preset = try #require(Presets.all.first { $0.id == id })
        for base in [Self.empty, Self.example] {
            let outcome = PresetEngine.apply(preset, items: Set(preset.items.map(\.id)), to: base, hardware: Self.everything)
            try check(outcome.document)
            #expect(Set(outcome.applied).union(outcome.skipped.map(\.item)) == Set(preset.items.map(\.id)))
            if base == Self.empty {
                #expect(outcome.skipped.isEmpty, "\(outcome.skipped)")
            }
        }
    }

    @Test func allPresetsTogether() throws {
        var document = Self.empty
        for preset in Presets.all {
            document = PresetEngine.apply(preset, items: Set(preset.items.map(\.id)), to: document, hardware: Self.everything).document
        }
        try check(document)
        #expect(document.deviceSettings?.count == 1)
    }

    @Test func gesturesMacOSUsesAreLeftOut() {
        var hardware = Self.everything
        hardware.systemGestures = [.lookUp]
        let outcome = PresetEngine.apply(Presets.trackpad, items: ["middle", "play"], to: Self.empty, hardware: hardware)
        #expect(outcome.skipped.map(\.item) == ["middle"], "Look Up takes the three-finger tap")
        #expect(outcome.applied == ["play"])
    }

    @Test func fourFingerVolumeNeedsFreeSwipes() {
        let swipe = Presets.trackpad.items.first { $0.id == "swipeVolume" }!
        #expect(swipe.unavailable(Self.everything, Self.empty) == nil)
        var busy = Self.everything
        busy.systemGestures = [.fourFingerVertical]
        #expect(swipe.unavailable(busy, Self.empty) != nil, "macOS opens Mission Control with four fingers")
    }

    @Test func applyingTwiceAddsNothing() {
        let preset = Presets.trackpad
        let first = PresetEngine.apply(preset, items: ["middle", "swipeVolume"], to: Self.empty, hardware: Self.everything)
        #expect(PresetEngine.appliedItems(preset, in: first.document) == ["middle", "swipeVolume"])
        let second = PresetEngine.apply(preset, items: ["middle", "swipeVolume"], to: first.document, hardware: Self.everything)
        #expect(second.applied.isEmpty)
        #expect(second.document == first.document)
    }

    @Test func removingRestoresTheConfiguration() {
        for preset in Presets.all {
            let outcome = PresetEngine.apply(preset, items: Set(preset.items.map(\.id)), to: Self.example, hardware: Self.everything)
            #expect(PresetEngine.remove(preset, from: outcome.document) == Self.example, "\(preset.id)")
        }
    }

    @Test func clashesAreSkippedWithAReason() {
        // A rule on ⌥ + button 4 already there.
        var document = Self.empty
        var side = RuleDraft()
        side.kind = .modifierClick
        side.modifiers = [.option]
        side.button = 4
        side.action = .missionControl
        document.rules.append(side.makeRule(id: "mine", order: 1))

        let mouse = PresetEngine.apply(Presets.mouse, items: ["spaces", "compass"], to: document, hardware: Self.everything)
        #expect(mouse.skipped.map(\.item) == ["spaces"])
        #expect(mouse.applied == ["compass"])
        #expect(mouse.document.rules.contains { $0.id == "mine" }, "the user's own rule stays")
    }

    @Test func theCompassItemOpensTheCompassYouHave() {
        var document = Self.empty
        document.compasses = [ConfigDocument.Compass(id: "main", name: "Main", slots: [])]
        var trigger = RuleDraft()
        trigger.kind = .modifierClick
        trigger.modifiers = [.command]
        trigger.button = 5
        trigger.action = .openCompass
        trigger.compassID = "main"
        document.rules.append(trigger.makeRule(id: "t", order: 0))
        let outcome = PresetEngine.apply(Presets.trackpad, items: ["compass"], to: document, hardware: Self.everything)
        #expect(outcome.applied == ["compass"])
        #expect(outcome.document.compasses?.map(\.id) == ["main"], "no second compass")
        let tap = outcome.document.rules.last
        #expect(tap?.trigger["kind"]?.string == "modifierTap")
        #expect(tap?.action["compassId"]?.string == "main")
        // Switching the setup off removes the tap and keeps your compass.
        #expect(PresetEngine.remove(Presets.trackpad, from: outcome.document) == document)
    }

    @Test func aTriggerYouAlreadyUseIsLeftOut() {
        var document = Self.empty
        var mine = RuleDraft()
        mine.kind = .modifierClick
        mine.modifiers = [.command]
        mine.button = 4
        mine.action = .missionControl
        document.rules.append(mine.makeRule(id: "mine", order: 0))
        let outcome = PresetEngine.apply(Presets.mouse, items: ["compass"], to: document, hardware: Self.everything)
        #expect(outcome.skipped.map(\.item) == ["compass"])
        #expect(outcome.document == document)
    }

    @Test func rulesGoToTheActiveProfile() throws {
        var document = Self.empty
        document.profiles.append(.init(id: "work", name: "Work", inherits: "default"))
        document.activeProfileId = "work"
        let outcome = PresetEngine.apply(Presets.trackpad, items: ["middle"], to: document, hardware: Self.everything)
        #expect(outcome.document.rules.allSatisfy { $0.profileId == "work" })
    }

    @Test func aShadowedRuleCountsAsAClash() {
        // A Default rule for a three-finger tap; the active profile inherits it.
        var document = Self.empty
        document.profiles.append(.init(id: "work", name: "Work", inherits: "default"))
        var tap = RuleTemplates.gesture(.gesture(.tap(fingers: 3)), .missionControl)
        tap.profileID = "default"
        document.rules.append(tap.makeRule(id: "mine", order: 0))
        document.activeProfileId = "work"
        let outcome = PresetEngine.apply(Presets.trackpad, items: ["middle"], to: document, hardware: Self.everything)
        #expect(outcome.skipped.map(\.item) == ["middle"])
    }
}
