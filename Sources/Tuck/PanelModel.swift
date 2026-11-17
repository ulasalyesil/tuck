import SwiftUI

/// What the panel shows and which row is selected. Mouse hover and the keyboard
/// share one selection, so both feel like a native menu.
final class PanelModel: ObservableObject {
    struct Level {
        let item: MenuBarItem
        let title: String
        let entries: [MenuEntry]
        let path: [MenuMirror.Step]
    }

    struct Row: Identifiable {
        enum Kind {
            case item(MenuBarItem)
            case entry(MenuEntry)
            case label(String)
            case separator
        }
        let id: String
        let kind: Kind

        var isSelectable: Bool {
            switch kind {
            case .item, .entry: true
            case .label, .separator: false
            }
        }

        var title: String {
            switch kind {
            case .item(let item): item.label
            case .entry(let entry): entry.title
            case .label(let text): text
            case .separator: ""
            }
        }
    }

    enum Direction { case forward, back }

    @Published var items: [MenuBarItem] = [] { didSet { selection = nil } }
    @Published private(set) var stack: [Level] = []
    @Published var selection: Int?
    @Published var loadingID: String?
    @Published var isPresented = false
    private(set) var direction: Direction = .forward

    /// Whether the last change came from the pointer. The window resize and the
    /// level fade follow it; keyboard changes stay instant.
    private(set) var changesAreAnimated = false

    func perform(animated: Bool, _ change: () -> Void) {
        changesAreAnimated = animated
        if animated { withAnimation(Motion.swap, change) } else { change() }
    }

    var openItem: (MenuBarItem) -> Void = { _ in }
    var pickEntry: (MenuBarItem, [MenuMirror.Step]) -> Void = { _, _ in }
    var arrange: () -> Void = {}
    var close: () -> Void = {}

    var rows: [Row] {
        guard let level = stack.last else {
            return items.map { Row(id: $0.id, kind: .item($0)) }
        }
        return level.entries.map { entry in
            let kind: Row.Kind = entry.isSeparator ? .separator
                : entry.enabled ? .entry(entry) : .label(entry.title)
            return Row(id: "entry-\(entry.id)", kind: kind)
        }
    }

    // MARK: Navigation

    func showMenu(_ entries: [MenuEntry], of item: MenuBarItem) {
        direction = .forward
        stack = [Level(item: item, title: item.label, entries: entries, path: [])]
        selection = firstSelectable
    }

    /// Back out of a mirrored menu. False when already at the item list.
    @discardableResult
    func back() -> Bool {
        guard !stack.isEmpty else { return false }
        direction = .back
        stack.removeLast()
        selection = nil
        return true
    }

    func reset() {
        stack = []
        selection = nil
        loadingID = nil
        changesAreAnimated = false
    }

    /// Next selectable row in `delta`'s direction, stopping at the ends like NSMenu.
    func move(_ delta: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        guard let current = selection else {
            selection = delta > 0 ? firstSelectable : rows.indices.last { rows[$0].isSelectable }
            return
        }
        var i = current + delta
        while rows.indices.contains(i) {
            if rows[i].isSelectable { selection = i; return }
            i += delta
        }
    }

    /// Type-to-select: the next selectable row whose title starts with `prefix`.
    func jump(to prefix: String) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let start = (selection ?? -1) + 1
        let order = Array(rows.indices[start...]) + Array(rows.indices[..<min(start, rows.count)])
        if let hit = order.first(where: {
            rows[$0].isSelectable && rows[$0].title.lowercased().hasPrefix(prefix.lowercased())
        }) {
            selection = hit
        }
    }

    func activate(_ index: Int?) {
        let rows = rows
        guard let index, rows.indices.contains(index) else { return }
        switch rows[index].kind {
        case .item(let item):
            openItem(item)
        case .entry(let entry):
            guard let level = stack.last else { return }
            let path = level.path + [MenuMirror.Step(index: entry.id, title: entry.title)]
            if let sub = entry.submenu {
                direction = .forward
                stack.append(Level(item: level.item, title: entry.title, entries: sub, path: path))
                selection = firstSelectable
            } else {
                pickEntry(level.item, path)
            }
        case .label, .separator:
            break
        }
    }

    /// → opens a row only when it leads somewhere deeper, like a submenu arrow.
    func activateIfDeeper(_ index: Int?) {
        guard let index, rows.indices.contains(index) else { return }
        switch rows[index].kind {
        case .item: activate(index)
        case .entry(let entry) where entry.submenu != nil: activate(index)
        default: break
        }
    }

    private var firstSelectable: Int? { rows.firstIndex { $0.isSelectable } }
}
