import AppKit
import ApplicationServices
import ClavimoCore

/// Reads and presses items in an app's menu bar through Accessibility,
/// the permission Clavimo already has. Menus are read only when an item is
/// pressed or listed for the editor; nothing is kept.
public enum MenuItems {
    /// One menu item, with its titles from the menu bar down.
    public struct Item: Hashable, Sendable {
        public let path: [String]
        public let isEnabled: Bool
        /// The item's own shortcut as macOS shows it, e.g. "⇧⌘N".
        public let shortcut: String?
    }

    /// Presses the item at `path` in the frontmost app. Titles are matched
    /// exactly first, then ignoring case and a trailing ellipsis. Returns
    /// false when the item is missing or disabled.
    @discardableResult
    public static func press(_ path: [String]) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return press(path, inApp: app.processIdentifier)
    }

    public static func press(_ path: [String], inApp pid: pid_t) -> Bool {
        guard let item = find(path, inApp: pid) else { return false }
        if bool(item, kAXEnabledAttribute) == false { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Every item in the app's menus, in menu order, without the Apple menu
    /// and separators. Stops after `limit` items for very large menus.
    public static func items(inApp pid: pid_t, limit: Int = 3000) -> [Item] {
        guard let bar = menuBar(of: pid) else { return [] }
        var result: [Item] = []
        // The first menu bar item is the Apple menu, the same in every app.
        for top in children(of: bar).dropFirst() {
            guard let title = string(top, kAXTitleAttribute), !title.isEmpty else { continue }
            collect(top, path: [title], into: &result, limit: limit)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Walking the menus

    private static func collect(_ element: AXUIElement, path: [String], into result: inout [Item], limit: Int) {
        for menu in children(of: element) {
            for item in children(of: menu) {
                guard result.count < limit else { return }
                guard let title = string(item, kAXTitleAttribute), !title.isEmpty else { continue }
                let itemPath = path + [title]
                let submenu = children(of: item)
                if submenu.isEmpty {
                    result.append(Item(path: itemPath, isEnabled: bool(item, kAXEnabledAttribute) ?? true,
                                       shortcut: shortcut(of: item)))
                } else {
                    collect(item, path: itemPath, into: &result, limit: limit)
                }
            }
        }
    }

    private static func find(_ path: [String], inApp pid: pid_t) -> AXUIElement? {
        guard !path.isEmpty, let bar = menuBar(of: pid) else { return nil }
        var current = bar
        for (index, title) in path.enumerated() {
            // Below a menu bar item or menu item sits one menu holding the
            // items; the menu bar holds its items directly.
            let candidates = index == 0 ? children(of: current) : children(of: current).flatMap(children(of:))
            guard let next = match(title, in: candidates) else { return nil }
            current = next
        }
        return current
    }

    static func normalized(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespaces).lowercased()
        for ellipsis in ["…", "..."] where result.hasSuffix(ellipsis) {
            result = String(result.dropLast(ellipsis.count)).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func match(_ title: String, in elements: [AXUIElement]) -> AXUIElement? {
        let titled = elements.map { ($0, string($0, kAXTitleAttribute) ?? "") }
        if let exact = titled.first(where: { $0.1 == title }) { return exact.0 }
        let wanted = normalized(title)
        return titled.first { normalized($0.1) == wanted }?.0
    }

    private static func menuBar(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    /// The shortcut text: modifiers (bit 0 Shift, 1 Option, 2 Control,
    /// 3 no Command) and the key character.
    private static func shortcut(of item: AXUIElement) -> String? {
        guard let character = string(item, kAXMenuItemCmdCharAttribute), !character.isEmpty else { return nil }
        let flags = int(item, kAXMenuItemCmdModifiersAttribute) ?? 0
        var text = ""
        if flags & 4 != 0 { text += "⌃" }
        if flags & 2 != 0 { text += "⌥" }
        if flags & 1 != 0 { text += "⇧" }
        if flags & 8 == 0 { text += "⌘" }
        return text + character.uppercased()
    }
}
