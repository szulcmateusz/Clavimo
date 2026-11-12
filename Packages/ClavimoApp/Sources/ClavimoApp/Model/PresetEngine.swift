import ClavimoCore
import Foundation

/// Puts presets into a configuration and takes them out again. Every item is
/// checked the way a save is checked; items that would clash with what is
/// already there are left out with a reason, and the caller saves the result
/// in one go, so a preset is never half applied.
enum PresetEngine {
    struct Skipped: Equatable {
        let item: String
        let reason: String
    }

    struct Outcome {
        var document: ConfigDocument
        var applied: [String] = []
        var skipped: [Skipped] = []
    }

    // MARK: - Marks

    /// Rules carry their preset in `ui`, settings and compasses in their id,
    /// so taking a preset out removes exactly what it added.
    static func settingID(_ preset: String, _ item: String) -> String { "preset.\(preset).\(item)" }
    static func compassID(_ preset: String, _ item: String) -> String { "preset-\(preset)-\(item)" }

    /// The items of `preset` that are in the configuration.
    static func appliedItems(_ preset: Preset, in document: ConfigDocument) -> Set<String> {
        var result: Set<String> = []
        for rule in document.rules where rule.ui["preset"]?.string == preset.id {
            if let item = rule.ui["presetItem"]?.string { result.insert(item) }
        }
        for item in preset.items {
            if (document.deviceSettings ?? []).contains(where: { $0["id"]?.string == settingID(preset.id, item.id) })
                || (document.compasses ?? []).contains(where: { $0.id == compassID(preset.id, item.id) }) {
                result.insert(item.id)
            }
        }
        return result
    }

    // MARK: - Apply

    static func apply(_ preset: Preset, items chosen: Set<String>, to document: ConfigDocument, hardware: Hardware) -> Outcome {
        var outcome = Outcome(document: document)
        let context = PresetContext(hardware: hardware, profileID: document.activeProfileId)
        let already = appliedItems(preset, in: document)
        for item in preset.items where chosen.contains(item.id) {
            if already.contains(item.id) {
                outcome.skipped.append(Skipped(item: item.id, reason: String(localized: "Already on.")))
                continue
            }
            if let reason = item.unavailable(hardware, outcome.document) {
                outcome.skipped.append(Skipped(item: item.id, reason: reason))
                continue
            }
            var candidate = outcome.document
            if let reason = add(item.changes(context), preset: preset.id, item: item.id, to: &candidate) {
                outcome.skipped.append(Skipped(item: item.id, reason: reason))
                continue
            }
            if let reason = problem(adding: candidate, to: outcome.document) {
                outcome.skipped.append(Skipped(item: item.id, reason: reason))
                continue
            }
            outcome.document = candidate
            outcome.applied.append(item.id)
        }
        return outcome
    }

    /// Writes the changes into `document`; returns a reason when they cannot go in.
    private static func add(_ changes: [PresetChange], preset: String, item: String, to document: inout ConfigDocument) -> String? {
        func mark(_ rule: inout ConfigDocument.Rule) {
            var ui: [String: JSONValue] = ["order": .number(Double(document.rules.count))]
            ui["preset"] = .string(preset)
            ui["presetItem"] = .string(item)
            rule.ui = .object(ui)
        }
        for change in changes {
            switch change {
            case var .rule(draft):
                draft.profileID = document.activeProfileId
                var rule = draft.makeRule(id: UUID().uuidString.lowercased(), order: document.rules.count)
                mark(&rule)
                document.rules.append(rule)
            case var .keyboard(draft, fixedID):
                draft.profileID = document.activeProfileId
                let id = fixedID ?? UUID().uuidString.lowercased()
                if document.rules.contains(where: { $0.id == id }) {
                    return String(localized: "This key is already set up.")
                }
                var rule = draft.makeRule(id: id, order: document.rules.count)
                mark(&rule)
                document.rules.append(rule)
            case var .setting(draft):
                draft.profileID = document.activeProfileId
                var settings = document.deviceSettings ?? []
                settings.append(draft.makeDeviceSetting(id: settingID(preset, item)))
                document.deviceSettings = settings
            case var .compass(compass):
                // Presets name their compasses with `compassID`, so the
                // trigger rules of the same item already point to it.
                compass.id = compassID(preset, item)
                var list = document.compasses ?? []
                list.removeAll { $0.id == compass.id }
                list.append(compass.document)
                document.compasses = list
            }
        }
        return nil
    }

    /// Why `candidate` must not replace `current`: it does not save, it
    /// leaves a rule unable to run, or it silently replaces a rule that
    /// worked (a preset rule in a profile shadowing an inherited one).
    private static func problem(adding candidate: ConfigDocument, to current: ConfigDocument) -> String? {
        let before: InterpretedConfig
        let after: InterpretedConfig
        do {
            before = try current.interpret()
            after = try candidate.interpret()
        } catch {
            return String(localized: "The configuration cannot be read.")
        }
        if case let .failure(failure) = CompiledRules.compile(after.definitions) {
            let names = Dictionary(candidate.rules.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            return Messages.describe(ConfigStore.LoadError.rejected(failure.errors), ruleNames: names)
        }
        if after.unsupported.count > before.unsupported.count {
            return after.unsupported.last.map { Messages.describe($0.reason) } ?? String(localized: "It cannot run here.")
        }
        if !before.definitions.allSatisfy(after.definitions.contains) {
            return String(localized: "You already have a rule for the same keys or buttons.")
        }
        return nil
    }

    // MARK: - Remove

    /// The configuration without anything `preset` added. Rules the user
    /// changed since keep working: editing a rule removes its mark.
    static func remove(_ preset: Preset, from document: ConfigDocument) -> ConfigDocument {
        var updated = document
        let compassIDs = Set(preset.items.map { compassID(preset.id, $0.id) })
        updated.rules.removeAll { rule in
            rule.ui["preset"]?.string == preset.id
                || compassIDs.contains { ConfigEditor.opens($0, rule) }
        }
        let settingIDs = Set(preset.items.map { settingID(preset.id, $0.id) })
        updated.deviceSettings?.removeAll { settingIDs.contains($0["id"]?.string ?? "") }
        if updated.deviceSettings?.isEmpty == true { updated.deviceSettings = nil }
        updated.compasses?.removeAll { compassIDs.contains($0.id) }
        if updated.compasses?.isEmpty == true { updated.compasses = nil }
        return updated
    }
}
