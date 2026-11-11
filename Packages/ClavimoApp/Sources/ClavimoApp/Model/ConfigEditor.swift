import ClavimoCore
import Foundation
import Observation

/// Edits the configuration document on behalf of the settings window.
/// Every change is validated and saved immediately; rules the form cannot
/// represent are preserved exactly as written.
@MainActor
@Observable
final class ConfigEditor {
    struct Row: Identifiable, Equatable {
        enum Source: Equatable { case rule, deviceSetting }
        let id: String
        let source: Source
        let name: String
        let enabled: Bool
        let profileID: String
        /// Nil for advanced rules that can only be edited in the JSON file.
        let draft: RuleDraft?
    }

    private let store: ConfigStore
    private(set) var document: ConfigDocument?
    private(set) var rows: [Row] = []
    var lastError: String?
    var onSaved: () -> Void = {}

    init(store: ConfigStore) {
        self.store = store
        reload()
    }

    func reload() {
        switch store.load() {
        case let .success(loaded):
            document = loaded.document
            lastError = nil
        case let .failure(error):
            document = nil
            lastError = Messages.describe(error)
        }
        rebuildRows()
    }

    private func rebuildRows() {
        guard let document else { rows = []; return }
        var result: [Row] = document.rules.map { rule in
            Row(id: rule.id, source: .rule, name: rule.name, enabled: rule.enabled, profileID: rule.profileId, draft: RuleDraft(rule: rule))
        }
        for setting in document.deviceSettings ?? [] {
            guard let id = setting["id"]?.string else { continue }
            let draft = RuleDraft(deviceSetting: setting)
            result.append(Row(id: id, source: .deviceSetting, name: setting["name"]?.string ?? id,
                              enabled: setting["enabled"] == .bool(true), profileID: setting["profileId"]?.string ?? "default",
                              draft: draft))
        }
        rows = result
    }

    /// Inserts or replaces a rule. Returns an error message when the result
    /// would be invalid; the file is then left unchanged.
    @discardableResult
    func upsert(_ draft: RuleDraft, id existingID: String?) -> String? {
        guard var updated = document else { return lastError ?? "Configuration is not loaded." }
        if let message = draft.validationMessage { return message }
        let id = existingID ?? UUID().uuidString.lowercased()
        remove(id: id, from: &updated)
        if draft.kind == .wheel {
            var settings = updated.deviceSettings ?? []
            settings.append(draft.makeDeviceSetting(id: id))
            updated.deviceSettings = settings
        } else {
            let rule = draft.makeRule(id: id, order: updated.rules.count)
            if let index = document?.rules.firstIndex(where: { $0.id == id }), index <= updated.rules.count {
                updated.rules.insert(rule, at: index)
            } else {
                updated.rules.append(rule)
            }
        }
        return commit(updated)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, id: String) -> String? {
        guard var updated = document else { return nil }
        if let index = updated.rules.firstIndex(where: { $0.id == id }) {
            updated.rules[index].enabled = enabled
        } else if var settings = updated.deviceSettings,
                  let index = settings.firstIndex(where: { $0["id"]?.string == id }),
                  case var .object(object) = settings[index] {
            object["enabled"] = .bool(enabled)
            settings[index] = .object(object)
            updated.deviceSettings = settings
        }
        return commit(updated)
    }

    @discardableResult
    func delete(id: String) -> String? {
        guard var updated = document else { return nil }
        remove(id: id, from: &updated)
        return commit(updated)
    }

    @discardableResult
    func setEnabledOnLaunch(_ enabled: Bool) -> String? {
        guard var updated = document else { return nil }
        updated.engine.enabledOnLaunch = enabled
        return commit(updated)
    }

    var enabledOnLaunch: Bool { document?.engine.enabledOnLaunch ?? false }

    // MARK: Profiles

    var profiles: [ConfigDocument.Profile] { document?.profiles ?? [] }
    var activeProfileID: String { document?.activeProfileId ?? "default" }

    func profileName(_ id: String) -> String {
        profiles.first { $0.id == id }?.name ?? id
    }

    /// Profiles the given profile inherits from, nearest first.
    func ancestors(of id: String) -> [String] {
        var result: [String] = []
        var current = profiles.first { $0.id == id }?.inherits
        while let parent = current, !result.contains(parent), parent != id {
            result.append(parent)
            current = profiles.first { $0.id == parent }?.inherits
        }
        return result
    }

    @discardableResult
    func setActiveProfile(_ id: String) -> String? {
        guard var updated = document, updated.profiles.contains(where: { $0.id == id }) else { return nil }
        updated.activeProfileId = id
        return commit(updated)
    }

    /// Adds a profile that inherits from Default and returns its ID.
    @discardableResult
    func addProfile(named name: String) -> String? {
        guard var updated = document else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let base = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        var id = base.isEmpty ? "profile" : base
        while updated.profiles.contains(where: { $0.id == id }) { id += "-\(Int.random(in: 10...99))" }
        updated.profiles.append(ConfigDocument.Profile(id: id, name: trimmed, inherits: updated.profiles.first?.id))
        return commit(updated) == nil ? id : nil
    }

    @discardableResult
    func renameProfile(_ id: String, to name: String) -> String? {
        guard var updated = document, let index = updated.profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        updated.profiles[index].name = trimmed
        return commit(updated)
    }

    /// Deletes a profile and its own rules. The base profile cannot be
    /// deleted; profiles that inherited from it inherit from its parent.
    @discardableResult
    func deleteProfile(_ id: String) -> String? {
        guard var updated = document, updated.profiles.count > 1, updated.profiles.first?.id != id,
              let profile = updated.profiles.first(where: { $0.id == id }) else { return nil }
        updated.profiles.removeAll { $0.id == id }
        for index in updated.profiles.indices where updated.profiles[index].inherits == id {
            updated.profiles[index].inherits = profile.inherits
        }
        updated.rules.removeAll { $0.profileId == id }
        updated.deviceSettings?.removeAll { $0["profileId"]?.string == id }
        if updated.activeProfileId == id { updated.activeProfileId = profile.inherits ?? updated.profiles[0].id }
        return commit(updated)
    }

    private func remove(id: String, from document: inout ConfigDocument) {
        document.rules.removeAll { $0.id == id }
        document.deviceSettings?.removeAll { $0["id"]?.string == id }
        if document.deviceSettings?.isEmpty == true { document.deviceSettings = nil }
    }

    private func commit(_ updated: ConfigDocument) -> String? {
        do {
            try store.save(updated)
            document = updated
            lastError = nil
            rebuildRows()
            onSaved()
            return nil
        } catch {
            let names = Dictionary(updated.rules.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            if let error = error as? ConfigStore.LoadError { return Messages.describe(error, ruleNames: names) }
            return error.localizedDescription
        }
    }
}
