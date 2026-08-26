import AppKit

// A menu bar carrying, on purpose, every combination the question is about.
//
// This process exists so the *platform* question can be asked without building the whole app:
// **does an `NSMenuItemBadge` reach the accessibility plane at all?** The real app's menu is built
// by SwiftUI and annotated by `ShellMenuReasons`, so a negative there has two possible causes —
// AppKit does not expose badges, or the walker never ran. Here there is no walker and no SwiftUI:
// the badges are set directly, three lines above the run loop, so a negative can only be AppKit's.
//
// Every item carries an accessibility help string as well, and two of them carry a key equivalent.
// Those are the controls. A probe that reads the help back and the chord back, and still finds no
// badge, has measured an absence; a probe that finds none of the three has measured a broken
// instrument and says nothing about badges.
//
// It never activates. `setActivationPolicy(.regular)` places the process in the menu bar's world
// without bringing it forward, and nothing here calls `activate`. The driver asserts the frontmost
// application is unchanged across the whole run, because `planning/practices/UI_VERIFICATION.md`
// rule 1 binds a fixture exactly as hard as it binds the app.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

func item(_ title: String, badge: String?, chord: String?, enabled: Bool = true) -> NSMenuItem {
    let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: chord ?? "")
    if chord != nil { menuItem.keyEquivalentModifierMask = [.command] }
    // The help string is the control: it is the one annotation already measured as readable over AX
    // on the real app's menu items, so reading it back here proves the probe is looking at the item
    // it thinks it is.
    menuItem.setAccessibilityHelp("help for \(title)")
    if let badge { menuItem.badge = NSMenuItemBadge(string: badge) }
    // Enablement is a parameter because the real app's badged items are **disabled** — the badge is
    // how a dimmed command explains itself — and a disabled element is a different accessibility
    // subject than an enabled one. Measuring only the enabled case would answer a question the app
    // does not ask.
    menuItem.isEnabled = enabled
    return menuItem
}

let mainMenu = NSMenu()

// macOS treats the first menu as the application menu whatever it is called, so the fixture's own
// items go in a second menu where they are not competing with anything the system contributes.
let appMenuItem = NSMenuItem()
let appMenu = NSMenu(title: "Fixture")
appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

let subjectItem = NSMenuItem()
let subject = NSMenu(title: "Subject")
subject.autoenablesItems = false
subject.addItem(item("Badge Only", badge: "BADGEONLY", chord: nil))
subject.addItem(item("Chord Only", badge: nil, chord: "1"))
subject.addItem(item("Both", badge: "BADGEBOTH", chord: "2"))
subject.addItem(item("Neither", badge: nil, chord: nil))
// The real app's shape: dimmed, carrying the reason as a badge, and — for six commands — a chord
// as well. If AppKit stops folding the badge into the title when the item is disabled, this is
// the row that says so while the four above still read correctly.
subject.addItem(item("Disabled Badge", badge: "BADGEDISABLED", chord: nil, enabled: false))
subject.addItem(item("Disabled Both", badge: "BADGEDISABOTH", chord: "3", enabled: false))
subjectItem.submenu = subject
mainMenu.addItem(subjectItem)

app.mainMenu = mainMenu

// The pid on stdout is the driver's handle. Flushed, because the driver reads one line and then
// waits on it — a buffered pid is a hang.
print(ProcessInfo.processInfo.processIdentifier)
fflush(stdout)

app.run()
