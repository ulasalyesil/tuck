import AppKit

/// The status item that does the hiding. Collapsed, it fills exactly the free
/// space between the notch (or screen edge) and its right edge, so macOS 27
/// overflows every item to its left. Arranging, it shrinks to a labelled line
/// so icons can be ⌘-dragged across it.
final class MenuBarDivider {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private(set) var isArranging = false
    private var watchdog: Timer?

    init() {
        item.autosaveName = "tuck.divider"
        // Free space changes as other items appear, resize or quit.
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.fit() }
    }

    /// Screen x where tucked territory ends.
    var maxX: CGFloat { item.button?.window?.frame.maxX ?? 0 }

    func collapse() {
        isArranging = false
        item.button?.image = nil
        item.button?.attributedTitle = NSAttributedString()
        fit(force: true)
    }

    func arrange() {
        isArranging = true
        item.length = NSStatusItem.variableLength
        item.button?.image = Self.lineImage
        item.button?.imagePosition = .imageRight
        item.button?.attributedTitle = NSAttributedString(string: "← tucked ", attributes: [
            .font: NSFont.menuBarFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func fit(force: Bool = false) {
        guard !isArranging, let win = item.button?.window,
              let screen = win.screen ?? NSScreen.main else { return }
        guard Self.isOnBar(win.frame, screen: screen.frame) else {
            // macOS overflowed the divider itself: shrink it back on, measure next tick.
            item.length = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.fit(force: true) }
            return
        }
        let leftLimit = screen.auxiliaryTopRightArea?.minX ?? screen.frame.minX
        let target = Self.fitLength(rightEdge: win.frame.maxX, leftLimit: leftLimit)
        if force || abs(item.length - target) > 2 { item.length = target }
    }

    /// 8 pt is the gap macOS leaves next to the notch; 4 pt of slack keeps a
    /// rounding error from overflowing the divider. No icon is narrower than that.
    static func fitLength(rightEdge: CGFloat, leftLimit: CGFloat) -> CGFloat {
        max(floor(rightEdge - (leftLimit + 8) - 4), 1)
    }

    static func isOnBar(_ frame: NSRect, screen: NSRect) -> Bool {
        frame.minY > screen.maxY - 60
    }

    private static let lineImage: NSImage = {
        let img = NSImage(size: NSSize(width: 2, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
