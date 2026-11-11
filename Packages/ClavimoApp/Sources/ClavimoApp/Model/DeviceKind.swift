import ClavimoQuartz

extension HIDDeviceInfo {
    /// Many mice also expose a keyboard interface for their macro keys, so
    /// HID usages alone do not tell a mouse from a keyboard. Built-in
    /// keyboard and trackpad combinations stay keyboards.
    var looksLikeMouse: Bool {
        guard isPointer else { return false }
        let lowered = name.lowercased()
        if lowered.contains("keyboard") || lowered.contains("keys") { return false }
        return lowered.contains("mouse") || !isKeyboard
    }
}
