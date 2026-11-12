import ClavimoCore
import Foundation
import Testing
@testable import ClavimoApp

@Suite("Ready-made setups")
struct PresetTests {
    static let empty = ConfigDocument(configId: "c", engine: .init(enabledOnLaunch: true), activeProfileId: "default",
                                      profiles: [.init(id: "default", name: "Default")])

    static let pcKeyboard = Hardware.Device(id: DeviceID(vendorID: 1241, productID: 4), name: "USB Keyboard", transport: "USB",
                                            isKeyboard: true, isPointer: false)
    static let builtIn = Hardware.Device(id: DeviceID(vendorID: 1452, productID: 832), name: "Apple Internal Keyboard / Trackpad",
                                         transport: "FIFO", isKeyboard: true, isPointer: true)
    static let receiver = Hardware.Device(id: DeviceID(vendorID: 1133, productID: 50475), name: "USB Receiver", transport: "USB",
                                          isKeyboard: true, isPointer: true)
    static let everything = Hardware(devices: [builtIn, receiver, pcKeyboard])

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
        #expect(laptop.hasTrackpad && !laptop.hasMouse && laptop.pcKeyboards.isEmpty)
        let desk = Self.everything
        #expect(desk.hasTrackpad && desk.hasMouse && desk.hasLogitech)
        #expect(desk.pcKeyboards.map(\.id) == [Self.pcKeyboard.id], "a receiver counts as a mouse, not a PC keyboard")
        let magic = Hardware(devices: [Hardware.Device(id: DeviceID(vendorID: 1452, productID: 613), name: "Magic Trackpad",
                                                       transport: "Bluetooth", isKeyboard: false, isPointer: true)])
        #expect(magic.hasTrackpad && !magic.hasMouse)
        #expect(Hardware(devices: [], otherApps: ["Logi Options+"]).usesLogiOptions)
        let mxKeys = Hardware.Device(id: DeviceID(vendorID: 1133, productID: 45934), name: "MX Keys Mini", transport: "Bluetooth Low Energy",
                                     isKeyboard: true, isPointer: false)
        #expect(Hardware(devices: [mxKeys]).pcKeyboards.isEmpty, "Logitech keyboards switch to a Mac layout themselves")
    }

    @Test func recommendationsFollowTheHardware() {
        #expect(Presets.ordered(for: Hardware(devices: [Self.builtIn])).first?.id == "trackpad")
        let pcOnly = Hardware(devices: [Self.pcKeyboard])
        #expect(Presets.ordered(for: pcOnly).first?.id == "windows")
        #expect(!Presets.developer.fits(Self.everything), "programmers choose it themselves")
    }

    @Test(arguments: ["trackpad", "mouse", "windows", "developer"])
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
        // The wheel item is in two presets; only the first one adds it.
        #expect(document.deviceSettings?.count == 1)
    }

    @Test func applyingTwiceAddsNothing() {
        let preset = Presets.trackpad
        let first = PresetEngine.apply(preset, items: ["middle", "volume"], to: Self.empty, hardware: Self.everything)
        #expect(PresetEngine.appliedItems(preset, in: first.document) == ["middle", "volume"])
        let second = PresetEngine.apply(preset, items: ["middle", "volume"], to: first.document, hardware: Self.everything)
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
        // Caps Lock already set, and a rule on ⌥ + button 4 already there.
        var document = Self.empty
        var caps = KeyboardRuleDraft()
        caps.output = .key(KeyCode.escape.rawValue)
        document.rules.append(caps.makeRule(id: KeyboardPane.capsLockRuleID, order: 0))
        var side = RuleDraft()
        side.kind = .modifierClick
        side.modifiers = [.option]
        side.button = 4
        side.action = .missionControl
        document.rules.append(side.makeRule(id: "mine", order: 1))

        let developer = PresetEngine.apply(Presets.developer, items: ["caps"], to: document, hardware: Self.everything)
        #expect(developer.skipped.map(\.item) == ["caps"])
        let mouse = PresetEngine.apply(Presets.mouse, items: ["spaces", "compass"], to: document, hardware: Self.everything)
        #expect(mouse.skipped.map(\.item) == ["spaces"])
        #expect(mouse.applied == ["compass"])
        #expect(mouse.document.rules.contains { $0.id == "mine" }, "the user's own rule stays")
    }

    @Test func theCompassItemStepsAsideForAnExistingCompass() {
        var document = Self.empty
        document.compasses = [ConfigDocument.Compass(id: "main", name: "Main", slots: [])]
        var trigger = RuleDraft()
        trigger.kind = .modifierClick
        trigger.modifiers = [.command]
        trigger.button = 5
        trigger.action = .openCompass
        trigger.compassID = "main"
        document.rules.append(trigger.makeRule(id: "t", order: 0))
        let outcome = PresetEngine.apply(Presets.mouse, items: ["compass"], to: document, hardware: Self.everything)
        #expect(outcome.applied.isEmpty)
        #expect(outcome.skipped.first?.reason.isEmpty == false)
    }

    @Test func thePCKeyboardSwapNeedsAPCKeyboard() {
        let outcome = PresetEngine.apply(Presets.windows, items: ["swap"], to: Self.empty, hardware: Hardware(devices: [Self.builtIn]))
        #expect(outcome.skipped.map(\.item) == ["swap"])
        let withKeyboard = PresetEngine.apply(Presets.windows, items: ["swap"], to: Self.empty, hardware: Self.everything)
        let rule = withKeyboard.document.rules.first
        #expect(rule?.conditions.first?["deviceId"]?.string == "1241:4", "the swap applies to the PC keyboard only")
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
