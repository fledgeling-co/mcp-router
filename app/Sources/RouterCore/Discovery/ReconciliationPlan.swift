import Foundation

/// What a fix would change in one harness's config — named, rendered, and applied by nothing.
///
/// **This is the seam, and it is deliberately inert.** There is no `apply`, no writer protocol and
/// no conformer anywhere in `app/Sources`; `scripts/lint/no-harness-config-writes.sh` fails the
/// build if one appears. Spec §7 carries the two reasons: the configs on a developer's machine are
/// live working state, and the brief's own framing is that config *writing* is the easy half —
/// the diff is the product.
public struct ReconciliationPlan: Sendable, Hashable {
    public let client: MCPClient
    public let path: String
    /// Harness entry names to delete, in the harness's own declaration order.
    public let remove: [String]
    /// The router entry to add, when the harness has none. Nil when it is already wired.
    public let addRouterEntry: String?
    /// The shim entry to replace with a direct HTTP one, when there is one to replace.
    public let replaceShim: String?

    public init(
        client: MCPClient, path: String, remove: [String], addRouterEntry: String?, replaceShim: String?
    ) {
        self.client = client
        self.path = path
        self.remove = remove
        self.addRouterEntry = addRouterEntry
        self.replaceShim = replaceShim
    }

    public var isEmpty: Bool {
        remove.isEmpty && addRouterEntry == nil && replaceShim == nil
    }

    /// A diff a person reads before deciding, not a patch a program applies. Deliberately not
    /// unified-diff format: this names entries rather than lines, and a format that looks
    /// machine-applicable invites somebody to apply it.
    public func render() -> String {
        guard !isEmpty else { return "\(client.displayName): nothing to reconcile\n" }
        var text = "\(client.displayName) — \(path)\n"
        for name in remove {
            text += "  - remove  \(name)   (the router already serves it)\n"
        }
        if let replaceShim {
            text += "  ~ replace \(replaceShim)   (stdio shim -> direct HTTP)\n"
        }
        if let addRouterEntry {
            text += "  + add     \(addRouterEntry)   (this router's endpoint)\n"
        }
        text += "  nothing applies this plan — see planning/specs/spec-R7.md §7\n"
        return text
    }

    /// Derive the plan from a report. The router entry is named `mcp-router` when one has to be
    /// added, matching what `install-entry` writes into `~/.claude.json`.
    public static func from(
        _ report: HarnessReport, routerEntryName: String = "mcp-router"
    ) -> ReconciliationPlan {
        // An unread file is not an empty one, and this distinction cost a wrong answer before it
        // was drawn. `~/.grok/config.toml` failed the TOML reader on an unrelated section, arrived
        // here as `.notWired` with no entries, and produced a plan offering to add a router entry
        // to a harness that was already wired via HTTP. Absence of evidence proposes nothing.
        guard report.exists, report.unreadable == nil else {
            return ReconciliationPlan(
                client: report.client, path: report.path,
                remove: [], addRouterEntry: nil, replaceShim: nil
            )
        }
        var add: String?
        var replace: String?
        switch report.route {
        case .notWired:
            add = report.exists ? routerEntryName : nil
        case .directHTTP:
            break
        case let .stdioShim(name, _, _):
            // Only offered where the harness is known to have somewhere to move to. On `.unknown`
            // the report's remedy asks the question instead, and this plan does not pretend to
            // know the answer.
            replace = report.capability.isEstablished ? name : nil
        }
        return ReconciliationPlan(
            client: report.client,
            path: report.path,
            remove: report.duplicates.map(\.harnessName),
            addRouterEntry: add,
            replaceShim: replace
        )
    }
}
