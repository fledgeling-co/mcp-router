import Foundation

/// The inbox's presence in the menu-bar popover, as one value.
///
/// The same device `PopoverContent.band` uses, applied to the second thing in this app that wants a
/// human decision: **the whole band is an optional and is `nil`, never a band of zero rows.** A view
/// test cannot tell a hidden band from a band rendering nothing — both draw nothing — so the
/// absent-versus-empty distinction lives in the type where a unit test can see it.
///
/// The band exists to make a queued item reachable **without opening the window**, which is the
/// whole of `D-m6-d`. It is a glance, not the board: it caps its rows, states the true total in its
/// header line, and routes to `⌘5` for the rest.
public struct InboxBand: Equatable, Sendable {
    /// The header line, taken verbatim from `InboxCopy.subtitle` — the same function the pane's
    /// subtitle calls.
    ///
    /// `DESIGN.md` §6 asks for one name per state, from one source rather than spelled twice. The
    /// popover and the pane are two surfaces describing one queue, and a second phrasing here is how
    /// they come to disagree about it.
    public let headline: String

    /// The rows actually drawn, **oldest first**, capped at ``MenuBarPresentation/inboxBandLimit``.
    public let rows: [Row]

    /// How many are waiting beyond the rows drawn. Zero when everything fits.
    public let overflow: Int

    /// What the last disposition was, reported in place under the band with its undo affordance
    /// where it has one. `nil` when nothing has been acted on.
    public let report: Report?

    public init(headline: String, rows: [Row], overflow: Int, report: Report? = nil) {
        self.headline = headline
        self.rows = rows
        self.overflow = overflow
        self.report = report
    }

    /// One queued item, already formatted. The view places these; it does not compute them.
    public struct Row: Equatable, Sendable, Identifiable {
        /// The envelope's id — minted by the phone, stable across snapshots, and what every route
        /// and every withdrawal is keyed on.
        public let id: String
        public let title: String
        /// `queued 2m ago · Luke's iPhone`.
        public let provenance: String
        /// The capability headline the **Mac** derived, or `nil` for an item whose entry it could
        /// not read.
        ///
        /// Never a string the phone sent. That is the security property the whole envelope design
        /// turns on: the phone names *which* entry it means and the Mac reads what that entry does.
        public let capability: String?
        /// True when the registry entry could not be read. Such a row can be declined and cannot be
        /// reviewed into an install — `AcceptableInboxItem` cannot be constructed for it.
        public let isPartial: Bool

        /// Whether the row carries a review affordance at all.
        ///
        /// **The band read this off nothing and drew the affordance anyway.** A partial row was a
        /// full-width Review button that opened a sheet which could never install, because the
        /// entry it would install was the thing that could not be read. `DESIGN.md`'s Disabled state
        /// and `spec-I6.md` §"The states" both say a row that could not be read *carries no review
        /// affordance and says why* — a control that cannot do what it offers is worse than an
        /// absent one, because the absent one is not a promise.
        ///
        /// Its own property rather than `!isPartial` read at the call site, so the view states which
        /// rule it is obeying and a clause has a subject.
        public var isReviewable: Bool { !isPartial }

        /// Whether this row may be installed from the band itself, without opening the window.
        ///
        /// **Three conditions, and `isReviewable` is only the first of them.** Kept distinct from
        /// reviewing rather than derived from it, because the two answer different questions:
        /// reviewing shows what an item would run, and approving runs it. Collapsing them is how an
        /// `Approve` button appears on a row whose entry nobody could read.
        ///
        /// 1. The entry resolved (``isReviewable``). Nothing can be declared from a name this Mac
        ///    could not look up.
        /// 2. The Settings preference is on. The popover's install path is the one gate-removing
        ///    control in this product that a person can switch off, and `spec-M20.md` §1 asks for it
        ///    to be switchable rather than absolute.
        /// 3. **Nothing the entry asks for is still blank.** The band has no fields, so an entry
        ///    with unmet requirements has no way to be given them here — and
        ///    `RegistryCapability.action` already records what happens when that gate is missing:
        ///    *"reveal the fields, press Add with every box empty, and a credential-less declaration
        ///    reached the router — which then fails at runtime with an authentication error naming
        ///    nothing."* `RegistryCapability.declaration(for:values:)` does not refuse such an
        ///    entry — it drops the empty values and sends the rest — so the refusal has to be here.
        ///    Such a row keeps `Review…`, which is where the fields are.
        ///
        /// `plan-M20.md` step 12 names the first two conditions; the third is this build's addition
        /// and the reason is above.
        public let isApprovable: Bool

        public init(
            id: String,
            title: String,
            provenance: String,
            capability: String?,
            isPartial: Bool,
            isApprovable: Bool = false
        ) {
            self.id = id
            self.title = title
            self.provenance = provenance
            self.capability = capability
            self.isPartial = isPartial
            self.isApprovable = isApprovable
        }
    }

    /// The in-place report of the last disposition. `DESIGN.md` §5: macOS does not toast a click, so
    /// this is a quiet line under the band rather than a notification of our own.
    public struct Report: Equatable, Sendable {
        public let sentence: String
        /// Whether an `Undo` control is drawn beside it.
        ///
        /// **False for an accept**, and that is a fix rather than an omission: M6's Phase D critic
        /// found an "Undo" that restored the row and left the server installed. Declining is
        /// reversible; installing is reversed on Servers, and `InboxCopy.accepted` says so.
        public let isUndoable: Bool

        public init(sentence: String, isUndoable: Bool) {
            self.sentence = sentence
            self.isUndoable = isUndoable
        }
    }

    // MARK: - Building one

    /// Compose the band from the rows the board is currently showing.
    ///
    /// One function, so the popover cannot assemble the band a second way, and so every state clause
    /// is a call to it with constructed inputs rather than a running app.
    ///
    /// - Parameters:
    ///   - waiting: everything still waiting, in whatever order the board holds it. Ordering is this
    ///     function's job, not the caller's.
    ///   - device: the paired device, or `nil` when nothing is paired.
    ///   - report: the last disposition, already worded.
    ///   - approveFromPopover: whether the Settings preference permitting an install from this band
    ///     is on. **Defaults to `false`**, so a caller written before the preference existed — or one
    ///     that forgets to thread it — draws no `Approve`. The default that fails closed is the one
    ///     that cannot ship an install path by omission.
    ///   - now: the instant the relative ages are measured from.
    /// - Returns: `nil` when nothing is waiting — **absent, not empty**.
    public static func make(
        waiting: [InboxItem],
        device: String?,
        report: Report? = nil,
        approveFromPopover: Bool = false,
        now: Date
    ) -> InboxBand? {
        guard !waiting.isEmpty else { return nil }

        // **Oldest first, which is the opposite of the pane, and deliberately so.**
        //
        // Two reasons, and the second is the load-bearing one. A band is a queue you drain from the
        // front, so newest-first would put the item that just arrived permanently at the top and the
        // oldest one permanently out of reach. And newest-first inserts an arrival at index 0, which
        // pushes every row down one **while the popover is open** — a mis-press waiting for someone
        // who was reaching for Decline. Oldest-first makes an arrival append, so nothing already on
        // screen moves.
        let ordered = waiting.sorted { $0.envelope.queuedAt < $1.envelope.queuedAt }
        let shown = ordered.prefix(MenuBarPresentation.inboxBandLimit)

        return InboxBand(
            headline: InboxCopy.subtitle(waiting: ordered.count, device: device),
            rows: shown.map { row(for: $0, approveFromPopover: approveFromPopover, now: now) },
            overflow: ordered.count - shown.count,
            report: report
        )
    }

    private static func row(for item: InboxItem, approveFromPopover: Bool, now: Date) -> Row {
        Row(
            id: item.id,
            title: item.title,
            provenance: InboxCopy.provenance(
                queued: shortAgo(item.envelope.queuedAt, from: now),
                device: item.envelope.deviceName
            ),
            // Derived by this Mac from the entry it resolved, never read off the envelope.
            capability: item.resolved.map { RegistryCapability.statement(for: $0).headline },
            isPartial: item.isPartial,
            isApprovable: approveFromPopover && canApprove(item)
        )
    }

    /// Whether this item could be installed with nothing typed in.
    ///
    /// The third condition of ``Row/isApprovable``, in one function so the band and the shell's own
    /// route ask the same question of the same item rather than each deciding it. `nil` resolved is
    /// refused first, so the requirement check reads a real entry.
    public static func canApprove(_ item: InboxItem) -> Bool {
        guard let entry = item.resolved else { return false }
        return RegistryCapability.missingRequirements(for: entry, values: [:]).isEmpty
    }
}
