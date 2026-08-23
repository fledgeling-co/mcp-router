#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// Where the shell's restorable state is kept, and why it is not `@SceneStorage`.
    ///
    /// Apple documents no persistence timing for `@SceneStorage` and states its contents are
    /// destroyed with the scene, so "the selection survives quit and relaunch" is not a promise it
    /// makes. A32 asks for restoration across a *process* boundary, which is `UserDefaults` — written
    /// on change rather than at termination, because a process that is killed rather than quit never
    /// reaches a termination hook.
    ///
    /// The suite is injectable so a test can drive real restoration against a scratch domain instead
    /// of the developer's own preferences, which is the difference between testing this and
    /// corrupting the machine it runs on.
    ///
    /// `@unchecked Sendable` is a promise, and this one is honest and narrow: the struct holds no
    /// mutable state of its own, and `UserDefaults` is documented by Apple as thread-safe — "the
    /// UserDefaults class is thread-safe". `SWIFT_PRACTICES.md` §1 permits the annotation exactly
    /// where the type has no mutable state or guards it with its own lock, and asks for which one
    /// to be said. It is the first.
    public struct ShellRestoration: @unchecked Sendable {
        public static let destinationKey = "shell.selectedDestination"
        public static let sidebarVisibleKey = "shell.sidebarVisible"
        public static let windowFrameKey = "shell.windowFrame"
        /// Which pane the Settings window was last showing. Named here beside the destination for
        /// the same reason: two windows, two selections, and neither may reach into the other.
        public static let settingsPaneKey = "shell.settingsPane"
        /// Whether the menu-bar status item is shown. Named on `SettingsPresentation` so the pane
        /// and the store cannot disagree about which key they mean.
        public static let menuBarVisibleKey = SettingsPresentation.menuBarVisibleKey
        /// Whether the popover's band may install. Named on `SettingsPresentation` for the same
        /// reason, and read by `InboxBoardModel.bandZone` rather than by the view.
        public static let approveFromPopoverKey = SettingsPresentation.approveFromPopoverKey

        private let defaults: UserDefaults

        public init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        public static let standard = ShellRestoration()

        public func restoredDestination() -> Destination {
            // A stored value this build no longer has falls back rather than rendering nothing.
            Destination.restoring(defaults.string(forKey: Self.destinationKey))
        }

        /// The sidebar shows by default, so an absent key must read as `true` rather than as
        /// `Bool`'s zero value — `bool(forKey:)` returns `false` for a key nobody has written, which
        /// would hide the sidebar on every first launch.
        public func restoredSidebarVisible() -> Bool {
            defaults.object(forKey: Self.sidebarVisibleKey) as? Bool ?? true
        }

        public func save(destination: Destination) {
            defaults.set(destination.rawValue, forKey: Self.destinationKey)
        }

        public func save(sidebarVisible: Bool) {
            defaults.set(sidebarVisible, forKey: Self.sidebarVisibleKey)
        }

        /// Whether the menu-bar status item is shown.
        ///
        /// Shown by default, so an absent key must read as `true` for the same reason the sidebar's
        /// does: `bool(forKey:)` returns `false` for a key nobody has written, which would hide a
        /// menu-bar app's main affordance on every first launch.
        ///
        /// This lives here rather than as `@AppStorage` in the scene so it has an evidence lane at
        /// all. `app/MCPRouter` is not a SwiftPM target, so a preference read straight from a
        /// `Scene` is a preference no test can drive; here, restoration across a process boundary is
        /// assertable against a scratch defaults domain.
        public func restoredMenuBarVisible() -> Bool {
            defaults.object(forKey: Self.menuBarVisibleKey) as? Bool
                ?? SettingsPresentation.menuBarVisibleDefault
        }

        public func save(menuBarVisible: Bool) {
            defaults.set(menuBarVisible, forKey: Self.menuBarVisibleKey)
        }

        /// Whether a queued item may be installed from the popover's band.
        ///
        /// **On by default, so an absent key must read as `true`** — `bool(forKey:)` returns `false`
        /// for a key nobody has written, which would ship the preference silently off and make the
        /// design of record's own switch state unreachable until someone toggled it twice.
        ///
        /// Read through the store rather than as `@AppStorage` in the scene for the reason
        /// `restoredMenuBarVisible` is: `app/MCPRouter` is not a SwiftPM target, so a preference read
        /// straight from a `Scene` is a preference no test can drive — and this one gates an install.
        public func restoredApproveFromPopover() -> Bool {
            defaults.object(forKey: Self.approveFromPopoverKey) as? Bool
                ?? SettingsPresentation.approveFromPopoverDefault
        }

        public func save(approveFromPopover: Bool) {
            defaults.set(approveFromPopover, forKey: Self.approveFromPopoverKey)
        }

        /// Which Settings pane was last looked at.
        ///
        /// **A `Settings` scene destroys its window on close**, so a scene-local `@State` would
        /// reset the pane to Router on every `⌘,` — which is not how a settings window behaves on
        /// this platform, and is a regression against the Settings board, whose selected destination
        /// survived precisely because this type held it. So the pane is stored the way the
        /// destination is, and gains the same evidence lane: restoration across a process boundary,
        /// assertable against a scratch defaults domain.
        ///
        /// An absent or unknown value falls back rather than failing, exactly as
        /// `Destination.restoring` does — a pane name this build no longer has must land somewhere
        /// real rather than rendering nothing.
        public func restoredSettingsPane() -> SettingsPane {
            SettingsPane.restoring(defaults.string(forKey: Self.settingsPaneKey))
        }

        public func save(settingsPane: SettingsPane) {
            defaults.set(settingsPane.rawValue, forKey: Self.settingsPaneKey)
        }

        /// The window frame this app last had, or nil if it has never stored a usable one.
        ///
        /// Stored as four numbers rather than as an archived `NSRect`, so the value is readable in
        /// `defaults read` and cannot fail to decode across an OS release. A partial, mistyped or
        /// zero-sized entry reads as nil, which falls back to macOS's own placement — a window is
        /// better placed by AppKit than by half a stored frame.
        public func restoredFrame() -> CGRect? {
            guard let numbers = defaults.array(forKey: Self.windowFrameKey) as? [Double],
                  numbers.count == 4,
                  numbers[2] > 0, numbers[3] > 0 else { return nil }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }

        public func save(frame: CGRect) {
            defaults.set(
                [frame.origin.x, frame.origin.y, frame.width, frame.height],
                forKey: Self.windowFrameKey
            )
        }
    }
#endif
