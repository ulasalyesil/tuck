import AppKit

// Tuck: a menu bar divider. Items left of it are tucked into a panel under ⋯.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
