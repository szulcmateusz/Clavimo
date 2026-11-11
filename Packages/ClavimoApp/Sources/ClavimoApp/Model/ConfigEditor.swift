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
        /// Keyboard rules (tap-hold, layers, combos, sequences) edited in
        /// the Keyboard pane.
        var keyboard: KeyboardRuleDraft? = nil

        var isEditable: Bool { draft != nil || keyboard != nil }
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
            let draft = RuleDraft(rule: rule)
            return Row(id: rule.id, source: .rule, name: rule.name, enabled: rule.enabled, profileID: rule.profileId, draft: draft,
                       keyboard: draft == nil ? KeyboardRuleDraft(rule: rule) : nil)
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
        if draft.kind.isSetting {
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

    /// Inserts or replaces a keyboard rule.
    @discardableResult
    func upsertKeyboard(_ draft: KeyboardRuleDraft, id existingID: String?) -> String? {
        replaceKeyboardRules([(existingID ?? UUID().uuidString.lowercased(), draft)], removing: [])
    }

    /// Writes several keyboard rules and removes others in one save, so a
    /// set such as home row modifiers is never half applied.
    @discardableResult
    func replaceKeyboardRules(_ drafts: [(id: String, draft: KeyboardRuleDraft)], removing ids: Set<String>) -> String? {
        guard var updated = document else { return lastError ?? "Configuration is not loaded." }
        for (_, draft) in drafts {
            if let message = draft.validationMessage { return message }
        }
        for id in ids { remove(id: id, from: &updated) }
        for (id, draft) in drafts {
            let index = updated.rules.firstIndex { $0.id == id }
            let rule = draft.makeRule(id: id, order: index ?? updated.rules.count)
            if let index {
                updated.rules[index] = rule
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

    // MARK: Import, export and backups

    /// The current configuration as stable, human-readable JSON.
    func exportData() throws -> Data {
        guard let document else { throw ConfigStore.LoadError.unreadable(String(localized: "No configuration is loaded.")) }
        return try document.encoded()
    }

    struct ReadFailure: Error {
        let message: String
    }

    /// Reads a configuration for preview without applying it.
    func readDocument(at url: URL) -> Result<ConfigDocument, ReadFailure> {
        do {
            return .success(try ConfigDocument.decode(Data(contentsOf: url)))
        } catch let error as ConfigLoadError {
            return .failure(ReadFailure(message: Messages.describe(error)))
        } catch let error as DecodingError {
            return .failure(ReadFailure(message: Messages.describe(ConfigStore.LoadError.invalid(ConfigStore.describeDecoding(error)))))
        } catch {
            return .failure(ReadFailure(message: error.localizedDescription))
        }
    }

    /// Replaces the whole configuration after validation. The previous
    /// file becomes the backup.
    @discardableResult
    func replace(with incoming: ConfigDocument) -> String? {
        commit(incoming)
    }

    var backupDocument: ConfigDocument? {
        guard let data = try? Data(contentsOf: store.backupURL) else { return nil }
        return try? ConfigDocument.decode(data)
    }

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
