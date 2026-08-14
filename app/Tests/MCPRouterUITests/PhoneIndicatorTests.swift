import Foundation
import MCPRouterKit
import Testing
@testable import MCPRouterUI

/// A4, A25 and A29 — the three criteria that were implemented correctly and asserted nowhere.
///
/// Each of these is a rule a reader can only check by reading the diff, which means it is not
/// checked: the next person to add a surface has nothing that tells them they broke it. The colour
/// rules in particular are the ones `DESIGN.md` §11 already caught the prototype breaking twice.
@Suite("Phone indicators, destructive confirmation and motion")
struct PhoneIndicatorTests {
    // MARK: - A4: an indicator hue means one thing, and is used for nothing else

    /// `DESIGN.md` §2: `--live` is "a child process is running". A reachable Mac genuinely has the
    /// router process up, so the dot earns it. Not-reachable is **neutral**, not `--attn`: nothing
    /// is being asked of the user and the state recovers on its own.
    @Test("the connection dot takes an indicator hue only where the indicator is true")
    func connectionDotSemantics() {
        #expect(ConnectionBanner(.reachable).dotColor == .live)
        #expect(ConnectionBanner(.notReachable).dotColor == .t3)
        #expect(ConnectionBanner(.neverPaired).dotColor == .t4)

        // The specific regression this guards: painting an unreachable Mac amber. `--attn` means
        // "wants a human decision", and an unreachable Mac wants none.
        for state in [ConnectionState.notReachable, .neverPaired] {
            #expect(ConnectionBanner(state).dotColor != .attention, "\(state) was painted --attn")
            #expect(ConnectionBanner(state).dotColor != .fail, "\(state) was painted --fail")
            #expect(ConnectionBanner(state).dotColor != .live, "\(state) claims a running process")
        }
    }

    /// The message block's three tones map onto exactly the meanings §2 assigns.
    @Test("a message block's tone maps onto the documented meaning of its hue")
    func messageBlockToneSemantics() {
        #expect(PhoneMessageBlock.Tone.neutral.accent == .t3)
        #expect(PhoneMessageBlock.Tone.caution.accent == .attention)
        #expect(PhoneMessageBlock.Tone.failure.accent == .fail)
    }

    /// The exclusivity half of §2, which a mapping test cannot reach: no *other* surface may reach
    /// for an indicator hue decoratively.
    ///
    /// This is the guard that catches the defect §11 names in the prototype — a green tick, a green
    /// trend delta, an amber switch track. `--live` may appear only where a process state is
    /// genuinely observed, which in this feature is the connection dot and nowhere else.
    @Test("no phone surface uses an indicator hue decoratively")
    func indicatorHuesAreNotDecoration() throws {
        let files = try PhoneSourceGuardTests.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")

        for (name, source) in files {
            let body = PhoneSourceGuardTests.stripped(source)

            // `--live` means "a child process is running", and two surfaces now observe exactly
            // that:
            //
            //  - `ConnectionBanner` — the connection dot.
            //  - `Library/LibraryScreen` — I3's library row, where the hue marks a server whose
            //    `MCPServer.state` is `.running`. That is not an analogy for the meaning, it is
            //    the meaning: the router has a live child process for that server right now. The
            //    row's other two states (idle, never started) take label tiers, and the fact is
            //    also stated in words, so the hue is emphasis rather than the only signal.
            let liveSurfaces: Set = [
                "ConnectionBanner.swift",
                "Library/LibraryScreen.swift"
            ]
            if body.contains("ColorToken.live") || body.contains(": .live") {
                #expect(
                    liveSurfaces.contains(name),
                    """
                    \(name) uses --live, which DESIGN.md §2 reserves for "a child process is \
                    running". Only the connection dot observes that. A confirmation mark, a trend \
                    or a decorative accent must use --accent or a label tier.
                    """
                )
            }

            // --attn is reserved for a decision a human has to take before something irreversible
            // or consequential happens. Two surfaces qualify, and the list is exhaustive so a
            // third has to argue its way in here rather than arriving in a diff.
            //
            //  - `PairedMacSettingsView` — the pre-scan caution before granting a pairing.
            //  - `CapabilityPlateView` — I2's capability plate, where amber marks the two lines
            //    that state a consequence of queueing this entry: it runs a program on your Mac
            //    with your own access, and it needs a credential. Those are the decision the
            //    surface exists to put in front of the user before the commit (spec-I2 A12–A13),
            //    which is exactly §2's meaning rather than an extension of it.
            //  - `Triage/TriageRow` — I3's capability line, which is the same argument one level
            //    up. The row states what queueing this entry would let it do *before* anything is
            //    ticked, and amber marks the two clauses that carry a consequence: it runs a
            //    program on your Mac, and it needs a credential. The tick is the decision, and
            //    this line is what the decision is taken on.
            //
            // Offline is deliberately absent: `DiscoverScreen` renders "the router isn't running"
            // in `--t3`, because that asks for an action, not a decision. I3's Triage follows it —
            // its offline pane is `--t3` and its unreadable-dismissals pane is `--fail`, since a
            // file that will not decode has failed rather than asked for a judgement.
            let attnSurfaces: Set = [
                "PairedMacSettingsView.swift",
                "Discover/CapabilityPlateView.swift",
                "Triage/TriageRow.swift"
            ]
            if body.contains("ColorToken.attention") || body.contains(": .attention") {
                #expect(
                    attnSurfaces.contains(name),
                    """
                    \(name) uses --attn outside the surfaces that ask for a decision. §2 reserves \
                    amber for "wants a human decision"; a state the user can only be informed of \
                    takes a label tier.
                    """
                )
            }
        }
    }

    // MARK: - A25: unpair states its consequence, and is never the default

    /// `DESIGN.md` §9 prefers undo to confirm — but unpairing revokes a credential and cannot be
    /// undone, so it earns a dialog. What it must not be is "Are you sure?".
    @Test("the unpair confirmation names what stops and what survives")
    func unpairNamesItsConsequence() {
        let entry = PairingCopy.entry(.unpairConfirm)

        let headline = try? #require(entry.headline)
        #expect(headline?.contains("{mac}") == true, "the headline does not name the Mac being unpaired")

        // Both halves of the consequence, which is what makes it a named consequence rather than a
        // warning: what stops working, and what is not destroyed.
        #expect(entry.body.contains("stop being able to queue"), "the copy does not say what stops working")
        #expect(entry.body.contains("stays there"), "the copy does not say what survives")
        #expect(entry.body.contains("pair again"), "the copy does not say the action is repeatable")

        // The generic form this criterion exists to forbid.
        #expect(!entry.body.lowercased().contains("are you sure"))

        // Cancel is a separate control, not the same button wearing another label.
        #expect(entry.actionLabel == "Unpair")
        #expect(entry.secondaryActionLabel == "Cancel")
        #expect(entry.actionLabel != entry.secondaryActionLabel)
    }

    /// The roles carry the platform behaviour: `.destructive` is never the default button, and
    /// `.cancel` is what the Escape key and an outside tap resolve to.
    @Test("unpair is presented as a platform confirmation with destructive and cancel roles")
    func unpairUsesPlatformRoles() throws {
        let source = try PhoneSourceGuardTests.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
            .first { $0.name.hasSuffix("PairingFlowView.swift") }
        let body = try PhoneSourceGuardTests.stripped(#require(source).source)

        // A8: the platform's presentation, not a re-created Mac sheet.
        #expect(body.contains(".confirmationDialog("), "unpair does not use the platform confirmation")
        #expect(body.contains("role: .destructive"), "the unpair action is not marked destructive")
        #expect(body.contains("role: .cancel"), "there is no cancel role, so dismissal has no defined result")
    }

    // MARK: - A29: motion is transform and opacity only, and Reduce Motion removes it

    /// Every animation in the feature must be reachable by a Reduce Motion check. The failure this
    /// catches is the ordinary one: someone adds a second animated view and forgets the guard.
    @Test("every animation honours Reduce Motion")
    func everyAnimationIsReduceMotionGuarded() throws {
        let files = try PhoneSourceGuardTests.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")

        var animatedFiles = 0
        for (name, source) in files {
            let body = PhoneSourceGuardTests.stripped(source)
            guard body.contains(".animation(") || body.contains("withAnimation") else { continue }
            animatedFiles += 1
            #expect(
                body.contains("reduceMotion"),
                "\(name) animates without consulting accessibilityReduceMotion"
            )
        }
        #expect(animatedFiles > 0, "no animated file was found, so this guard proved nothing")
    }

    /// `DESIGN.md` §7 forbids animating opacity from 0 on entry, because the content is unreadable
    /// for the first half of the fade. Transform-only entry is the rule.
    @Test("nothing enters by fading up from zero opacity")
    func noEntryAnimationStartsInvisible() throws {
        let files = try PhoneSourceGuardTests.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")

        for (name, source) in files {
            let body = PhoneSourceGuardTests.stripped(source)
            for forbidden in [".opacity(0)", ".opacity(0.0)", "opacity: 0)"] {
                #expect(!body.contains(forbidden), "\(name) starts a view fully transparent: \(forbidden)")
            }
            // The SwiftUI shorthand for the same defect.
            #expect(!body.contains(".transition(.opacity"), "\(name) uses an opacity transition on entry")
        }
    }

    /// Reduce Motion must remove the animation and never the state it reports — a spinner that
    /// disappears under Reduce Motion takes the "still working" signal with it.
    @Test("the working indicator keeps reporting when its motion is removed")
    func reduceMotionRemovesMotionNotMeaning() throws {
        let source = try PhoneSourceGuardTests.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
            .first { $0.name.hasSuffix("PairingSurfaces.swift") }
        let body = try PhoneSourceGuardTests.stripped(#require(source).source)

        // The arc is still drawn; only the rotation is conditional.
        #expect(
            body.contains("reduceMotion ? nil :"),
            "the animation is not made conditional on Reduce Motion"
        )
        #expect(body.contains("rotationEffect"), "the indicator no longer animates a transform")
        #expect(
            !body.contains("if reduceMotion { EmptyView"),
            "the indicator is removed under Reduce Motion, taking its meaning with it"
        )
    }
}
