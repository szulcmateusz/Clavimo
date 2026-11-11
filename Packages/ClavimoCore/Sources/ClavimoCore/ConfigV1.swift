import Foundation

/// A minimal JSON value, used to read rule triggers and actions whose
/// shape depends on their `kind` without accepting unchecked `Any`.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value):
            // Whole numbers are written without a fractional part so that
            // saved files stay valid against integer schema fields.
            if value.rounded() == value, abs(value) < 9e15 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    public var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var int: Int? {
        if case let .number(value) = self, value.rounded() == value, abs(value) <= 1e9 { return Int(value) }
        return nil
    }

    public var number: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

/// The draft v1 configuration document (`schema/config-v1.schema.json`).
public struct ConfigDocument: Codable, Equatable, Sendable {
    public struct Engine: Codable, Equatable, Sendable {
        public var enabledOnLaunch: Bool
        public var failOpen: Bool

        public init(enabledOnLaunch: Bool, failOpen: Bool = true) {
            self.enabledOnLaunch = enabledOnLaunch
            self.failOpen = failOpen
        }
    }

    public struct Profile: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var inherits: String?

        public init(id: String, name: String, inherits: String? = nil) {
            self.id = id
            self.name = name
            self.inherits = inherits
        }

        enum CodingKeys: String, CodingKey { case id, name, inherits }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            // The schema requires the key, with null for no parent.
            try container.encode(inherits, forKey: .inherits)
        }
    }

    public struct Behavior: Codable, Equatable, Sendable {
        public var consumeTrigger: Bool
        public var fireOn: String
        public var `repeat`: String
        public var leaderPolicy: String?
        public var leaderWindowMs: Int?
        public var repeatCooldownMs: Int?
        public var allowProtectedButton: Bool?

        public init(
            consumeTrigger: Bool,
            fireOn: String,
            repeat: String,
            leaderPolicy: String? = nil,
            leaderWindowMs: Int? = nil,
            repeatCooldownMs: Int? = nil,
            allowProtectedButton: Bool? = nil
        ) {
            self.consumeTrigger = consumeTrigger
            self.fireOn = fireOn
            self.repeat = `repeat`
            self.leaderPolicy = leaderPolicy
            self.leaderWindowMs = leaderWindowMs
            self.repeatCooldownMs = repeatCooldownMs
            self.allowProtectedButton = allowProtectedButton
        }
    }

    public struct Rule: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var enabled: Bool
        public var priority: Int
        public var profileId: String
        public var trigger: JSONValue
        public var conditions: [JSONValue]
        public var action: JSONValue
        public var behavior: Behavior
        public var ui: JSONValue

        public init(
            id: String, name: String, enabled: Bool, priority: Int, profileId: String,
            trigger: JSONValue, conditions: [JSONValue], action: JSONValue, behavior: Behavior, ui: JSONValue
        ) {
            self.id = id
            self.name = name
            self.enabled = enabled
            self.priority = priority
            self.profileId = profileId
            self.trigger = trigger
            self.conditions = conditions
            self.action = action
            self.behavior = behavior
            self.ui = ui
        }
    }

    public var schemaVersion: Int
    public var configId: String
    public var engine: Engine
    public var activeProfileId: String
    public var profiles: [Profile]
    public var rules: [Rule]
    public var macros: [JSONValue]
    public var deviceSettings: [JSONValue]?

    public static let supportedSchemaVersion = 1

    public init(
        configId: String = UUID().uuidString.lowercased(),
        engine: Engine = Engine(enabledOnLaunch: false),
        activeProfileId: String = "default",
        profiles: [Profile] = [Profile(id: "default", name: "Default")],
        rules: [Rule] = [],
        macros: [JSONValue] = [],
        deviceSettings: [JSONValue]? = nil
    ) {
        schemaVersion = Self.supportedSchemaVersion
        self.configId = configId
        self.engine = engine
        self.activeProfileId = activeProfileId
        self.profiles = profiles
        self.rules = rules
        self.macros = macros
        self.deviceSettings = deviceSettings
    }

    /// Stable, human-diffable JSON.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> ConfigDocument {
        let document = try JSONDecoder().decode(ConfigDocument.self, from: data)
        guard document.schemaVersion == supportedSchemaVersion else {
            throw ConfigLoadError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }
}

public enum ConfigLoadError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unknownActiveProfile(String)
    case unknownParentProfile(String)
    case profileCycle(String)
}

/// Why an enabled rule or device setting cannot run in the current engine.
/// The app turns these into localized sentences; `description` is the
/// English text used by the command line tools.
public enum UnsupportedReason: Equatable, Sendable, CustomStringConvertible {
    case invalidRule
    case invalidCondition(String)
    case unsupportedCondition(String)
    case unsupportedCombination(trigger: String, action: String)
    case bothSidesSwap
    case modifierKeyChord
    case chordOrder
    case invalidMouseButton
    case missingLeaderPolicy
    case chordBehavior
    case keyNamespace
    case sideSpecificChordModifiers
    case unsupportedAction(String)
    case trackpadSettings
    case pointerSettings
    case noScrollChange
    case perDeviceScrolling
    case displayScope
    case unsupportedScrollField(String)
    case unsupportedScrollMode(String)
    case scrollValueOutOfRange(mode: String)
    case invalidTrackpadTrigger

    public var description: String {
        switch self {
        case .invalidRule: "the rule is incomplete or malformed"
        case let .invalidCondition(kind): "the \(kind) condition is missing its value"
        case let .unsupportedCondition(kind): "condition \(kind) is not supported"
        case let .unsupportedCombination(trigger, action): "\(trigger) -> \(action) is not supported yet"
        case .bothSidesSwap: "sideMode both is not supported yet; add one rule per side"
        case .modifierKeyChord: "only modifier + mouse button chords are supported yet"
        case .chordOrder: "only leaderThenMouse order is supported"
        case .invalidMouseButton: "invalid mouse button"
        case .missingLeaderPolicy: "letter key chords need an explicit leaderPolicy"
        case .chordBehavior: "chords currently require consumeTrigger, fireOn down and repeat once"
        case .keyNamespace: "only macVirtualKeyCode keys are supported"
        case .sideSpecificChordModifiers: "side-specific chord modifiers are not supported yet"
        case let .unsupportedAction(kind): "action \(kind) is not supported yet"
        case .trackpadSettings: "only mouse and trackpad device settings are supported"
        case .pointerSettings: "pointer speed and acceleration are not supported yet"
        case .noScrollChange: "no supported scroll change in this setting"
        case .perDeviceScrolling: "per-device scrolling is not supported yet"
        case .displayScope: "display scope is not supported"
        case let .unsupportedScrollField(field): "scroll \(field) is not supported yet"
        case let .unsupportedScrollMode(mode): "scroll mode \(mode) is not supported yet"
        case let .scrollValueOutOfRange(mode): "the \(mode) value is out of range"
        case .invalidTrackpadTrigger: "the trackpad gesture is incomplete or not supported"
        }
    }
}

/// Why an enabled rule is not active in the current engine.
public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    public let ruleID: String
    public let ruleName: String
    public let reason: UnsupportedReason

    public var description: String { "\(ruleName): \(reason)" }
}

public struct InterpretedConfig: Equatable, Sendable {
    public var definitions: [RuleDefinition]
    /// Enabled rules in the active profile that cannot run yet. They are
    /// reported, never applied partially.
    public var unsupported: [ConfigIssue]
}

extension ConfigDocument {
    /// The active profile followed by the profiles it inherits from,
    /// nearest first.
    public func profileChain() throws -> [String] {
        var chain: [String] = []
        var current: String? = activeProfileId
        while let id = current {
            guard let profile = profiles.first(where: { $0.id == id }) else {
                throw id == activeProfileId ? ConfigLoadError.unknownActiveProfile(id) : ConfigLoadError.unknownParentProfile(id)
            }
            guard !chain.contains(id) else { throw ConfigLoadError.profileCycle(id) }
            chain.append(id)
            current = profile.inherits
        }
        return chain
    }

    /// Translates enabled rules and device settings of the active profile
    /// and the profiles it inherits from into engine rule definitions.
    /// A rule in a nearer profile replaces inherited rules with the same
    /// trigger. Anything the engine cannot run is reported as unsupported.
    public func interpret() throws -> InterpretedConfig {
        let chain = try profileChain()
        var result = InterpretedConfig(definitions: [], unsupported: [])
        var claimed: Set<String> = []
        // Nearest profile first, so its rules claim triggers before
        // inherited rules are considered.
        for profileID in chain {
            var level: [RuleDefinition] = []
            for rule in rules where rule.enabled && rule.profileId == profileID {
                switch Self.translate(rule) {
                case let .success(definition):
                    level.append(definition)
                case let .failure(reason):
                    result.unsupported.append(ConfigIssue(ruleID: rule.id, ruleName: rule.name, reason: reason.reason))
                }
            }
            for setting in deviceSettings ?? [] {
                guard setting["enabled"] == .bool(true), setting["profileId"]?.string == profileID else { continue }
                let id = setting["id"]?.string ?? "?"
                let name = setting["name"]?.string ?? id
                do {
                    level.append(try Self.translateDeviceSetting(setting))
                } catch let error as Unsupported {
                    result.unsupported.append(ConfigIssue(ruleID: id, ruleName: name, reason: error.reason))
                } catch {
                    result.unsupported.append(ConfigIssue(ruleID: id, ruleName: name, reason: .invalidRule))
                }
            }
            var levelClaims: Set<String> = []
            for definition in level where definition.triggerSignatures.isDisjoint(with: claimed) {
                result.definitions.append(definition)
                levelClaims.formUnion(definition.triggerSignatures)
            }
            claimed.formUnion(levelClaims)
        }
        return result
    }

    /// Mouse wheel direction and scroll modes are supported. Pointer
    /// settings and smoothed scrolling are reported as unsupported.
    private static func translateDeviceSetting(_ setting: JSONValue) throws -> RuleDefinition {
        if setting["scope"]?["deviceClass"]?.string == "trackpad" {
            return try translateTrackpadSetting(setting)
        }
        guard setting["scope"]?["deviceClass"]?.string == "mouse" else {
            throw Unsupported(.trackpadSettings)
        }
        if let pointer = setting["pointer"], pointer["accelerationMode"]?.string != "system" || pointer["speedMultiplier"] != nil {
            throw Unsupported(.pointerSettings)
        }
        let vertical = try scrollAxis(setting["scrolling"]?["vertical"])
        let horizontal = try scrollAxis(setting["scrolling"]?["horizontal"])
        guard vertical.changesEvents || horizontal.changesEvents else {
            throw Unsupported(.noScrollChange)
        }
        var conditions = RuleConditions()
        let scope = setting["scope"]
        if scope?["vendorId"] != nil || scope?["productId"] != nil {
            // Scroll events cannot be attributed to a device yet; applying
            // the setting to every wheel would silently widen its scope.
            throw Unsupported(.perDeviceScrolling)
        }
        if let app = scope?["appBundleId"]?.string {
            conditions.onlyApps = [app]
        }
        if scope?["displayId"] != nil {
            throw Unsupported(.displayScope)
        }
        return .wheel(vertical: vertical, horizontal: horizontal, conditions: conditions)
    }

    /// Trackpad scrolling: direction per axis, one speed for both axes,
    /// and momentum. Pointer settings are not supported.
    private static func translateTrackpadSetting(_ setting: JSONValue) throws -> RuleDefinition {
        if setting["pointer"] != nil { throw Unsupported(.pointerSettings) }
        let scope = setting["scope"]
        if scope?["vendorId"] != nil || scope?["productId"] != nil { throw Unsupported(.perDeviceScrolling) }
        if scope?["displayId"] != nil { throw Unsupported(.displayScope) }
        var speeds: [Double] = []
        var reverse: [Bool] = []
        for axis in ["vertical", "horizontal"] {
            let config = setting["scrolling"]?[axis]
            reverse.append(config?["reverse"] == .bool(true))
            switch config?["mode"]?.string ?? "system" {
            case "system":
                break
            case "accelerated":
                guard let speed = config?["speedMultiplier"]?.number, TrackpadScrollSettings.speedRange.contains(speed) else {
                    throw Unsupported(.scrollValueOutOfRange(mode: "accelerated"))
                }
                speeds.append(speed)
            case let other:
                throw Unsupported(.unsupportedScrollMode(other))
            }
        }
        guard Set(speeds).count <= 1 else { throw Unsupported(.unsupportedScrollField("speedMultiplier")) }
        let settings = TrackpadScrollSettings(
            reverseVertical: reverse[0], reverseHorizontal: reverse[1], speed: speeds.first ?? 1,
            momentum: setting["scrolling"]?["momentum"] != .bool(false)
        )
        guard settings.changesEvents else { throw Unsupported(.noScrollChange) }
        var conditions = RuleConditions()
        if let app = scope?["appBundleId"]?.string { conditions.onlyApps = [app] }
        return .trackpadScroll(settings, conditions: conditions)
    }

    private static func scrollAxis(_ config: JSONValue?) throws -> ScrollAxisSettings {
        guard let config else { return .unchanged }
        for key in ["acceleration"] where config[key] != nil {
            throw Unsupported(.unsupportedScrollField(key))
        }
        if config["smoothing"] != nil, config["mode"]?.string != "smoothed" {
            throw Unsupported(.unsupportedScrollField("smoothing"))
        }
        let mode: ScrollMode
        switch config["mode"]?.string ?? "system" {
        case "system":
            mode = .system
        case "accelerated":
            guard let speed = config["speedMultiplier"]?.number, ScrollMode.speedRange.contains(speed) else {
                throw Unsupported(.scrollValueOutOfRange(mode: "accelerated"))
            }
            mode = .accelerated(speed: speed)
        case "byLines":
            guard let lines = config["distanceLines"]?.int, ScrollMode.linesRange.contains(lines) else {
                throw Unsupported(.scrollValueOutOfRange(mode: "byLines"))
            }
            mode = .byLines(lines)
        case "byPixels":
            guard let pixels = config["distancePixels"]?.number, ScrollMode.pixelsRange.contains(pixels) else {
                throw Unsupported(.scrollValueOutOfRange(mode: "byPixels"))
            }
            mode = .byPixels(pixels)
        case "smoothed":
            let pixels = config["distancePixels"]?.number ?? SmoothScroller.Settings.standard.pixelsPerNotch
            let duration = config["smoothing"]?["response"]?.number ?? SmoothScroller.Settings.standard.duration
            guard SmoothScroller.Settings.pixelsRange.contains(pixels), SmoothScroller.Settings.durationRange.contains(duration) else {
                throw Unsupported(.scrollValueOutOfRange(mode: "smoothed"))
            }
            mode = .smoothed(SmoothScroller.Settings(pixelsPerNotch: pixels, duration: duration))
        case let other:
            throw Unsupported(.unsupportedScrollMode(other))
        }
        return ScrollAxisSettings(reverse: config["reverse"] == .bool(true), mode: mode)
    }

    private struct Unsupported: Error {
        let reason: UnsupportedReason
        init(_ reason: UnsupportedReason) { self.reason = reason }
    }

    private static func translate(_ rule: Rule) -> Result<RuleDefinition, Unsupported> {
        do {
            return .success(try translateOrThrow(rule))
        } catch let error as Unsupported {
            return .failure(error)
        } catch {
            return .failure(Unsupported(.invalidRule))
        }
    }

    private static func conditions(_ values: [JSONValue]) throws -> RuleConditions {
        var result = RuleConditions()
        for value in values {
            switch value["kind"]?.string {
            case "appIs":
                guard let id = value["bundleId"]?.string, !id.isEmpty else { throw Unsupported(.invalidCondition("appIs")) }
                result.onlyApps.insert(id)
            case "appIsNot":
                guard let id = value["bundleId"]?.string, !id.isEmpty else { throw Unsupported(.invalidCondition("appIsNot")) }
                result.exceptApps.insert(id)
            case "physicalDeviceIs":
                guard let text = value["deviceId"]?.string, let device = DeviceID(string: text) else {
                    throw Unsupported(.invalidCondition("physicalDeviceIs"))
                }
                result.devices.insert(device)
            case let kind:
                throw Unsupported(.unsupportedCondition(kind ?? "unknown"))
            }
        }
        return result
    }

    private static func translateOrThrow(_ rule: Rule) throws -> RuleDefinition {
        let conditions = try conditions(rule.conditions)
        guard let triggerKind = rule.trigger["kind"]?.string, let actionKind = rule.action["kind"]?.string else {
            throw Unsupported(.invalidRule)
        }
        let behavior = rule.behavior

        switch (triggerKind, actionKind) {
        case ("keyPair", "swapKeys"):
            let first = try key(rule.trigger["first"])
            let second = try key(rule.trigger["second"])
            let sideMode = rule.action["sideMode"]?.string ?? "asSpecified"
            guard sideMode != "both" else {
                throw Unsupported(.bothSidesSwap)
            }
            return .swap(first, second, conditions: conditions)

        case ("key", "sendKey"):
            let from = try key(rule.trigger["key"])
            let to = try key(rule.action["key"])
            return .remap(from: from, to: to, conditions: conditions)

        case ("modifierChord", _):
            guard rule.trigger["key"] == nil, let number = rule.trigger["mouseButton"]?.int,
                  let button = MouseButton(userFacingNumber: number) else {
                throw Unsupported(.modifierKeyChord)
            }
            try requireFireOnceOnDown(behavior)
            let modifiers = try genericModifiers(rule.trigger["requiredModifiers"])
            return .mouseChord(
                id: rule.id,
                leader: .modifiers(modifiers),
                button: button,
                action: try action(rule.action),
                priority: rule.priority,
                allowProtectedButton: behavior.allowProtectedButton ?? false,
                conditions: conditions
            )

        case ("keyMouseChord", _):
            guard rule.trigger["order"]?.string == "leaderThenMouse" else {
                throw Unsupported(.chordOrder)
            }
            guard let number = rule.trigger["mouseButton"]?.int, let button = MouseButton(userFacingNumber: number) else {
                throw Unsupported(.invalidMouseButton)
            }
            try requireFireOnceOnDown(behavior)
            let leader = try key(rule.trigger["leaderKey"])
            let policy: LeaderPolicy
            switch behavior.leaderPolicy {
            case "boundedWindow":
                policy = .boundedWindow(milliseconds: behavior.leaderWindowMs ?? LeaderPolicy.defaultWindowMilliseconds)
            case "deferredUntilUp":
                policy = .deferredUntilUp
            case "nonConsuming":
                policy = .nonConsuming
            default:
                throw Unsupported(.missingLeaderPolicy)
            }
            return .mouseChord(
                id: rule.id,
                leader: .key(leader, policy),
                button: button,
                action: try action(rule.action),
                priority: rule.priority,
                allowProtectedButton: behavior.allowProtectedButton ?? false,
                conditions: conditions
            )

        case ("trackpadGesture", _), ("trackpadClick", _):
            guard conditions.devices.isEmpty else { throw Unsupported(.unsupportedCondition("physicalDeviceIs")) }
            return .trackpad(
                id: rule.id,
                trigger: try trackpadTrigger(rule.trigger),
                modifiers: try genericModifiers(rule.trigger["requiredModifiers"]),
                action: try action(rule.action),
                priority: rule.priority,
                conditions: conditions
            )

        default:
            throw Unsupported(.unsupportedCombination(trigger: triggerKind, action: actionKind))
        }
    }

    private static func trackpadTrigger(_ trigger: JSONValue) throws -> TrackpadTrigger {
        let fingers = trigger["fingers"]?.int
        if trigger["kind"]?.string == "trackpadClick" {
            if let corner = trigger["corner"]?.string {
                guard fingers == nil, let corner = TrackpadCorner(rawValue: corner) else { throw Unsupported(.invalidTrackpadTrigger) }
                return .cornerClick(corner)
            }
            guard let fingers else { throw Unsupported(.invalidTrackpadTrigger) }
            return .click(fingers: fingers)
        }
        switch trigger["gesture"]?.string {
        case "tap":
            guard let fingers else { throw Unsupported(.invalidTrackpadTrigger) }
            return .gesture(.tap(fingers: fingers))
        case "tipTap":
            guard let side = trigger["side"]?.string.flatMap(GestureEvent.Side.init(rawValue:)) else {
                throw Unsupported(.invalidTrackpadTrigger)
            }
            return .gesture(.tipTap(side))
        case "swipe":
            guard let fingers, let direction = trigger["direction"]?.string.flatMap(GestureEvent.Direction.init(rawValue:)) else {
                throw Unsupported(.invalidTrackpadTrigger)
            }
            return .gesture(.swipe(fingers: fingers, direction))
        default:
            throw Unsupported(.invalidTrackpadTrigger)
        }
    }

    private static func requireFireOnceOnDown(_ behavior: Behavior) throws {
        guard behavior.consumeTrigger, behavior.fireOn == "down", behavior.repeat == "once" else {
            throw Unsupported(.chordBehavior)
        }
    }

    private static func key(_ value: JSONValue?) throws -> KeyCode {
        guard let value, value["codeNamespace"]?.string == "macVirtualKeyCode",
              let code = value["code"]?.int, (0...Int(UInt16.max)).contains(code) else {
            throw Unsupported(.keyNamespace)
        }
        return KeyCode(UInt16(code))
    }

    private static func genericModifiers(_ value: JSONValue?) throws -> GenericModifiers {
        var result: GenericModifiers = []
        for item in value?.array ?? [] {
            switch item.string {
            case "command": result.insert(.command)
            case "option": result.insert(.option)
            case "control": result.insert(.control)
            case "shift": result.insert(.shift)
            case "function": result.insert(.function)
            default:
                throw Unsupported(.sideSpecificChordModifiers)
            }
        }
        return result
    }

    private static func action(_ value: JSONValue) throws -> ActionCommand {
        switch value["kind"]?.string {
        case "nextWorkspace": return .nextWorkspace
        case "previousWorkspace": return .previousWorkspace
        case "missionControl": return .missionControl
        case "applicationWindows": return .applicationWindows
        case "sendShortcut":
            return .shortcut(try key(value["key"]), try genericModifiers(value["modifiers"]))
        case "mouseClick":
            guard let number = value["mouseButton"]?.int, let button = MouseButton(userFacingNumber: number) else {
                throw Unsupported(.invalidMouseButton)
            }
            return .click(button)
        case "launchApp":
            guard let bundleID = value["bundleId"]?.string, !bundleID.isEmpty else { throw Unsupported(.unsupportedAction("launchApp")) }
            return .launchApp(bundleID)
        case "mediaKey":
            guard let key = value["key"]?.string.flatMap(MediaKey.init(rawValue:)) else { throw Unsupported(.unsupportedAction("mediaKey")) }
            return .media(key)
        case let kind:
            throw Unsupported(.unsupportedAction(kind ?? "unknown"))
        }
    }
}
