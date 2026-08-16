#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The shell's chrome decisions, declared as data rather than only as modifiers.
    ///
    /// Three clauses — A6, A8 and A10 — are about what the shell *does not* do: no indicator colour
    /// used decoratively, no glass on the window's content, no pointing-hand cursor. A test cannot
    /// read a `.background(...)` out of an opaque SwiftUI view tree, so asserting those from a unit
    /// test would mean asserting nothing. Declaring them here gives each clause a subject, and the
    /// views below read these constants rather than restating them, so the declaration and the
    /// render cannot disagree without the compiler noticing.
    ///
    /// The source-level half is in `scripts/lint/no-raw-design-values.sh`, which forbids the
    /// spellings that would bypass this file entirely — a material, a pointing-hand cursor, a raw
    /// frame height. Between them the claim is real: the declaration says what is intended, and the
    /// gate proves nothing else was written.
    public enum ShellChrome {
        /// `DESIGN.md` §3.3: content is opaque; Liquid Glass is for floating chrome only. This is a
        /// token, not a material, and that is the whole of A8.
        public static let contentBackground: ColorToken = .ground

        /// One tonal step up from the ground, per §2. Also not a material.
        public static let sidebarBackground: ColorToken = .panel

        /// §3.8: the arrow cursor everywhere in app chrome. The pointer hand is a web-content
        /// signal, and the shell sets no cursor at all — this records that decision so A10 has
        /// something to assert beyond the absence of a grep hit.
        public static let usesPointingHandCursor = false

        /// Every element in the shell drawn in one of the four exclusive indicator colours, with
        /// the meaning that justifies it.
        ///
        /// `DESIGN.md` §2: "Nothing else in the app may be any of these three indicator colours —
        /// that exclusivity is what makes one amber dot in a menu bar mean something." A6's test
        /// walks this list and fails on an entry whose justification does not match the token's
        /// documented meaning, and separately fails if the shell renders an indicator colour that
        /// is not listed here.
        public static let indicatorUses: [IndicatorUse] = [
            IndicatorUse(
                element: "sidebar row label and icon, while selected",
                token: .accent,
                justification: "selection"
            ),
            IndicatorUse(
                element: "keyboard focus ring",
                token: .accent,
                justification: "focus"
            ),
            IndicatorUse(
                element: "the readout's running count and its trace",
                token: .live,
                justification: "a child process is running"
            ),
            IndicatorUse(
                element: "the Servers badge",
                token: .attention,
                justification: "wants a human decision"
            ),
            // M3's board. Registered here rather than in a second list, so there stays one place a
            // reviewer reads to learn every element in the Mac app allowed to be an indicator
            // colour — which is the only way the exclusivity in §2 is checkable at all.
            IndicatorUse(
                element: "the Servers board's breaker lamp and slot, while a process is up",
                token: .live,
                justification: "a child process is running"
            ),
            IndicatorUse(
                element: "a server row's subtitle and breaker, while it is tripped or placarded",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "a server row's error count, and the inspector's failure banners",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "the destructive label on Remove, which names a failure it would cause",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "a server row's subtitle and breaker, while it holds a change or needs authorising",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "the stale-reading and partial-index banners",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "the board's one prominent action, Add server…",
                token: .accent,
                justification: "the one primary action"
            ),
            // M8's surfaces. Added here rather than left implicit: the token-level check passes for
            // a new file the moment an earlier item has declared the same token, so a surface can
            // start drawing an indicator colour without anything objecting. This list is the part a
            // reviewer actually reads, and a list that stops naming where a colour is drawn stops
            // being able to answer the question §2 asks.
            IndicatorUse(
                element: "the menu-bar status item's dot, whenever any server wants a decision",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "a popover band row's glyph, for a held change or an unauthorised server",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "a popover band row's glyph, for a server that failed to index",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "the popover's stale-refresh notice, and a call row's dot when the call errored",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "a popover call row's dot, for a call the router served without error",
                token: .live,
                justification: "a child process is running"
            ),
            IndicatorUse(
                element: "a tool's newly added input parameter in the held-change diff",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "the popover's one prominent action, Open MCP Router",
                token: .accent,
                justification: "the one primary action"
            ),
            IndicatorUse(
                element: "Settings' Forget the stored token, while the router is rejecting it",
                token: .accent,
                justification: "the one primary action"
            ),
            IndicatorUse(
                element: "Settings' router-unreachable banner",
                token: .fail,
                justification: "failed or tripped"
            ),
            IndicatorUse(
                element: "Settings' keychain-unavailable banner",
                token: .attention,
                justification: "wants a human decision"
            ),
            // I6's band. Registered here for the reason every entry above is: A6 fails on an
            // indicator colour the shell renders and this list does not name, and the band's edge
            // was an unnamed one — `noUndeclaredIndicatorUse` only checks that a token appears
            // somewhere in the list, so a second use of an already-listed token cannot fail it. The
            // entry is what makes the justification checkable.
            IndicatorUse(
                element: "the menu-bar popover's inbox band, its edge stroke",
                token: .attention,
                justification: "wants a human decision"
            )
        ]

        /// The tokens the shell is allowed to draw an indicator colour in, derived from the list
        /// above so the two cannot drift.
        public static var indicatorTokensUsed: Set<ColorToken> {
            Set(indicatorUses.map(\.token))
        }
    }

    /// One justified use of an exclusive indicator colour.
    public struct IndicatorUse: Equatable, Sendable {
        /// What is drawn in it, named the way a reviewer would look for it on screen.
        public let element: String
        public let token: ColorToken
        /// The documented meaning this use claims. A6 checks it against `DESIGN.md`'s own wording
        /// for the token, so "it looked good there" cannot be spelled as a justification.
        public let justification: String

        public init(element: String, token: ColorToken, justification: String) {
            self.element = element
            self.token = token
            self.justification = justification
        }
    }
#endif
