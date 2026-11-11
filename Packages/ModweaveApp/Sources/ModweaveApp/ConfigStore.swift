import Foundation
import ModweaveCore

/// Loads the per-account configuration from Application Support. The file
/// is only read here; a missing file is created as an empty, disabled
/// configuration so nothing is remapped without the user's choice.
struct ConfigStore {
    struct Loaded {
        var document: ConfigDocument
        var rules: CompiledRules
        var unsupported: [ConfigIssue]
    }

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case invalid(String)
        case rejected([RuleValidationError])

        var description: String {
            switch self {
            case let .unreadable(message): "Cannot read configuration: \(message)"
            case let .invalid(message): "Invalid configuration: \(message)"
            case let .rejected(errors): "Conflicting rules: \(errors.map { "\($0)" }.joined(separator: ", "))"
            }
        }
    }

    let fileURL: URL

    static func defaultLocation() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Modweave", isDirectory: true).appendingPathComponent("config.json")
    }

    func load() -> Result<Loaded, LoadError> {
        let data: Data
        do {
            try createDefaultIfMissing()
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        let document: ConfigDocument
        let interpreted: InterpretedConfig
        do {
            document = try ConfigDocument.decode(data)
            interpreted = try document.interpret()
        } catch let error as DecodingError {
            return .failure(.invalid(Self.describe(error)))
        } catch {
            return .failure(.invalid("\(error)"))
        }
        switch CompiledRules.compile(interpreted.definitions) {
        case let .success(rules):
            return .success(Loaded(document: document, rules: rules, unsupported: interpreted.unsupported))
        case let .failure(failure):
            return .failure(.rejected(failure.errors))
        }
    }

    private func createDefaultIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let empty = """
        {
          "schemaVersion": 1,
          "configId": "\(UUID().uuidString.lowercased())",
          "engine": {"enabledOnLaunch": false, "failOpen": true},
          "activeProfileId": "default",
          "profiles": [{"id": "default", "name": "Default", "inherits": null}],
          "rules": [],
          "macros": []
        }

        """
        try Data(empty.utf8).write(to: fileURL, options: .atomic)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            "missing \"\(key.stringValue)\" at \(path(context))"
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            "wrong value at \(path(context))"
        case let .dataCorrupted(context):
            context.debugDescription
        @unknown default:
            "\(error)"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }
        return components.isEmpty ? "top level" : components.joined()
    }
}
