#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterUI

    /// A33's decidable half: what a stored frame is, and when one may be applied.
    ///
    /// The rendered half — move the window, quit, relaunch, compare — stays in
    /// `scripts/acceptance/mac-shell.sh`, because no SwiftPM test can place a real window on a real
    /// screen. What is here is the part that was actually wrong: the previous mechanism restored a
    /// frame saved during an external-display session and put the window at `-266,-1172`, off every
    /// screen, where it could not be reached or moved back.
    @Suite("Shell window frame restoration")
    struct ShellFrameRestorationTests {
        private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)

        @Test("a frame fully on screen is usable")
        func onScreenIsUsable() {
            #expect(ShellFrameRestoration.isUsable(
                CGRect(x: 180, y: 140, width: 980, height: 620),
                on: [screen]
            ))
        }

        @Test("the frame that put the window off every screen is rejected")
        func theMeasuredFailureIsRejected() {
            // The literal frame a relaunch restored on 2026-08-14, from a session with an external
            // display attached. This is the regression this whole mechanism exists to prevent, so it
            // is asserted as itself rather than as a generic negative case.
            let offscreen = CGRect(x: -266, y: -1172, width: 1000, height: 640)
            #expect(!ShellFrameRestoration.isUsable(offscreen, on: [screen]))
            #expect(ShellFrameRestoration.openingFrame(stored: offscreen, screens: [screen]) == nil)
        }

        @Test("a frame that only clips a screen's corner is rejected, not merely one that misses entirely")
        func barelyOverlappingIsRejected() {
            // Intersection alone would accept this: it overlaps by 20×20 points of a 1000×640 window.
            // A window reachable only by its corner is not reachable.
            let corner = CGRect(x: -980, y: -620, width: 1000, height: 640)
            #expect(corner.intersects(screen))
            #expect(!ShellFrameRestoration.isUsable(corner, on: [screen]))
        }

        @Test("a frame on a second screen is usable when that screen is attached, and not when it is gone")
        func aSecondScreenIsHonoured() {
            let external = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
            let onExternal = CGRect(x: -2000, y: 200, width: 900, height: 500)
            #expect(ShellFrameRestoration.isUsable(onExternal, on: [screen, external]))
            #expect(!ShellFrameRestoration.isUsable(onExternal, on: [screen]))
        }

        @Test("no stored frame, no screens, or a zero-sized frame all decline rather than guess")
        func degenerateInputsDecline() {
            #expect(ShellFrameRestoration.openingFrame(stored: nil, screens: [screen]) == nil)
            #expect(!ShellFrameRestoration.isUsable(CGRect(x: 0, y: 0, width: 900, height: 450), on: []))
            #expect(!ShellFrameRestoration.isUsable(CGRect(x: 0, y: 0, width: 0, height: 450), on: [screen]))
        }

        @Test("a usable stored frame is returned unchanged rather than clamped")
        func usableFramesAreNotAdjusted() {
            let stored = CGRect(x: 180, y: 140, width: 980, height: 620)
            #expect(ShellFrameRestoration.openingFrame(stored: stored, screens: [screen]) == stored)
        }

        @Test("the store round-trips a frame through real defaults")
        func theStoreRoundTrips() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            #expect(scratch.store.restoredFrame() == nil)
            let frame = CGRect(x: 180, y: 140, width: 980, height: 620)
            scratch.store.save(frame: frame)
            #expect(scratch.store.restoredFrame() == frame)
        }

        /// A half-written or nonsense entry must read as "nothing stored" rather than as a frame.
        /// `UserDefaults` will hand back whatever is under the key, including something another
        /// version of this app wrote, and a zero-sized window is not recoverable by the user.
        @Test("a malformed or zero-sized stored frame reads as nothing stored")
        func malformedEntriesReadAsAbsent() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            scratch.defaults.set([1.0, 2.0], forKey: ShellRestoration.windowFrameKey)
            #expect(scratch.store.restoredFrame() == nil)

            scratch.defaults.set([1.0, 2.0, 0.0, 620.0], forKey: ShellRestoration.windowFrameKey)
            #expect(scratch.store.restoredFrame() == nil)

            scratch.defaults.set("180 140 980 620", forKey: ShellRestoration.windowFrameKey)
            #expect(scratch.store.restoredFrame() == nil)
        }
    }
#endif
