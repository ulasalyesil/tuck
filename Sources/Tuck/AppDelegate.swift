import AppKit
import Combine
import ServiceManagement

/// Wires the ⋯ icon, the divider, the panel and the shortcut together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created before the divider so a first launch puts ⋯ to the divider's right.
    private let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let divider = MenuBarDivider()
    private let panel = TuckPanel()
    private let store = MenuBarItemStore()
    private var shortcut: Shortcut?
    private var outsideClickMonitor: Any?
    private var rightClickMonitor: Any?
    private var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ note: Notification) {
        toggle.autosaveName = "tuck.toggle"
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleClicked)
        setToggleIcon("ellipsis")

        let model = panel.model
        model.openItem = { [weak self] in self?.open($0) }
        model.pickEntry = { [weak self] in self?.pick($0, path: $1) }
        model.arrange = { [weak self] in self?.startArranging() }
        model.close = { [weak self] in self?.closePanel(animated: false) }
        model.objectWillChange
            .sink { [weak self] in
                // Read now: the flag describes the change that is about to happen.
                let animated = model.changesAreAnimated
                DispatchQueue.main.async { self?.panel.relayout(animated: animated) }
            }
            .store(in: &bag)

        // Right-clicks never reach the button on macOS 27, but MenuBarAgent owns
        // the bar, so they arrive here as global events.
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] _ in
            guard let self, self.isOverToggle(NSEvent.mouseLocation) else { return }
            self.showMenu()
        }
        shortcut = Shortcut { [weak self] in self?.togglePanel(fromKeyboard: true) }

        divider.collapse()
        if !MenuBarItems.isTrusted { MenuBarItems.promptForTrust() }
        store.refresh()
    }

    // MARK: Icon

    @objc private func toggleClicked() {
        // Clicks arrive as a bare left-up: no right button, no modifier flags.
        // Read the live keyboard state for ⌥/⌃-click.
        if !NSEvent.modifierFlags.intersection([.control, .option]).isEmpty { return showMenu() }
        if divider.isArranging { return stopArranging() }
        togglePanel(fromKeyboard: false)
    }

    private func isOverToggle(_ point: NSPoint) -> Bool {
        toggle.button?.window?.frame.contains(point) ?? false
    }

    private func setToggleIcon(_ symbol: String) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tuck")
        img?.isTemplate = true
        toggle.button?.image = img
    }

    // MARK: Arranging

    private func startArranging() {
        closePanel(animated: panel.model.changesAreAnimated)
        divider.arrange()
        setToggleIcon("checkmark")
    }

    private func stopArranging() {
        divider.collapse()
        setToggleIcon("ellipsis")
        // Items just moved across the divider.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.store.refresh() }
    }

    // MARK: Panel

    private func togglePanel(fromKeyboard: Bool) {
        if panel.isVisible { return closePanel(animated: !fromKeyboard) }
        if divider.isArranging { stopArranging() }
        guard MenuBarItems.isTrusted else { return MenuBarItems.promptForTrust() }
        guard let anchor = toggle.button?.window?.frame else { return }
        // Open from the last scan at once, then correct it from a fresh one.
        panel.show(items: MenuBarItems.hidden(in: store.items, dividerMaxX: divider.maxX), under: anchor,
                   animated: !fromKeyboard)
        store.refresh { [weak self] fresh in
            guard let self else { return }
            self.panel.update(items: MenuBarItems.hidden(in: fresh, dividerMaxX: self.divider.maxX))
        }
        // A click on ⋯ itself also lands here first; toggleClicked handles that one.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isOverToggle(NSEvent.mouseLocation) else { return }
            self.closePanel(animated: true)
        }
    }

    private func closePanel(animated: Bool) {
        panel.dismiss(animated: animated)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }

    /// Items behind the divider still open their own menu on screen: press them.
    /// Items overflowed by the notch would open below the screen: mirror their
    /// menu in the panel, or open the app when there is no menu (popovers).
    private func open(_ item: MenuBarItem) {
        let animated = panel.model.changesAreAnimated
        if item.isOnScreen {
            closePanel(animated: animated)
            DispatchQueue.global(qos: .userInitiated).async { item.press() }
            return
        }
        panel.model.loadingID = item.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = MenuMirror.snapshot(item)
            DispatchQueue.main.async {
                guard let self else { return }
                let model = self.panel.model
                model.loadingID = nil
                if let entries {
                    model.perform(animated: animated) { model.showMenu(entries, of: item) }
                    self.panel.makeKey() // the off-screen menu borrowed the keyboard
                } else {
                    self.closePanel(animated: animated)
                    NSRunningApplication(processIdentifier: item.pid)?.activate()
                }
            }
        }
    }

    private func pick(_ item: MenuBarItem, path: [MenuMirror.Step]) {
        closePanel(animated: panel.model.changesAreAnimated)
        DispatchQueue.global(qos: .userInitiated).async { MenuMirror.pick(item, path: path) }
    }

    // MARK: Menu

    private func showMenu() {
        closePanel(animated: false)
        let menu = NSMenu()
        menu.addItem(withTitle: divider.isArranging ? "Done Arranging" : "Arrange Items…",
                     action: #selector(arrangeClicked), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(loginClicked), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let hint = menu.addItem(withTitle: shortcut == nil ? "Shortcut \(Shortcut.display) is taken"
                                    : "Open with \(Shortcut.display)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // The button sits in a proxy window on macOS 27; popping up "in" it shows
        // nothing. Use screen coordinates under the icon.
        guard let icon = toggle.button?.window?.frame else { return }
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: NSPoint(x: icon.minX, y: icon.minY - 4), in: nil)
        }
    }

    @objc private func arrangeClicked() {
        divider.isArranging ? stopArranging() : startArranging()
    }

    @objc private func loginClicked() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }
}
