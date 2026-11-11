import ClavimoCore
import Foundation

/// Turns engine and configuration errors into short, localized sentences
/// that name keys and buttons the way the UI does. No enum case names or
/// raw key codes ever reach the user.
enum Messages {
    static func describe(_ issue: ConfigIssue) -> String {
        String(localized: "\(issue.ruleName): \(describe(issue.reason))")
    }

    static func describe(_ reason: UnsupportedReason) -> String {
        switch reason {
        case .invalidRule:
            String(localized: "The rule is incomplete. Edit or delete it.")
        case let .invalidCondition(kind):
            String(localized: "The \(kind) condition has no value.")
        case let .unsupportedCondition(kind):
            String(localized: "The condition \(kind) is not supported.")
        case let .unsupportedCombination(trigger, action):
            String(localized: "Combining \(trigger) with \(action) is not supported yet.")
        case .bothSidesSwap:
            String(localized: "Swapping both sides at once is not supported. Add one rule for each side.")
        case .modifierKeyChord:
            String(localized: "Modifier + key shortcuts are not supported yet; use a mouse button.")
        case .chordOrder:
            String(localized: "The key must be held before the mouse button is pressed.")
        case .invalidMouseButton:
            String(localized: "The mouse button number is not valid.")
        case .missingLeaderPolicy:
            String(localized: "Choose how the key behaves while Clavimo waits for the click.")
        case .chordBehavior:
            String(localized: "Mouse shortcuts must run once when pressed.")
        case .keyNamespace:
            String(localized: "The key uses a code format Clavimo does not read yet.")
        case .sideSpecificChordModifiers:
            String(localized: "Mouse shortcuts cannot require a specific left or right modifier yet.")
        case let .unsupportedAction(kind):
            String(localized: "The action \(kind) is not supported yet.")
        case .trackpadSettings:
            String(localized: "Trackpad settings are not changed by Clavimo.")
        case .pointerSettings:
            String(localized: "Pointer speed and acceleration are set in System Settings > Mouse.")
        case .noScrollChange:
            String(localized: "The scroll setting changes nothing.")
        case .perDeviceScrolling:
            String(localized: "Scroll settings cannot be limited to one mouse yet.")
        case .displayScope:
            String(localized: "Settings per display are not supported.")
        case let .unsupportedScrollField(field):
            String(localized: "The scroll option \(field) is not supported yet.")
        case let .unsupportedScrollMode(mode):
            String(localized: "The scroll mode \(mode) is not supported yet.")
        case .scrollValueOutOfRange:
            String(localized: "The scroll distance or speed is outside the allowed range.")
        }
    }

    /// Explains why a set of rules cannot be saved, naming the rules
    /// involved where possible.
    static func describe(_ error: RuleValidationError, ruleNames: [String: String] = [:]) -> String {
        func key(_ code: KeyCode) -> String { KeyNames.name(for: code.rawValue) }
        func rule(_ id: String) -> String { ruleNames[id] ?? id }
        switch error {
        case let .duplicateRemapSource(code):
            return String(localized: "\(key(code)) is already used by another rule with the same conditions.")
        case let .swapWithItself(code), let .remapToItself(code):
            return String(localized: "\(key(code)) cannot be mapped to itself.")
        case let .leaderWindowOutOfRange(code, ms):
            return String(localized: "The waiting time for \(key(code)) (\(ms) ms) must be between 50 and 500 ms.")
        case let .leaderIsModifierKey(code):
            return String(localized: "\(key(code)) is a modifier. Use a modifier + mouse button rule instead.")
        case let .leaderAlsoRemapped(code):
            return String(localized: "\(key(code)) is both remapped and used in a mouse shortcut. Keep only one.")
        case let .conflictingLeaderPolicies(code):
            return String(localized: "Mouse shortcuts with \(key(code)) use different waiting behaviors. Use the same one.")
        case let .emptyModifierLeader(id):
            return String(localized: "\(rule(id)) needs at least one modifier.")
        case let .protectedMouseButton(button, id):
            return String(localized: "\(rule(id)) uses the \(KeyNames.buttonName(button.userFacingNumber)) without allowing it.")
        case let .protectedMouseButtonNeedsModifierLeader(button, id):
            return String(localized: "\(rule(id)): the \(KeyNames.buttonName(button.userFacingNumber)) can only be combined with modifiers.")
        case let .duplicateChord(button, ids):
            let names = ids.map(rule).joined(separator: ", ")
            return String(localized: "\(names) use the same shortcut with the \(KeyNames.buttonName(button.userFacingNumber)).")
        case let .duplicateRuleID(id):
            return String(localized: "Two rules share the ID \(id).")
        case let .deviceConditionOnLetterLeader(id):
            return String(localized: "\(rule(id)): key + mouse button shortcuts cannot be limited to a device.")
        case let .unsupportedKey(code):
            return String(localized: "\(key(code)) cannot be remapped yet.")
        case .duplicateWheelRule:
            return String(localized: "Two mouse wheel settings apply in the same situation. Keep one.")
        case .wheelRuleWithoutChanges:
            return String(localized: "The mouse wheel setting changes nothing.")
        }
    }

    static func describe(_ error: ConfigLoadError) -> String {
        switch error {
        case let .unsupportedSchemaVersion(version):
            String(localized: "The configuration was made by a newer version of Clavimo (format \(version)). Update Clavimo to use it.")
        case let .unknownActiveProfile(id):
            String(localized: "The active profile \(id) does not exist.")
        case let .unknownParentProfile(id):
            String(localized: "A profile inherits from \(id), which does not exist.")
        case let .profileCycle(id):
            String(localized: "The profile \(id) inherits from itself through other profiles.")
        }
    }

    static func describe(_ error: ConfigStore.LoadError, ruleNames: [String: String] = [:]) -> String {
        switch error {
        case let .unreadable(message):
            String(localized: "The configuration file cannot be read: \(message)")
        case let .invalid(message):
            String(localized: "The configuration file is not valid: \(message)")
        case let .rejected(errors):
            errors.map { describe($0, ruleNames: ruleNames) }.joined(separator: "\n")
        case let .profile(error):
            describe(error)
        }
    }
}
