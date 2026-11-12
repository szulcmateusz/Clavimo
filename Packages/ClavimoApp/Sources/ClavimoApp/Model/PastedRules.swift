import ClavimoCore
import Foundation

/// Reads rules pasted as text, typically an AI assistant's answer: a whole
/// configuration, a list of rules or one rule, with or without a Markdown
/// code block around it, and action compasses alone or next to rules.
/// Missing bookkeeping fields are filled in, so only the trigger and the
/// action (or a compass's slots) really matter.
enum PastedRules {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// The configuration after adding the pasted rules to `current`, or the
    /// pasted configuration itself when a whole one was pasted.
    /// The text can hold one long JSON or several separate ones, for
    /// example several code blocks or rules pasted one after another.
    static func apply(_ text: String, to current: ConfigDocument) -> Result<ConfigDocument, Failure> {
        let pieces = extractAllJSON(from: text)
        guard !pieces.isEmpty else {
            return .failure(Failure(message: String(localized: "No rules found. Paste the JSON your assistant wrote, including the braces.")))
        }
        // Braces in the explanation around the code are not JSON; skip them.
        var values: [JSONValue] = []
        var sources: [String] = []
        for piece in pieces {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(piece.utf8)),
                  value.array != nil || value["trigger"] != nil || value["rules"] != nil || value["schemaVersion"] != nil
                  || value["compasses"] != nil || value["slots"] != nil else { continue }
            values.append(value)
            sources.append(piece)
        }
        guard !values.isEmpty else {
            return .failure(Failure(message: String(localized: "The text is not valid JSON. Copy the whole code block from the answer.")))
        }

        // A whole configuration replaces the current one, so it must be
        // pasted on its own.
        if let whole = values.firstIndex(where: { $0["schemaVersion"] != nil }) {
            guard values.count == 1 else {
                return .failure(Failure(message: String(localized: "Paste either a whole configuration or rules, not both.")))
            }
            do {
                return .success(try ConfigDocument.decode(Data(sources[whole].utf8)))
            } catch {
                return .failure(Failure(message: String(localized: "This looks like a whole configuration, but it cannot be read. Ask the assistant to check it against the schema.")))
            }
        }

        var ruleValues: [JSONValue] = []
        var compassValues: [JSONValue] = []
        func sort(_ value: JSONValue) {
            if value["slots"] != nil { compassValues.append(value) } else { ruleValues.append(value) }
        }
        for value in values {
            if value["rules"] != nil || value["compasses"] != nil {
                ruleValues += value["rules"]?.array ?? []
                compassValues += value["compasses"]?.array ?? []
            } else if let array = value.array {
                array.forEach(sort)
            } else if value["trigger"] != nil || value["slots"] != nil {
                sort(value)
            } else {
                return .failure(Failure(message: String(localized: "No rules found. A rule needs a trigger and an action.")))
            }
        }
        guard !ruleValues.isEmpty || !compassValues.isEmpty else {
            return .failure(Failure(message: String(localized: "No rules found. A rule needs a trigger and an action.")))
        }

        var updated = current
        for (index, value) in compassValues.enumerated() {
            guard case var .object(object) = value, object["slots"]?.array != nil else {
                return .failure(Failure(message: String(localized: "Compass \(index + 1) has no slots.")))
            }
            let name = object["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Compass")
            object["name"] = .string(name)
            if object["id"]?.string?.isEmpty != false {
                object["id"] = .string(freeCompassID(name, in: updated))
            }
            do {
                let data = try JSONEncoder().encode(JSONValue.object(object))
                let compass = try JSONDecoder().decode(ConfigDocument.Compass.self, from: data)
                var list = updated.compasses ?? []
                if let existing = list.firstIndex(where: { $0.id == compass.id }) {
                    list[existing] = compass
                } else {
                    list.append(compass)
                }
                updated.compasses = list
            } catch {
                return .failure(Failure(message: String(localized: "Compass \(index + 1) cannot be read. Ask the assistant to follow the Clavimo configuration format.")))
            }
        }
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

    /// An id made from the compass name that no compass uses yet.
    private static func freeCompassID(_ name: String, in document: ConfigDocument) -> String {
        let letters = name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        let stem = letters.isEmpty ? "compass" : String(String.UnicodeScalarView(letters).prefix(24))
        let used = Set((document.compasses ?? []).map(\.id))
        var candidate = stem
        var number = 2
        while used.contains(candidate) {
            candidate = "\(stem)\(number)"
            number += 1
        }
        return candidate
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
        extractAllJSON(from: text).first
    }

    /// Every top-level JSON object or array in `text`, in order.
    static func extractAllJSON(from text: String) -> [String] {
        let characters = Array(text)
        var result: [String] = []
        var position = 0
        while position < characters.count,
              let start = characters[position...].firstIndex(where: { $0 == "{" || $0 == "[" }) {
            guard let end = matchingEnd(in: characters, from: start) else { break }
            result.append(String(characters[start...end]))
            position = end + 1
        }
        return result
    }

    private static func matchingEnd(in characters: [Character], from start: Int) -> Int? {
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
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }
}
