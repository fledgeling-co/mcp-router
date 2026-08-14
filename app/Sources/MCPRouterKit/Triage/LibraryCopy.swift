import Foundation

/// Every string the Library surface renders.
///
/// The Library is the narrowest surface in the app: it lists what the paired Mac has declared, and
/// offers no act that changes any of it. **It also carries the narrowing sentence**, and that
/// placement is inherited rather than invented — `PairingCopy` put `neverInstalls` on the library
/// surface under the note *"the narrowing is rendered where permission is being decided, and on the
/// surface most likely to be mistaken for an install surface"*. That reasoning survives the
/// placeholder this item retires, so the sentence moves here rather than disappearing with it.
public enum LibraryCopy {
    // MARK: - Substitution

    public enum Token: String, Sendable, CaseIterable {
        /// The paired Mac's name; `"your Mac"` when none is paired.
        case mac
        /// The size of a locally-held set: the decoded `servers` array, or the filtered result.
        case count
        /// The user's filter text, echoed back.
        case query

        public var placeholder: String { "{\(rawValue)}" }
    }

    public struct Entry: Sendable, Equatable {
        public let headline: String?
        public let body: String
        public let actionLabel: String?
        public let carriesNarrowing: Bool

        public init(
            headline: String? = nil,
            body: String,
            actionLabel: String? = nil,
            carriesNarrowing: Bool = false
        ) {
            self.headline = headline
            self.body = body
            self.actionLabel = actionLabel
            self.carriesNarrowing = carriesNarrowing
        }

        public var tokens: Set<Token> {
            let text = (headline ?? "") + body + (actionLabel ?? "")
            return Set(Token.allCases.filter { text.contains($0.placeholder) })
        }

        public func resolved(_ values: [Token: String]) -> Entry {
            func sub(_ s: String?) -> String? {
                guard var out = s else { return nil }
                for (token, value) in values {
                    out = out.replacingOccurrences(of: token.placeholder, with: value)
                }
                return out
            }
            return Entry(
                headline: sub(headline),
                body: sub(body) ?? body,
                actionLabel: sub(actionLabel),
                carriesNarrowing: carriesNarrowing
            )
        }
    }

    // MARK: - Keys

    public enum ChromeKey: String, Sendable, CaseIterable {
        case subtitle
        case filterPlaceholder
        case footer
        /// The narrowing, carried on this surface. Its text is `PairingCopy.neverInstalls`
        /// **verbatim** — asserted, not copied by hand.
        case narrowing
    }

    /// The per-row facts. Every one is a named `MCPServer` field.
    ///
    /// `neverStarted` exists because `idleSec == 0` is byte-identical for a server that went idle
    /// this instant and one that has never been started at all — the router computes
    /// `idleSec: live?.idleSec ?? 0`. Rendering the second as "idle 0s" would state a freshness
    /// nobody observed, so it reads from `MCPServer.neverUsed` instead.
    public enum FactKey: String, Sendable, CaseIterable {
        case toolCount
        case runningNow
        case idleFor
        case neverStarted
    }

    /// The states. **No Success key**: the Library has no commit, so there is nothing to succeed.
    /// **No Partial key**: `/servers` returns one document, so there is no half of it to fail.
    public enum StateKey: String, Sendable, CaseIterable {
        case empty
        case emptyFiltered
        case failed
        case offline
        /// The absence stated as a fact rather than drawn as an empty list. There is no skills index
        /// and no `/skills` route on either router — re-verified for this item.
        case skillsAbsent
    }

    public enum Key: Sendable, Equatable, Hashable {
        case chrome(ChromeKey)
        case fact(FactKey)
        case state(StateKey)

        public static var allCases: [Key] {
            ChromeKey.allCases.map(Key.chrome)
                + FactKey.allCases.map(Key.fact)
                + StateKey.allCases.map(Key.state)
        }
    }

    public static func entry(_ key: Key) -> Entry {
        switch key {
        case let .chrome(k): chrome(k)
        case let .fact(k): fact(k)
        case let .state(k): state(k)
        }
    }

    // MARK: - Chrome

    private static func chrome(_ key: ChromeKey) -> Entry {
        switch key {
        case .subtitle:
            Entry(body: "{count} servers · read-only from here")
        case .filterPlaceholder:
            Entry(body: "Filter")
        case .footer:
            Entry(body: "Adding, changing and removing all happen at your Mac. This is the same list, so you know what you are carrying.")
        case .narrowing:
            // The shared constant itself, not a paraphrase of it. A second wording of a security
            // sentence is a second sentence, and the one nobody updates is the one that ships.
            Entry(body: PairingCopy.neverInstalls, carriesNarrowing: true)
        }
    }

    // MARK: - Facts

    private static func fact(_ key: FactKey) -> Entry {
        switch key {
        case .toolCount:
            Entry(body: "{count} tools")
        case .runningNow:
            Entry(body: "running now")
        case .idleFor:
            Entry(body: "idle {count}")
        case .neverStarted:
            Entry(body: "never started")
        }
    }

    // MARK: - States

    private static func state(_ key: StateKey) -> Entry {
        switch key {
        case .empty:
            Entry(
                headline: "No servers declared",
                body: "{mac} has no MCP servers declared yet. Queue one from Triage and accept it at your Mac, and it will appear here.",
                actionLabel: "Go to Triage"
            )
        case .emptyFiltered:
            Entry(
                headline: "No server matches \"{query}\"",
                body: "Clear the filter to see all {count}.",
                actionLabel: "Clear filter"
            )
        case .failed:
            Entry(
                headline: "The server list could not be read",
                body: "The router answered with something this version does not understand. Nothing on your Mac has changed.",
                actionLabel: "Try again"
            )
        case .offline:
            Entry(
                headline: "The router is not running on {mac}",
                body: "The library is the router's own list of declared servers, so there is nothing to show until it starts. Open MCP Router on your Mac."
            )
        case .skillsAbsent:
            Entry(
                headline: "Skills are not listed here.",
                body: "The router publishes no skills endpoint, so this phone has nothing to read. Your Mac's Skills board is the only place they appear."
            )
        }
    }

    public static var narrowingKeys: Set<Key> {
        Set(Key.allCases.filter { entry($0).carriesNarrowing })
    }
}
