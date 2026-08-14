import Foundation

/// The one line every Triage row carries, stating what the entry would be able to do.
///
/// **It is the same derivation the capability plate uses, not a second one.** `CapabilityPlate`
/// already turns an `install` descriptor into an accumulating set of severity-carrying lines, and
/// this type calls it and shortens the result. A row and a detail plate that derived the same
/// security fact independently would be one edit away from disagreeing about the same entry, and
/// the row is the half nobody would check.
///
/// The brief requires this line to be visible **without opening anything**, and — the second of the
/// two prototype bugs it names — **never truncated**. Truncating is only avoidable because the
/// clause vocabulary is closed: there are seven possible clauses, all short, so the line is brief by
/// construction rather than by hoping entry names stay small.
public enum CapabilitySummary {
    /// One short clause. Mirrors `CapabilityPlate`'s seven outcomes exactly, one case each, so an
    /// eighth outcome added to the plate **fails to compile here** rather than silently rendering a
    /// row with a missing clause.
    public enum Clause: String, Sendable, Equatable, CaseIterable {
        case runsLocally
        case remote
        case remoteUnknownHost
        case credential
        case credentialSmithery
        case archived
        case noInstall

        /// Whether this clause, on its own, wants a human decision.
        ///
        /// **Two clauses want attention and the other five are facts**, and the split is the whole
        /// of A6's colour rule. Running a program on the user's Mac is the case the colour exists
        /// for; a credential on a host that has not already made one a foregone conclusion is the
        /// other. A remote server, an unparseable host, an archived repository and a missing
        /// descriptor are all facts the row states in words without claiming they need deciding.
        ///
        /// `.credentialSmithery` is a fact **because** every Smithery-hosted install declares a
        /// required `Authorization` unconditionally (`src/registry.ts:172-179`): within that subset
        /// the clause distinguishes nothing, and Smithery is a majority of the corpus, so treating
        /// it as attention paints the colour on most rows and stops it meaning anything anywhere.
        public var wantsAttention: Bool {
            switch self {
            case .runsLocally, .credential: true
            case .remote, .remoteUnknownHost, .credentialSmithery, .archived, .noInstall: false
            }
        }
    }

    /// A resolved summary: the clauses in the plate's own order, and whether any of them wants a
    /// human decision.
    public struct Resolved: Sendable, Equatable {
        public let clauses: [Clause]
        /// The host, for `.remote`. Nil for every other clause.
        public let host: String?
        /// `--attn` at the view boundary. This type carries no colour: `MCPRouterKit` holds no UI
        /// framework (`SWIFT_PRACTICES.md` §8).
        public let wantsAttention: Bool
        /// Whether the entry can be selected at all. An entry with no install descriptor has
        /// nothing for the Mac to review, so it is not selectable and never reaches the commit.
        public let isSelectable: Bool

        /// The rendered line, clauses joined. The join is ` · ` rather than a comma because the
        /// clauses are peers rather than a sentence, and the middle dot is what the design
        /// representation draws.
        public func text(_ copy: (Clause) -> String) -> String {
            clauses.map(copy).joined(separator: " · ")
        }
    }

    /// Derive the row's summary from the same inputs the plate reads.
    ///
    /// **The Smithery split is inherited rather than flattened, and that is the point.** Every
    /// Smithery-hosted install declares a required `Authorization` unconditionally
    /// (`src/registry.ts:172-179`), so within that subset a credential warning distinguishes
    /// nothing — and Smithery is a majority of the corpus, so a single unconditional credential
    /// clause would paint the attention colour on most rows and stop it meaning anything. The plate
    /// already admits this by choosing a different copy key; the summary carries the admission
    /// through by giving that key a clause of its own **with no attention severity**.
    public static func resolve(for entry: RegistryEntry) -> Resolved {
        resolve(install: entry.install, archived: entry.archived)
    }

    /// The same derivation from the two inputs it actually reads.
    ///
    /// Mirrors `CapabilityPlate.lines(install:archived:)` deliberately. The Queue renders a
    /// `QueuedCapability`, which carries an `install` but is not a `RegistryEntry` — and
    /// synthesising a `RegistryEntry` from it just to call the other overload would be fabricating a
    /// registry result out of queue data, which is exactly the kind of thing that later reads as one.
    public static func resolve(install: RegistryInstall?, archived: Bool?) -> Resolved {
        let lines = CapabilityPlate.lines(install: install, archived: archived)
        let clauses = lines.compactMap(clause(for:))
        let host = lines.first { $0.kind == .remote }?.host

        // Severity is derived from the **clauses**, not from `CapabilityPlate.severity(of:)`.
        //
        // The plate marks its credential line `.attention` for the Smithery and non-Smithery cases
        // alike and distinguishes them only by copy key — which is the right answer for a detail
        // plate the user opened deliberately, and the wrong one for a row in a list. Taking the
        // plate's verdict here made every Smithery-hosted entry want attention, and since Smithery
        // is a majority of the corpus that fired the colour on most rows: exactly the noise A6
        // exists to prevent, and the opposite of what this type's own documentation claimed it did.
        //
        // The plate is I2's merged surface and is deliberately left alone; the reduction to one
        // line is this type's job, so the reduction is where the rule lives.
        let wantsAttention = clauses.contains { $0.wantsAttention }

        return Resolved(
            clauses: clauses,
            host: host,
            wantsAttention: wantsAttention,
            isSelectable: install != nil
        )
    }

    /// Map one plate line onto its short clause.
    ///
    /// Exhaustive over `DiscoverCopy.PlateKey`, so the compiler is what keeps the two in step.
    /// `invocationLabel` is a plate-only key — it labels the mono evidence block, which a one-line
    /// row does not carry — and it is named here rather than swept into a `default`, because a
    /// `default` is what would silently absorb a future security clause.
    private static func clause(for line: CapabilityPlate.Line) -> Clause? {
        guard case let .plate(key) = line.copyKey else { return nil }
        switch key {
        case .stdio: return .runsLocally
        case .remote: return .remote
        case .unknownHost: return .remoteUnknownHost
        case .credential: return .credential
        case .credentialSmithery: return .credentialSmithery
        case .archived: return .archived
        case .noInstall: return .noInstall
        case .invocationLabel: return nil
        }
    }
}
