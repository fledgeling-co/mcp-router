import Foundation

/// How far the router could get with one step, if anything applied it.
///
/// R29 settled that the router has two levers and they reach different things: it **tells**
/// (`notifications/tools/list_changed`, no model, no person, measured at 87 ms) and it **asks** (a
/// socket message the receiver enqueues with slash commands disabled). F8 needs a third word,
/// because most of what a profile touches reaches neither: bytes that would persist on disk while
/// no running session is made to re-read them.
///
/// All three cases occur on a real machine, which is what keeps this from being an enum with a
/// branch nothing takes: a skill step is ``durable``, a server step is ``tellElsewhere``, and a step
/// that would need a harness's MCP configuration rewritten is ``refused``.
public enum ProfileReach: Sendable, Hashable {
    /// The bytes would land and stay. Nothing makes a live session re-read them: skills and plugins
    /// have no `list_changed` equivalent, and the socket half only asks.
    case durable(note: String)
    /// The protocol can tell an attached session, and **this binary cannot**. R29's mechanism lives
    /// in `src/livereload.ts`; `app/Sources` has no counterpart, so the reach is reported and not
    /// claimed.
    case tellElsewhere(mechanism: String)
    /// The router will not do this. `spec-R7.md` §7, enforced by
    /// `scripts/lint/no-harness-config-writes.sh`.
    case refused(reason: String)

    public var label: String {
        switch self {
        case .durable: "durable"
        case .tellElsewhere: "tell-elsewhere"
        case .refused: "refused"
        }
    }

    public var detail: String {
        switch self {
        case let .durable(note): note
        case let .tellElsewhere(mechanism): mechanism
        case let .refused(reason): reason
        }
    }
}

/// One thing a profile asks for, against one harness or against the router itself.
public struct ProfileStep: Sendable, Hashable {
    public enum Subject: Sendable, Hashable {
        /// A skill the profile names, against one harness skill root.
        case skill(name: String, root: String)
        /// A server the profile names, against the router's own served set.
        case server(name: String)
        /// A plugin or marketplace the profile names. The router holds these; no harness root
        /// on this machine is a directory of them, so there is nothing to project onto.
        case storeEntry(kind: ExtensionKind, name: String)
    }

    /// What the step would do, if anything applied it.
    public enum Action: Sendable, Hashable {
        /// Already there, in the state the profile asks for.
        case satisfied
        /// The name is not present at the destination.
        case add
        /// The name is present and points at nothing — a repair, not an install.
        case repair(target: String)
        /// The profile names it and the router does not hold it, so there is nothing to project.
        case missingFromStore

        public var label: String {
            switch self {
            case .satisfied: "satisfied"
            case .add: "add"
            case .repair: "repair"
            case .missingFromStore: "missing-from-store"
            }
        }
    }

    public let client: MCPClient?
    public let subject: Subject
    public let action: Action
    public let reach: ProfileReach

    public init(
        client: MCPClient?, subject: Subject, action: Action, reach: ProfileReach
    ) {
        self.client = client
        self.subject = subject
        self.action = action
        self.reach = reach
    }
}

/// What one profile would require, harness by harness — named, rendered, and applied by nothing.
///
/// **The seam is deliberately empty**, exactly as ``ReconciliationPlan``'s is. There is no `apply`,
/// no writer protocol and no conformer anywhere in `app/Sources`, and
/// `scripts/lint/no-harness-skill-writes.sh` fails the build if one appears. `spec-F8.md` §3 gives
/// the two reasons and they are independent: the router does not write another program's tree, and
/// even where it wrote the bytes nothing would make a running session read them.
public struct ProfileProjection: Sendable {
    public let profile: ProfileRecord
    public let steps: [ProfileStep]
    /// Harnesses with no skills directory at all, named rather than silently absent.
    public let withoutSkillRoot: [MCPClient]
    /// Roots that exist and could not be opened, carried separately from an empty one.
    public let unreadableRoots: [String]

    public init(
        profile: ProfileRecord,
        steps: [ProfileStep],
        withoutSkillRoot: [MCPClient],
        unreadableRoots: [String]
    ) {
        self.profile = profile
        self.steps = steps
        self.withoutSkillRoot = withoutSkillRoot
        self.unreadableRoots = unreadableRoots
    }

    public func steps(reaching label: String) -> [ProfileStep] {
        steps.filter { $0.reach.label == label }
    }

    /// A diff a person reads before deciding, not a patch a program applies.
    ///
    /// Deliberately not unified-diff format, for the reason ``ReconciliationPlan/render()`` is not:
    /// this names entries rather than lines, and a format that looks machine-applicable invites
    /// somebody to apply it.
    public func render() -> String {
        var text = "profile \(profile.name) — \(steps.count) step(s)\n"
        for step in steps {
            let destination = step.client?.displayName ?? "this router"
            text += "  \(step.action.label.padding(toLength: 19, withPad: " ", startingAt: 0))"
            text += "\(Self.describe(step.subject))   [\(destination) · \(step.reach.label)]\n"
        }
        for client in withoutSkillRoot {
            text += "  no-skill-root      \(client.displayName)   [nothing to project onto]\n"
        }
        for root in unreadableRoots {
            text += "  unreadable         \(root)   [not the same as empty]\n"
        }
        text += "  nothing applies this projection — see planning/specs/spec-F8.md §3\n"
        return text
    }

    static func describe(_ subject: ProfileStep.Subject) -> String {
        switch subject {
        case let .skill(name, root): "skill \(name) in \(root)"
        case let .server(name): "server \(name)"
        case let .storeEntry(kind, name): "\(kind.singular) \(name)"
        }
    }
}
