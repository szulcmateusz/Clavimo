import ClavimoCore
import ClavimoQuartz
import Foundation

/// Command line modes that never touch input:
///   --check-config [path]   validate a configuration file
///   --list-devices          print connected keyboards and pointers
enum CommandLineTool {
    /// Returns an exit status when the arguments select a command line
    /// mode, or nil to launch the app normally.
    static func run(_ arguments: [String]) -> Int32? {
        if arguments.contains("--check-config") {
            return checkConfiguration(arguments)
        }
        if arguments.contains("--list-devices") {
            for device in HIDDeviceCatalog.connectedDevices() {
                let kinds = [device.isKeyboard ? "keyboard" : nil, device.isPointer ? "pointer" : nil].compactMap { $0 }
                print("\(device.id)\t\(device.name) [\(kinds.joined(separator: ", "))] \(device.transport ?? "")")
            }
            return 0
        }
        return nil
    }

    /// Exit status 0 means every enabled rule is active, 2 that some are
    /// unsupported, 1 that the file is invalid.
    private static func checkConfiguration(_ arguments: [String]) -> Int32 {
        var location = ConfigStore.defaultLocation()
        if let index = arguments.firstIndex(of: "--check-config"), index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
            location = URL(fileURLWithPath: arguments[index + 1])
            guard FileManager.default.fileExists(atPath: location.path) else {
                print("No such file: \(location.path)")
                return 1
            }
        }
        let store = ConfigStore(fileURL: location)
        print("Configuration: \(store.fileURL.path)")
        switch store.load() {
        case let .failure(error):
            print(error.description)
            return 1
        case let .success(loaded):
            let document = loaded.document
            let enabled = document.rules.filter { $0.enabled && $0.profileId == document.activeProfileId }
            let settings = (document.deviceSettings ?? []).filter {
                $0["enabled"] == .bool(true) && $0["profileId"]?.string == document.activeProfileId
            }
            print("Active profile: \(document.activeProfileId)")
            print("Enabled rules: \(enabled.count), device settings: \(settings.count), unsupported: \(loaded.unsupported.count)")
            for rule in enabled where !loaded.unsupported.contains(where: { $0.ruleID == rule.id }) {
                print("  ok    \(rule.name)")
            }
            for setting in settings where !loaded.unsupported.contains(where: { $0.ruleID == setting["id"]?.string }) {
                print("  ok    \(setting["name"]?.string ?? "device setting")")
            }
            for issue in loaded.unsupported {
                print("  skip  \(issue)")
            }
            print("Remapping on launch: \(document.engine.enabledOnLaunch ? "yes" : "no")")
            return loaded.unsupported.isEmpty ? 0 : 2
        }
    }
}
