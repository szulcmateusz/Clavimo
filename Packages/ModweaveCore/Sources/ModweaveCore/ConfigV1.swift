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
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var int: Int? {
        if case let .number(value) = self, value.rounded() == value, abs(value) <= 1e9 { return Int(value) }
        return nil
    }

    var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

/// The draft v1 configuration document (`schema/config-v1.schema.json`).
public struct ConfigDocument: Codable, Equatable, Sendable {
    public struct Engine: Codable, Equatable, Sendable {
        public var enabledOnLaunch: Bool
        public var failOpen: Bool
    }

    public struct Profile: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var inherits: String?
    }

    public struct Behavior: Codable, Equatable, Sendable {
        public var consumeTrigger: Bool
        public var fireOn: String
        public var `repeat`: String
        public var leaderPolicy: String?
        public var leaderWindowMs: Int?
        public var repeatCooldownMs: Int?
        public var allowProtectedButton: Bool?
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
}

/// Why an enabled rule is not active in the current engine.
public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    public let ruleID: String
    public let ruleName: String
    public let reason: String

    public var description: String { "\(ruleName): \(reason)" }
}

public struct InterpretedConfig: Equatable, Sendable {
    public var definitions: [RuleDefinition]
    /// Enabled rules in the active profile that cannot run yet. They are
    /// reported, never applied partially.
    public var unsupported: [ConfigIssue]
}

extension ConfigDocument {
    /// Translates enabled rules of the active profile into engine rule
    /// definitions. Profile inheritance and conditions are not supported
    /// yet; affected rules are reported as unsupported.
    public func interpret() throws -> InterpretedConfig {
        guard profiles.contains(where: { $0.id == activeProfileId }) else {
            throw ConfigLoadError.unknownActiveProfile(activeProfileId)
        }
        var result = InterpretedConfig(definitions: [], unsupported: [])
        for rule in rules where rule.enabled && rule.profileId == activeProfileId {
            switch Self.translate(rule) {
            case let .success(definition):
                result.definitions.append(definition)
            case let .failure(reason):
                result.unsupported.append(ConfigIssue(ruleID: rule.id, ruleName: rule.name, reason: reason.message))
            }
        }
        return result
    }

    private struct Unsupported: Error {
        let message: String
    }

    private static func translate(_ rule: Rule) -> Result<RuleDefinition, Unsupported> {
        do {
            return .success(try translateOrThrow(rule))
        } catch let error as Unsupported {
            return .failure(error)
        } catch {
            return .failure(Unsupported(message: "invalid rule"))
        }
    }

    private static func translateOrThrow(_ rule: Rule) throws -> RuleDefinition {
        if !rule.conditions.isEmpty {
            throw Unsupported(message: "conditions are not supported yet")
        }
        guard let triggerKind = rule.trigger["kind"]?.string, let actionKind = rule.action["kind"]?.string else {
            throw Unsupported(message: "missing trigger or action kind")
        }
        let behavior = rule.behavior

        switch (triggerKind, actionKind) {
        case ("keyPair", "swapKeys"):
            let first = try key(rule.trigger["first"])
            let second = try key(rule.trigger["second"])
            let sideMode = rule.action["sideMode"]?.string ?? "asSpecified"
            guard sideMode != "both" else {
                throw Unsupported(message: "sideMode both is not supported yet; add one rule per side")
            }
            return .swap(first, second)

        case ("key", "sendKey"):
            let from = try key(rule.trigger["key"])
            let to = try key(rule.action["key"])
            return .remap(from: from, to: to)

        case ("modifierChord", _):
            guard rule.trigger["key"] == nil, let number = rule.trigger["mouseButton"]?.int,
                  let button = MouseButton(userFacingNumber: number) else {
                throw Unsupported(message: "only modifier + mouse button chords are supported yet")
            }
            try requireFireOnceOnDown(behavior)
            let modifiers = try genericModifiers(rule.trigger["requiredModifiers"])
            return .mouseChord(
                id: rule.id,
                leader: .modifiers(modifiers),
                button: button,
                action: try action(rule.action),
                priority: rule.priority,
                allowProtectedButton: behavior.allowProtectedButton ?? false
            )

        case ("keyMouseChord", _):
            guard rule.trigger["order"]?.string == "leaderThenMouse" else {
                throw Unsupported(message: "only leaderThenMouse order is supported")
            }
            guard let number = rule.trigger["mouseButton"]?.int, let button = MouseButton(userFacingNumber: number) else {
                throw Unsupported(message: "invalid mouse button")
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
                throw Unsupported(message: "letter key chords need an explicit leaderPolicy")
            }
            return .mouseChord(
                id: rule.id,
                leader: .key(leader, policy),
                button: button,
                action: try action(rule.action),
                priority: rule.priority,
                allowProtectedButton: behavior.allowProtectedButton ?? false
            )

        default:
            throw Unsupported(message: "\(triggerKind) -> \(actionKind) is not supported yet")
        }
    }

    private static func requireFireOnceOnDown(_ behavior: Behavior) throws {
        guard behavior.consumeTrigger, behavior.fireOn == "down", behavior.repeat == "once" else {
            throw Unsupported(message: "chords currently require consumeTrigger, fireOn down and repeat once")
        }
    }

    private static func key(_ value: JSONValue?) throws -> KeyCode {
        guard let value, value["codeNamespace"]?.string == "macVirtualKeyCode",
              let code = value["code"]?.int, (0...Int(UInt16.max)).contains(code) else {
            throw Unsupported(message: "only macVirtualKeyCode keys are supported")
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
                throw Unsupported(message: "side-specific chord modifiers are not supported yet")
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
        case let kind:
            throw Unsupported(message: "action \(kind ?? "unknown") is not supported yet")
        }
    }
}
