import Foundation

/// Every word the Harnesses board says.
///
/// In the kit rather than in the view because `DESIGN.md` §6 asks for one name per state taken
/// from one source, and because a string in a `body` is a string no test can reach.
public enum HarnessBoardCopy {
    public static let title = "Harnesses"
    public static let subtitle = """
    Which AI tools on this Mac actually route through here. Pointing a harness at the endpoint is \
    the easy half; the half that saves anything is noticing it still spawns its own copies.
    """

    public static let sectionDetected = "Detected on this Mac"
    /// The design of record's own word. It read `Check again` for one draft, which is a
    /// second spelling of a control the mock already names — exactly what §6's "one name per
    /// state, taken from one source" rules out, and the fidelity ledger read it as a
    /// divergence rather than as a preference.
    public static let rescan = "Rescan"
    public static let openConfig = "Reveal config in Finder"
    public static let reconcile = "Reconcile…"
    public static let explainShim = "Why a shim?"

    public static let reconcileAll = "Reconcile all…"

    /// What "reconcile" opens, said before it opens. `…` because it opens a further view (§3.4),
    /// and the sentence because a diff of somebody's live configuration is not a click you make
    /// without knowing it is a diff.
    public static let reconcileHelp = """
    Shows the difference against the real file. Nothing is written until you say so.
    """

    /// Why the reconcile controls are dim.
    ///
    /// **Dim rather than absent**, per `DESIGN.md` §3.4: a disabled control dims in place with a
    /// discoverable reason and never disappears. The panel is M18's — this board is one of the two
    /// surfaces it opens from — and a button that set a state nothing presented was the worse of
    /// the two options, because it looked like it worked.
    public static let reconcileUnavailable = """
    The panel that shows the difference isn't built yet, so nothing here can be reconciled \
    from this board. Your configuration is untouched either way.
    """

    public static let shimSheetTitle = "Why a shim?"
    public static let shimSheetDismiss = "Done"

    /// The shim explanation. An explanation rather than a fix, because there is no fix on this
    /// side: the transport is the harness's, and this router cannot change it.
    public static func shimExplanation(bridge: String?, capability: HarnessCapabilityProvenance) -> String {
        let name = bridge ?? "a bridge process"
        switch capability {
        case .measured, .documented:
            return """
            This harness speaks streamable HTTP, so \(name) is not the only way in — pointing it \
            straight at the endpoint drops the extra process. Changing that means editing its \
            configuration yourself; this app does not write harness files.
            """
        case .unknown:
            return """
            Nothing here has established whether this harness speaks streamable HTTP, so \(name) \
            may be the only way it can reach the router. That is a cost worth naming rather than \
            a fault to fix, and there is no fix on this side either way.
            """
        }
    }

    /// The finding above the list, when there is one. Nil when nothing is worth saying.
    ///
    /// Phrased as a **count** rather than a judgement, and only ever from figures on the rows it
    /// summarises — a headline is the easiest place in a product to put a number nobody took.
    public static func finding(_ rows: [DetectedHarness]) -> String? {
        let worst = rows
            .filter { $0.unreadable == nil && $0.duplicateCount > 0 }
            .max { $0.duplicateCount < $1.duplicateCount }
        guard let worst else { return nil }
        return "\(worst.displayName) runs \(worst.entries) server"
            + "\(worst.entries == 1 ? "" : "s") of its own, \(worst.duplicateCount) of which this "
            + "router already fronts"
    }

    /// The staleness line. The counts are read from files, so they are only as fresh as the last
    /// read — and the brief's own words are that a stale reading here is worse than no reading.
    public static func readAt(_ timestamp: String, now: Date = Date()) -> String {
        guard let date = timestamp.asControlAPIDate else { return "Read just now" }
        return "Read \(shortAgo(date, from: now)) ago"
    }

    public static let emptyTitle = "No AI harnesses found"
    public static let emptyBody = """
    Nothing on this Mac looks like an agent CLI or editor that speaks MCP. If one is installed \
    somewhere unusual, the router reads the standard configuration paths only.
    """

    public static let unreadableNote = """
    Nothing was written. A file this app cannot read is a file it will not rewrite, so your \
    configuration is exactly as you left it. The other harnesses were read normally and are \
    shown above.
    """

    /// The scope line. Said on the board rather than only in the CLI, because a reader comparing
    /// this against their own project's configuration needs to know it was not consulted.
    public static let scopeNote = """
    Global configuration only — a server declared inside one project is not read here.
    """
}

/// Every word the Insights board says.
public enum InsightsBoardCopy {
    public static let title = "Insights"
    public static let subtitle = """
    What your agents actually used. Every number here is counted from calls this router served \
    or from processes it opened — none of it is modelled.
    """

    public static let childrenLabel = "Child processes running"
    public static let residentLabel = "Resident, all children"
    public static let callsLabel = "Tool calls, last 24 hours"
    public static let failuresLabel = "Failed calls"

    /// The provenance line under the memory figure. The brief asks for it by name, and it is the
    /// difference between a number and a claim.
    public static let residentProvenance = "measured, not modelled"

    /// What stands where the memory figure would be when nothing is running.
    ///
    /// The absence rather than a zero: `residentMb()` omits an upstream with no local process, so
    /// there is no reading to show, and a `0 MB` under a label reading *measured* would be the one
    /// thing that label rules out.
    public static let residentAbsent = "No child is running, so there is nothing to measure"

    /// The two bar fills, named here rather than at the call site so the constraint is checkable
    /// without rendering anything.
    ///
    /// **The text-safe twins, never the published hues.** On the light ground `--live` measures
    /// 2.22:1 and `--attn` 2.31:1, under the 3:1 WCAG 1.4.11 asks of a graphical object; their
    /// inks measure 6.88:1 and 6.51:1. Swift Charts would happily paint the brighter one, and a
    /// bar sitting on a near-white track is exactly the pairing the split exists for.
    public static let callsBarFill: ColorToken = .liveInk
    public static let dutyBarFill: ColorToken = .attentionInk

    public static let callsByHarness = "Where the calls came from"
    public static let callsPerHour = "Calls per hour, last 24 hours"
    public static let dutyCycle = "Duty cycle, per server"
    public static let analyst = "The analyst"
    public static let analyseNow = "Analyse now"

    /// Why the analyst's one action is dim. `PRD.md` §6 specifies a session analyst and nothing in
    /// `app/Sources` implements one, so this is `featureUnbuilt` rather than a surface missing from
    /// this build — and saying which is the difference `CommandAvailability` exists to keep.
    public static let analyseUnavailable = """
    Nothing reads your session logs yet, so there is nothing to run. When something does, \
    this says which model judged and what it found.
    """

    /// The caption under the duty-cycle chart.
    ///
    /// **It states the mechanism and asserts no figure.** The brief's own caption reads *"before
    /// the router, every one of these sat at 100%"*, which is a number describing a world this
    /// router never ran — exactly what `DESIGN.md` §6 forbids, two paragraphs before the brief
    /// says no number here is modelled. Triage accepted the amendment; this is it.
    public static let dutyCycleCaption = """
    The share of wall-clock time each child was alive, since the router started. A server a \
    harness starts for itself has no reaper: it is spawned when the session begins and stays \
    alive until the session ends.
    """

    /// Why a bar can read nothing at all.
    public static let unattributableCaption = """
    A row with no bar is one whose calls the router cannot tell apart from another program's. It \
    sees the process on the other end of the connection, not the harness that started it.
    """

    /// The empty state. A measurement rather than a threshold: with no record in the window there
    /// is nothing to plot, and saying so beats drawing a flat line.
    public static let emptyTitle = "Not enough history yet"
    public static let emptyBody = """
    No calls have been served in the last 24 hours, so these charts would say less than the \
    Activity log already does. They fill themselves as sessions run; there is nothing to set up.
    """
    public static let emptyAction = "Watch the live log instead"

    public static let analystAbsentTitle = "No analyst has run"
    public static let analystAbsentBody = """
    Nothing has read your session logs. When something does, this says which model judged, how \
    much it read and what it found.
    """

    /// The failure rate, with both its numerator and its denominator, because a percentage on its
    /// own is a claim and this is a reading.
    public static func failureRate(_ totals: CallTotals) -> String {
        guard totals.total > 0 else { return "—" }
        let share = Double(totals.failed) / Double(totals.total) * 100
        return String(format: "%.2f%%", share)
    }

    public static func failureProvenance(_ totals: CallTotals) -> String {
        "\(totals.failed) of \(totals.total)"
    }

    /// The share of uptime one server was alive, as a percentage of a denominator the router
    /// reports rather than one this composes.
    public static func share(_ server: DutyCycleServer, of cycle: DutyCycle) -> Double {
        guard cycle.uptimeSeconds > 0 else { return 0 }
        return min(1, Double(server.aliveSeconds) / Double(cycle.uptimeSeconds))
    }
}
