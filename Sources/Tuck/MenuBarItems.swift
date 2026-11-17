import AppKit
import ApplicationServices

/// One menu bar extra owned by another app, read through Accessibility.
struct MenuBarItem: Identifiable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let label: String
    let icon: NSImage?
    let frame: CGRect // AX coordinates: origin top-left of the main screen

    /// Overflowed items report a y near the bottom of the screen.
    var isOnScreen: Bool { frame.minY < MenuBarItems.overflowY && frame.maxX > 0 }

    /// Blocks while the opened menu tracks: call off the main thread.
    func press() {
        AXUIElementSetMessagingTimeout(element, 0.25)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

/// Scanning every app over Accessibility takes from milliseconds to seconds, so it
/// runs in the background and the panel opens from the last result.
final class MenuBarItemStore {
    private(set) var items: [MenuBarItem] = []
    private let queue = DispatchQueue(label: "com.ulasalyesil.tuck.scan", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give a launching app a moment to put its item up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refresh() }
            })
        }
    }

    func refresh(then done: (([MenuBarItem]) -> Void)? = nil) {
        guard MenuBarItems.isTrusted else { return }
        queue.async { [weak self] in
            let fresh = MenuBarItems.all()
            DispatchQueue.main.async {
                self?.items = fresh
                done?(fresh)
            }
        }
    }
}

enum MenuBarItems {
    static let overflowY: CGFloat = 100

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Items Tuck should list: left of the divider or overflowed off screen.
    static func hidden(in items: [MenuBarItem], dividerMaxX: CGFloat) -> [MenuBarItem] {
        items
            .filter { isHidden($0.frame, dividerMaxX: dividerMaxX) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func isHidden(_ frame: CGRect, dividerMaxX: CGFloat) -> Bool {
        frame.minY >= overflowY || frame.maxX <= 0 || frame.midX < dividerMaxX
    }

    /// Every other app's menu extra with a real size.
    static func all() -> [MenuBarItem] {
        let me = ProcessInfo.processInfo.processIdentifier
        var items: [MenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != me {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            // One hung app must not stall the scan (default timeout is seconds).
            AXUIElementSetMessagingTimeout(axApp, 0.15)
            guard let bar: AXUIElement = attr(axApp, "AXExtrasMenuBar"),
                  let kids: [AXUIElement] = attr(bar, kAXChildrenAttribute) else { continue }
            let hostPath = app.bundleURL.flatMap { hostAppPath(forBundlePath: $0.path) }
            let hostName = hostPath.map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") }
            let icon = hostPath.map { NSWorkspace.shared.icon(forFile: $0) } ?? app.icon
            for (i, el) in kids.enumerated() {
                let frame = frameOf(el)
                guard frame.width > 0, frame.height > 0 else { continue }
                let desc: String = attr(el, kAXDescriptionAttribute) ?? ""
                let title: String = attr(el, kAXTitleAttribute) ?? ""
                items.append(MenuBarItem(
                    id: "\(app.processIdentifier)-\(i)",
                    element: el,
                    pid: app.processIdentifier,
                    label: label(hostName: hostName, axName: [desc, title].first { !$0.isEmpty },
                                 processName: app.localizedName ?? "Unknown"),
                    icon: icon,
                    frame: frame))
            }
        }
        return items
    }

    // MARK: Naming

    private static let friendly = ["TextInputMenuAgent": "Input Sources"]

    /// Helper processes (perplexityd, PasswordsMenuBarExtra) take their host app's
    /// name, else the item's own AX name, else a friendly name for system agents.
    static func label(hostName: String?, axName: String?, processName: String) -> String {
        hostName ?? axName ?? friendly[processName] ?? processName
    }

    /// The outermost .app around a nested helper: Perplexity.app/…/perplexityd.app → Perplexity.app.
    static func hostAppPath(forBundlePath path: String) -> String? {
        let parts = (path as NSString).pathComponents
        guard let i = parts.dropLast().firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(parts[...i]))
    }

    // MARK: AX

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func frameOf(_ el: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v: AXValue = attr(el, kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &p) }
        if let v: AXValue = attr(el, kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }
}
