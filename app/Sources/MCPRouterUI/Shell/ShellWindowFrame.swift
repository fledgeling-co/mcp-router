#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI

    /// Makes the window's frame survive quit and relaunch, because SwiftUI's own restoration does
    /// not reliably do it.
    ///
    /// **This was measured before it was written, and the measurement is the justification.** A
    /// `WindowGroup` does give its window an implicit frame-autosave name and does sometimes restore
    /// through it, which is why an earlier revision of this item removed a bridge and left the job to
    /// SwiftUI. Driven on 2026-08-14 against that build, on this machine:
    ///
    /// - a programmatic move (`AXPosition` / `AXSize`, which is how the acceptance gate moves a
    ///   window without touching the user's mouse) updated the implicit autosave key on one run and
    ///   left it at the launch frame on the next two;
    /// - the frame the app came back at was not the frame it was last at, but one from an earlier
    ///   session — restoration is reading saved *application state*, which the autosave key does not
    ///   feed;
    /// - one relaunch restored the window to `-266,-1172`, off every attached screen, from a frame
    ///   saved during a session with an external display. A window that cannot be seen is worse than
    ///   a window in the wrong place.
    ///
    /// The implicit name is also fragile by construction — it embeds the root view's *type
    /// signature*, so `ModifiedContent<ShellWindow, _FlexFrameLayout>` becomes a different saved
    /// window the moment a modifier is wrapped around it.
    ///
    /// So the app stores its own frame, in the same `UserDefaults` that already holds the selected
    /// destination, written on every move and resize. The decisions are in `ShellFrameRestoration`
    /// where tests can reach them; this view is the AppKit bridge that has to exist because SwiftUI
    /// exposes no window.
    struct WindowFrameRestorer: NSViewRepresentable {
        let store: ShellRestoration

        func makeNSView(context: Context) -> NSView {
            let view = FrameObservingView()
            view.store = store
            context.coordinator.view = view
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class Coordinator {
            var view: NSView?
        }
    }

    /// The rules about a stored frame, separated from the AppKit plumbing so they can be tested.
    public enum ShellFrameRestoration {
        /// Whether a stored frame may be applied.
        ///
        /// A frame is usable when enough of it lands on some screen for the window to be reachable —
        /// title bar included, since a window whose title bar is off the top cannot be moved back.
        /// The rule is deliberately about *area on a visible frame* rather than mere intersection: a
        /// window overlapping a screen by one pixel satisfies intersection and is unusable.
        public static func isUsable(_ frame: CGRect, on screens: [CGRect]) -> Bool {
            guard frame.width > 0, frame.height > 0, !screens.isEmpty else { return false }
            let needed = frame.width * frame.height * 0.5
            for screen in screens {
                let overlap = frame.intersection(screen)
                guard !overlap.isNull else { continue }
                if overlap.width * overlap.height >= needed { return true }
            }
            return false
        }

        /// The frame to open at: the stored one when it is usable, otherwise nothing and macOS
        /// decides. Returning nil rather than a clamped guess is deliberate — AppKit's own placement
        /// is better than this type's arithmetic, and a half-corrected frame hides the fact that the
        /// stored one was unusable.
        public static func openingFrame(stored: CGRect?, screens: [CGRect]) -> CGRect? {
            guard let stored, isUsable(stored, on: screens) else { return nil }
            return stored
        }
    }

    /// A zero-size view whose only job is to reach the `NSWindow` and keep its frame stored.
    ///
    /// Restoring happens once, on the first move into a window, and only after the current layout
    /// pass: a `setFrame` issued while SwiftUI is still installing the scene is overwritten by
    /// SwiftUI's own placement.
    final class FrameObservingView: NSView {
        var store: ShellRestoration = .standard
        private var restored = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                // Left the window: stop listening. Unregistering here rather than in `deinit` is
                // forced by concurrency checking — a nonisolated `deinit` may not touch the token
                // array — and it is the better place anyway, since a view removed from its window
                // has nothing left to observe.
                stopObserving()
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.restoreIfNeeded(window)
                self?.observe(window)
            }
        }

        private func stopObserving() {
            for token in observers {
                NotificationCenter.default.removeObserver(token)
            }
            observers = []
        }

        private func restoreIfNeeded(_ window: NSWindow) {
            guard !restored else { return }
            restored = true
            let screens = NSScreen.screens.map(\.visibleFrame)
            guard let frame = ShellFrameRestoration.openingFrame(
                stored: store.restoredFrame(),
                screens: screens
            ) else {
                return
            }
            window.setFrame(frame, display: true)
        }

        private func observe(_ window: NSWindow) {
            guard observers.isEmpty else { return }
            let store = store
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                let token = NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { notification in
                    // The window comes from the notification rather than from a capture, so this
                    // block holds nothing alive: capturing the window would keep it after it closed.
                    guard let moved = notification.object as? NSWindow else { return }
                    // `MainActor.assumeIsolated` rather than a `Task`: the queue is `.main`, so this
                    // already runs on the main actor, and hopping would leave a window in which a
                    // quit could land — which is exactly where the previous, SwiftUI-owned mechanism
                    // was measured to lose a move.
                    MainActor.assumeIsolated {
                        store.save(frame: moved.frame)
                    }
                }
                observers.append(token)
            }
        }
    }
#endif
