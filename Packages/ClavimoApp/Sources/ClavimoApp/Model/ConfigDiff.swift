import ClavimoCore
import Foundation

/// What would change if one configuration replaced another, shown before
/// an import or a restore is applied.
struct ConfigDiff: Equatable {
    struct Entry: Equatable, Identifiable {
        let id: String
        let name: String
    }

    var added: [Entry] = []
    var changed: [Entry] = []
    var removed: [Entry] = []
    /// Enabled rules in the incoming configuration that cannot run.
    var unsupported: [ConfigIssue] = []
    var profilesAdded: [String] = []
    var profilesRemoved: [String] = []
    var activeProfileChange: (from: String, to: String)?

    var isEmpty: Bool {
        added.isEmpty && changed.isEmpty && removed.isEmpty && profilesAdded.isEmpty && profilesRemoved.isEmpty
            && activeProfileChange == nil
    }

    static func == (lhs: ConfigDiff, rhs: ConfigDiff) -> Bool {
        lhs.added == rhs.added && lhs.changed == rhs.changed && lhs.removed == rhs.removed
            && lhs.unsupported == rhs.unsupported && lhs.profilesAdded == rhs.profilesAdded
            && lhs.profilesRemoved == rhs.profilesRemoved
            && lhs.activeProfileChange?.from == rhs.activeProfileChange?.from
            && lhs.activeProfileChange?.to == rhs.activeProfileChange?.to
    }

    init(from current: ConfigDocument?, to incoming: ConfigDocument) {
        let before = Self.items(current)
        let after = Self.items(incoming)
        for (id, item) in after.sorted(by: { $0.value.order < $1.value.order }) {
            if let old = before[id] {
                if old.content != item.content { changed.append(Entry(id: id, name: item.name)) }
            } else {
                added.append(Entry(id: id, name: item.name))
            }
        }
        for (id, item) in before.sorted(by: { $0.value.order < $1.value.order }) where after[id] == nil {
            removed.append(Entry(id: id, name: item.name))
        }
        let oldProfiles = Set(current?.profiles.map(\.name) ?? [])
        let newProfiles = Set(incoming.profiles.map(\.name))
        profilesAdded = newProfiles.subtracting(oldProfiles).sorted()
        profilesRemoved = oldProfiles.subtracting(newProfiles).sorted()
        if let current, current.activeProfileId != incoming.activeProfileId {
            let name = { (doc: ConfigDocument, id: String) in doc.profiles.first { $0.id == id }?.name ?? id }
            activeProfileChange = (name(current, current.activeProfileId), name(incoming, incoming.activeProfileId))
        }
        unsupported = (try? incoming.interpret().unsupported) ?? []
    }

    private struct Item {
        let name: String
        let content: Data
        let order: Int
    }

    /// Rules and device settings keyed by ID, with their encoded content
    /// so any change is detected.
    private static func items(_ document: ConfigDocument?) -> [String: Item] {
        guard let document else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var result: [String: Item] = [:]
        for (order, rule) in document.rules.enumerated() {
            result[rule.id] = Item(name: rule.name, content: (try? encoder.encode(rule)) ?? Data(), order: order)
        }
        for (offset, setting) in (document.deviceSettings ?? []).enumerated() {
            guard let id = setting["id"]?.string else { continue }
            result[id] = Item(name: setting["name"]?.string ?? id, content: (try? encoder.encode(setting)) ?? Data(),
                              order: document.rules.count + offset)
        }
        return result
    }
}
