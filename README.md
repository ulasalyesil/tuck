# —tuck

A divider for the macOS 27 menu bar. Icons left of it are tucked away and listed in a panel under the `⋯` icon. Small, open source, public APIs only.

[tuck.ulasalyesil.com](https://tuck.ulasalyesil.com)

## Use

- **Click `⋯`** or press **⌃⌥M**: panel of tucked items. Click one to open it.
- **Keyboard** in the panel: ↑↓ to move, type a letter to jump, ↩ or → to open, ← to go back, esc to back out or close. The panel takes the keyboard without pulling you out of the app you're in.
- **Right-click (or ⌥-click) `⋯`**: Arrange Items, Open at Login, Quit.
- **Arrange**: the divider shows as a `← tucked │` label. Hold ⌘ and drag an icon along the bar: left of the line to tuck it, right of it to keep it visible. Keep the drag on the bar; dropping an icon off the bar removes it. Click `✓` when done.

## Motion

Pointer actions animate, keyboard actions never do. The panel grows out of `⋯` (180 ms, scale 0.96 → 1, strong ease-out), leaves faster (120 ms), and glides between menu levels (200 ms resize, 8 pt slide from the direction of travel). ⌃⌥M, arrows, ↩ and esc are instant. Reduce Motion keeps the fades and drops scale and slide. Timings log under the `com.ulasalyesil.tuck` subsystem.

Needs Accessibility (System Settings → Privacy & Security → Accessibility → Tuck).

## Build

```bash
./build.sh            # → build/Tuck.app (ad-hoc signed)
open build/Tuck.app
swift test            # pure logic: menu matching, naming, divider sizing, panel keyboard model
```

| File | Role |
|---|---|
| `AppDelegate.swift` | Wires the icon, divider, panel and shortcut |
| `MenuBarDivider.swift` | The hiding status item and its sizing |
| `MenuBarItems.swift` | Reads other apps' menu extras through AX, names them |
| `MenuMirror.swift` | Copies an off-screen menu and presses entries in it |
| `PanelModel.swift` | Rows, selection and keyboard navigation (tested) |
| `TuckPanel.swift` | The panel window and its SwiftUI views |
| `Shortcut.swift` | Carbon global hot key, ⌃⌥M |

## How it works (macOS 27)

- Status item windows no longer show up in `CGWindowList`, so the Hidden Bar / Ice trick (a 10 000 pt divider) fails: macOS overflows the oversized divider itself.
- macOS 27 draws the whole bar as one window owned by `MenuBarAgent` and has its own overflow arrow (`«`). Tuck's divider is sized to exactly the free space between the notch and its right edge, which pushes everything left of it into Apple's overflow. A 2 s timer refits it as other items change width.
- The `«` is Apple's, not Tuck's. It appears whenever anything overflows (the notch alone triggers it) and reveals the overflow left of the notch. It is an `AXImage` with no actions, so Tuck can't hide or intercept it with public APIs.
- Clicks on Tuck's icon arrive as a bare left-up: no right-clicks, no modifier flags. Right-click is caught by a global monitor (the bar belongs to another process), Option/Control-click by reading live modifier state. The icon's view sits in a proxy window, so the menu pops up in screen coordinates.
- Items are read through Accessibility (`AXExtrasMenuBar` per app).
- **Behind the divider**: `AXPress` opens the item's own menu on screen. Nothing else needed.
- **Overflowed by the notch** (y ≈ screen height): pressing would open the menu below the screen. Tuck opens it off screen, copies the `AXMenu` tree into the panel, and cancels it. Picking an entry reopens the menu and presses that entry, matched by title.
- Popover-style items (Claude, Creative Cloud) have no `AXMenu`: Tuck activates the app instead.

## Limits

- Notch-overflowed popover items can't show their popover, only the app.
- Mirrored menus show titles, check marks and submenus. Custom view items (sliders) show as "(custom item)".
- Labels use app icons, not the real menu bar glyph (that would need Screen Recording).
