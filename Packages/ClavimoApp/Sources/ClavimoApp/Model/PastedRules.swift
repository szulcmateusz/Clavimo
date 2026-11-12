import ClavimoCore
import Foundation

/// Reads rules pasted as text, typically an AI assistant's answer: a whole
/// configuration, a list of rules or one rule, with or without a Markdown
/// code block around it. Missing bookkeeping fields are filled in, so only
/// the trigger and the action really matter.
enum PastedRules {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// The configuration after adding the pasted rules to `current`, or the
    /// pasted configuration itself when a whole one was pasted.
    static func apply(_ text: String, to current: ConfigDocument) -> Result<ConfigDocument, Failure> {
        guard let json = extractJSON(from: text) else {
            return .failure(Failure(message: String(localized: "No rules found. Paste the JSON your assistant wrote, including the braces.")))
        }
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        } catch {
            return .failure(Failure(message: String(localized: "The text is not valid JSON. Copy the whole code block from the answer.")))
        }

        if value["schemaVersion"] != nil {
            do {
                return .success(try ConfigDocument.decode(Data(json.utf8)))
            } catch {
                return .failure(Failure(message: String(localized: "This looks like a whole configuration, but it cannot be read. Ask the assistant to check it against the schema.")))
            }
        }

        let ruleValues: [JSONValue]
        if let rules = value["rules"]?.array {
            ruleValues = rules
        } else if let array = value.array {
            ruleValues = array
        } else if value["trigger"] != nil {
            ruleValues = [value]
        } else {
            return .failure(Failure(message: String(localized: "No rules found. A rule needs a trigger and an action.")))
        }
        guard !ruleValues.isEmpty else {
            return .failure(Failure(message: String(localized: "No rules found. A rule needs a trigger and an action.")))
        }

        var updated = current
        for (index, ruleValue) in ruleValues.enumerated() {
            guard case var .object(object) = ruleValue, object["trigger"] != nil, object["action"] != nil else {
                return .failure(Failure(message: String(localized: "Rule \(index + 1) has no trigger or action.")))
            }
            fillDefaults(&object, index: index, document: updated)
            do {
                let data = try JSONEncoder().encode(JSONValue.object(object))
                let rule = try JSONDecoder().decode(ConfigDocument.Rule.self, from: data)
                if let existing = updated.rules.firstIndex(where: { $0.id == rule.id }) {
                    updated.rules[existing] = rule
                } else {
                    updated.rules.append(rule)
                }
            } catch {
                return .failure(Failure(message: String(localized: "Rule \(index + 1) cannot be read. Ask the assistant to follow the Clavimo configuration format.")))
            }
        }
        return .success(updated)
    }

    /// Fills the fields a rule must have but an assistant may leave out.
    private static func fillDefaults(_ rule: inout [String: JSONValue], index: Int, document: ConfigDocument) {
        if rule["id"]?.string?.isEmpty != false {
            rule["id"] = .string(UUID().uuidString.lowercased())
        }
        if rule["name"]?.string?.isEmpty != false {
            rule["name"] = .string(String(localized: "Pasted rule \(index + 1)"))
        }
        if rule["enabled"] == nil { rule["enabled"] = .bool(true) }
        if rule["priority"]?.int == nil { rule["priority"] = .number(50) }
        let profiles = Set(document.profiles.map(\.id))
        if let profile = rule["profileId"]?.string, profiles.contains(profile) {} else {
            rule["profileId"] = .string(document.activeProfileId)
        }
        if rule["conditions"]?.array == nil { rule["conditions"] = .array([]) }
        if rule["behavior"] == nil {
            rule["behavior"] = .object(["consumeTrigger": .bool(true), "fireOn": .string("down"), "repeat": .string("once")])
        }
        if rule["ui"] == nil { rule["ui"] = .object(["order": .number(Double(document.rules.count + index))]) }
    }

    /// The first JSON object or array in `text`, ignoring Markdown fences
    /// and any explanation around it.
    static func extractJSON(from text: String) -> String? {
        let characters = Array(text)
        guard let start = characters.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for index in start..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 { return String(characters[start...index]) }
            default: break
            }
        }
        return nil
    }
}
