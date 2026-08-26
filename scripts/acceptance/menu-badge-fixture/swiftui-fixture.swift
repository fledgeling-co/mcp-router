import AppKit
import SwiftUI

// The same question as `fixture.swift`, asked of a menu **SwiftUI** built.
//
// `fixture.swift` proves AppKit folds a badge into `AXTitle`, at construction time and post-hoc,
// enabled and disabled. The real app shows no badge at all on items whose help tag is correct — so
// exactly one difference between the two remains, and it is this: the app's menu items are built by
// SwiftUI's `CommandGroup`, and this one's are too.
//
// A `Settings` scene rather than a `WindowGroup`, on purpose. A settings-only app is `.regular` —
// it owns a menu bar, which is the whole subject — and opens **no window at launch**, so this
// fixture cannot take the user's screen even by accident.
//
// The walker below is `ShellMenuReasons.apply` reduced to its one line under test: match by title,
// assign a badge, re-apply on a poll because SwiftUI rebuilds its items.

@main
struct SwiftUIBadgeFixture: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate

    var body: some Scene {
        Settings { Text("no window at launch") }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("SwiftUI Badged") {}.disabled(true)
                    Button("SwiftUI Badged Chord") {}.disabled(true).keyboardShortcut("j")
                    // No walker touches this one. It settles who writes `AXHelp` on the real app's
                    // menu items: `ShellMenuReasons`, or SwiftUI's own `.help()`. The answer decides
                    // whether the app's correct help tags are evidence that the walker reaches the
                    // real menu at all — and so whether its badge line reaches it too.
                    Button("SwiftUI Help Only") {}.disabled(true).help("swiftui help string")
                }
            }
    }

    final class Delegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_: Notification) {
            print(ProcessInfo.processInfo.processIdentifier)
            fflush(stdout)
            Task { @MainActor in
                while !Task.isCancelled {
                    if let main = NSApp.mainMenu { Self.apply(to: main) }
                    try? await Task.sleep(for: .milliseconds(100))
                    // The readback separates the two readings of an absent badge on the
                    // accessibility plane. If this prints the string, SwiftUI **kept** the badge and
                    // the plane simply does not expose it for these items; if it prints nil, SwiftUI
                    // **cleared** it and nothing was ever drawn for anyone to read.
                    if let main = NSApp.mainMenu { Self.readback(main) }
                }
            }
        }

        @MainActor
        static func readback(_ menu: NSMenu) {
            for item in menu.items {
                if item.title.hasPrefix("SwiftUI Badged") {
                    print("readback\t\(item.title)\t\(item.badge?.stringValue ?? "<nil>")")
                    fflush(stdout)
                }
                if let submenu = item.submenu { readback(submenu) }
            }
        }

        @MainActor
        static func apply(to menu: NSMenu) {
            for item in menu.items {
                let badge: String? = switch item.title {
                case "SwiftUI Badged": "BADGESWIFTUI"
                case "SwiftUI Badged Chord": "BADGESWIFTUICHORD"
                default: nil
                }
                if let badge, item.badge?.stringValue != badge {
                    item.badge = NSMenuItemBadge(string: badge)
                }
                if let submenu = item.submenu { apply(to: submenu) }
            }
        }
    }
}
