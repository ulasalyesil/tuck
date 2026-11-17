import ApplicationServices
import Foundation

/// A read-only copy of one entry in another app's status item menu.
struct MenuEntry: Identifiable {
    let id: Int // index in its parent menu
    let title: String
    let enabled: Bool
    let isSeparator: Bool
    let mark: String
    let submenu: [MenuEntry]?
}

/// Opens a hidden item's menu off screen, copies it, and closes it again.
/// Picking an entry reopens the menu and presses that entry through Accessibility.
/// All calls block for a few hundred ms: run them off the main thread.
enum MenuMirror {
    /// One level of the way down to a menu entry.
    struct Step: Equatable {
        let index: Int
        let title: String
    }

    static func snapshot(_ item: MenuBarItem) -> [MenuEntry]? {
        guard let menu = open(item) else { return nil }
        let entries = read(menu)
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        return entries.isEmpty ? nil : entries
    }

    static func pick(_ item: MenuBarItem, path: [Step]) {
        guard var current = open(item) else { return }
        for (depth, step) in path.enumerated() {
            let kids = children(current)
            guard let found = match(step, in: kids.map { string($0, kAXTitleAttribute) }) else { break }
            let entry = kids[found]
            if depth == path.count - 1 {
                AXUIElementSetMessagingTimeout(entry, 0.25)
                AXUIElementPerformAction(entry, kAXPressAction as CFString)
                return
            }
            guard let sub = children(entry).first else { break }
            current = sub
        }
        AXUIElementPerformAction(current, kAXCancelAction as CFString)
    }

    /// Menus change between snapshot and pick (a calendar adds an event), so the
    /// index is trusted only while its title still matches; otherwise search by title.
    static func match(_ step: Step, in titles: [String]) -> Int? {
        if titles.indices.contains(step.index), titles[step.index] == step.title { return step.index }
        return titles.firstIndex(of: step.title)
    }

    /// Presses the status item and waits for its AXMenu. nil when the item opens a popover or window.
    private static func open(_ item: MenuBarItem) -> AXUIElement? {
        // AXPress blocks while the menu tracks; the timeout lets us carry on.
        AXUIElementSetMessagingTimeout(item.element, 0.25)
        AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        for _ in 0..<10 {
            if let menu = children(item.element).first(where: { role($0) == kAXMenuRole }) { return menu }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private static func read(_ menu: AXUIElement) -> [MenuEntry] {
        children(menu).enumerated().compactMap { index, el in
            guard role(el) == kAXMenuItemRole else { return nil }
            let title = string(el, kAXTitleAttribute)
            let enabled = (value(el, kAXEnabledAttribute) as? Bool) ?? false
            let sub = children(el).first { role($0) == kAXMenuRole }
            return MenuEntry(
                id: index,
                title: title,
                enabled: enabled,
                isSeparator: title.isEmpty && !enabled && sub == nil,
                mark: string(el, "AXMenuItemMarkChar"),
                submenu: sub.map(read))
        }
    }

    private static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, name as CFString, &v)
        return v
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String {
        (value(el, name) as? String) ?? ""
    }

    private static func role(_ el: AXUIElement) -> String { string(el, kAXRoleAttribute) }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        (value(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
