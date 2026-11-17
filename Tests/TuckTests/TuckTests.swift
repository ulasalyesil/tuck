import ApplicationServices
import Testing
@testable import Tuck

// MARK: Menu mirroring

@Suite struct MenuMatching {
    let titles = ["Today", "9:15 · Busy", "", "Settings…", "Quit"]

    @Test func indexWinsWhileTitleStillMatches() {
        #expect(MenuMirror.match(.init(index: 3, title: "Settings…"), in: titles) == 3)
    }

    @Test func titleWinsWhenTheMenuShifted() {
        // A new event was added above: Settings… moved from 3 to 4.
        let shifted = ["Today", "8:00 · New", "9:15 · Busy", "", "Settings…", "Quit"]
        #expect(MenuMirror.match(.init(index: 3, title: "Settings…"), in: shifted) == 4)
    }

    @Test func goneEntryMatchesNothing() {
        #expect(MenuMirror.match(.init(index: 1, title: "10:00 · Gone"), in: titles) == nil)
    }
}

// MARK: Item naming and hiding

@Suite struct ItemNaming {
    @Test func helperTakesHostAppPath() {
        let helper = "/Applications/Perplexity.app/Contents/Library/LoginItems/perplexityd.app"
        #expect(MenuBarItems.hostAppPath(forBundlePath: helper) == "/Applications/Perplexity.app")
    }

    @Test func topLevelAppHasNoHost() {
        #expect(MenuBarItems.hostAppPath(forBundlePath: "/Applications/Shottr.app") == nil)
    }

    @Test func labelPrefersHostThenAXNameThenFriendlyName() {
        #expect(MenuBarItems.label(hostName: "Passwords", axName: "Apple Passwords Key", processName: "x") == "Passwords")
        #expect(MenuBarItems.label(hostName: nil, axName: "Gemini status menu", processName: "GeminiAppLauncher") == "Gemini status menu")
        #expect(MenuBarItems.label(hostName: nil, axName: nil, processName: "TextInputMenuAgent") == "Input Sources")
        #expect(MenuBarItems.label(hostName: nil, axName: nil, processName: "Shottr") == "Shottr")
    }

    @Test func hiddenMeansOverflowedOrLeftOfDivider() {
        let edge: CGFloat = 1321
        #expect(MenuBarItems.isHidden(CGRect(x: -1, y: 1157, width: 34, height: 24), dividerMaxX: edge))  // notch overflow
        #expect(MenuBarItems.isHidden(CGRect(x: 1290, y: 7.5, width: 39, height: 24), dividerMaxX: edge)) // tucked
        #expect(!MenuBarItems.isHidden(CGRect(x: 1335, y: 7.5, width: 34, height: 24), dividerMaxX: edge)) // visible
    }
}

// MARK: Divider sizing

@Suite struct DividerSizing {
    @Test func fillsFreeSpaceRightOfTheNotch() {
        // Notch ends at 1010, divider's right edge at 1321: 1321 - 1018 - 4.
        #expect(MenuBarDivider.fitLength(rightEdge: 1321, leftLimit: 1010) == 299)
    }

    @Test func neverCollapsesToZero() {
        #expect(MenuBarDivider.fitLength(rightEdge: 1000, leftLimit: 1010) == 1)
    }

    @Test func overflowedDividerIsOffTheBar() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        #expect(MenuBarDivider.isOnBar(CGRect(x: 1013, y: 1137, width: 308, height: 24), screen: screen))
        #expect(!MenuBarDivider.isOnBar(CGRect(x: 7, y: -31, width: 5002, height: 24), screen: screen))
    }
}

// MARK: Panel keyboard model

@Suite struct PanelNavigation {
    private func entry(_ id: Int, _ title: String, enabled: Bool = true, separator: Bool = false,
                       submenu: [MenuEntry]? = nil) -> MenuEntry {
        MenuEntry(id: id, title: title, enabled: enabled, isSeparator: separator, mark: "", submenu: submenu)
    }

    private let dummy = MenuBarItem(id: "1-0", element: AXUIElementCreateApplication(1), pid: 1,
                                    label: "Notion Calendar", icon: nil, frame: .zero)

    private func calendarModel() -> PanelModel {
        let model = PanelModel()
        model.showMenu([
            entry(0, "Tomorrow", enabled: false),
            entry(1, "9:15 · Busy", submenu: [entry(0, "Join"), entry(1, "Open Event")]),
            entry(2, "", enabled: false, separator: true),
            entry(3, "Settings…"),
            entry(4, "Quit"),
        ], of: dummy)
        return model
    }

    @Test func opensOnFirstSelectableRow() {
        #expect(calendarModel().selection == 1)
    }

    @Test func arrowsSkipLabelsAndSeparatorsAndStopAtEnds() {
        let model = calendarModel()
        model.move(1); #expect(model.selection == 3)
        model.move(1); #expect(model.selection == 4)
        model.move(1); #expect(model.selection == 4)
        model.move(-1); model.move(-1); model.move(-1)
        #expect(model.selection == 1)
    }

    @Test func typeToSelect() {
        let model = calendarModel()
        model.jump(to: "q"); #expect(model.selection == 4)
        model.jump(to: "S"); #expect(model.selection == 3)
    }

    @Test func returnDescendsIntoSubmenuAndPicksWithFullPath() {
        let model = calendarModel()
        var picked: [MenuMirror.Step] = []
        model.pickEntry = { _, path in picked = path }
        model.activate(1)
        #expect(model.stack.count == 2 && model.selection == 0)
        model.move(1)
        model.activate(model.selection)
        #expect(picked == [.init(index: 1, title: "9:15 · Busy"), .init(index: 1, title: "Open Event")])
    }

    @Test func rightArrowOnlyOpensSubmenus() {
        let model = calendarModel()
        var picked = false
        model.pickEntry = { _, _ in picked = true }
        model.selection = 3
        model.activateIfDeeper(3)
        #expect(!picked && model.stack.count == 1)
        model.activateIfDeeper(1)
        #expect(model.stack.count == 2)
    }

    @Test func escapeBacksOutBeforeClosing() {
        let model = calendarModel()
        #expect(model.back())
        #expect(!model.back())
    }
}
