import Foundation

/// How much friction each destructive decision gets, and which sheet carries it.
///
/// The brief's rule is *"friction scales with blast radius"*, and the failure it names is one
/// feedback mechanism serving every action — *"a three-second toast behind a command that stops
/// every job on the host"*. So the table is data rather than a habit spread across six files, and
/// **the boards route through it**: a model's `request(_:)` asks this type what gate an action
/// gets and opens that sheet, so a destructive path that skips the gate is a call site that does
/// not exist rather than one no test happens to cover.
///
/// That routing is the point. An earlier reading of this had `SheetGate` as a lookup table nobody
/// consulted, which the out-of-family plan review named exactly: its tests would have passed at
/// full green while a button called `remove(name)` directly, because the table would have been
/// asserted only against itself.
///
/// **There is no transient case on `Gate`, and there is no toast anywhere in this app** — the word
/// appears fifteen times in `app/Sources` and every one is a comment saying macOS does not toast a
/// click. So the brief's *"no destructive action's gate resolves to a transient message"* is
/// structural here rather than tested. The assertion that can actually fail is that nothing above
/// a one-child blast radius is `ungated`, which is what a later downgrade would trip.
public enum SheetGate {
    /// The brief's seven rows, plus one of the build's own.
    public enum Action: String, CaseIterable, Sendable {
        case reconcileHarnessConfig
        case removeInstalledCapability
        case acceptHeldChanges
        case disableServer
        case tripBreakerOrWake
        case approveQueuedInstall
        case stopRouter
        /// **The build's eighth row, which the brief's table does not have.**
        ///
        /// Added rather than omitted: forgetting the call record is destructive, it is irreversible,
        /// it is drawn twice (Activity and Cleanup), and a gate table that skipped it would be an
        /// inventory with a hole in exactly the place this item exists to close.
        case resetCallHistory
    }

    /// What the action touches. `Comparable` by reach, so "nothing above one child process is
    /// ungated" is expressible rather than a list somebody has to keep in step.
    public enum BlastRadius: String, CaseIterable, Sendable, Comparable {
        case oneChildProcess
        case oneServer
        case installedCapability
        case someoneElsesFile
        case executableCodeOnThisMac
        case everySessionOnThisMac

        private var reach: Int {
            switch self {
            case .oneChildProcess: 0
            case .oneServer: 1
            case .installedCapability: 2
            case .someoneElsesFile: 3
            case .executableCodeOnThisMac: 4
            case .everySessionOnThisMac: 5
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.reach < rhs.reach }
    }

    /// The four gate shapes the brief's table actually uses.
    public enum Gate: Equatable, Sendable {
        /// Reversible in one press with the state visible. `DESIGN.md` §9: undo over confirm.
        ///
        /// Named `ungated` rather than `none` so it cannot be confused with `Optional.none` at a
        /// call site that stores a `Gate?`.
        case ungated(reason: String)
        /// The decision and its evidence, on a sheet.
        case sheet(RouterSheet.Kind)
        /// No sheet, but the control is a quiet destructive text button and never the primary.
        case quietDestructiveControl
        /// A menu item. `accelerator: nil` is the brief's requirement for Stop Router, not an
        /// omission — a chord on the command that ends every session is how it gets pressed.
        case menuItem(accelerator: String?)
    }

    public static func radius(for action: Action) -> BlastRadius {
        switch action {
        case .reconcileHarnessConfig: .someoneElsesFile
        case .removeInstalledCapability: .installedCapability
        case .acceptHeldChanges: .oneServer
        case .disableServer: .oneServer
        case .tripBreakerOrWake: .oneChildProcess
        case .approveQueuedInstall: .executableCodeOnThisMac
        case .stopRouter: .everySessionOnThisMac
        case .resetCallHistory: .installedCapability
        }
    }

    public static func gate(for action: Action) -> Gate {
        switch action {
        case .reconcileHarnessConfig: .sheet(.reconcile)
        case .removeInstalledCapability: .sheet(.confirmRemove)
        case .acceptHeldChanges: .sheet(.quarantine)
        case .disableServer: .quietDestructiveControl
        case .tripBreakerOrWake:
            .ungated(reason: "Reversible in one press, and the breaker's state is on the row.")
        case .approveQueuedInstall: .sheet(.queuedDetail)
        case .stopRouter: .menuItem(accelerator: nil)
        case .resetCallHistory: .sheet(.resetHistory)
        }
    }

    /// Whether this app can actually perform the action, and who closes it if not.
    ///
    /// Three of the eight are not built, and each was measured rather than assumed. The
    /// distinction between `owned` and `unclaimed` is the one worth keeping: a row an item will
    /// build is a schedule, and a row nobody has claimed is a finding.
    public enum Availability: Equatable, Sendable {
        case built
        /// An item on the ledger will build it.
        case owned(String)
        /// Not built, and no item claims it. The string says what is missing.
        case unclaimed(reason: String)
    }

    public static func availability(for action: Action) -> Availability {
        switch action {
        // The Harnesses board does not exist, so there is nothing to reconcile from.
        case .reconcileHarnessConfig: .owned("M22")
        // `MenuCommand` declares six menus and none of them is a Router menu, so there is nowhere
        // to put an item that has to be a menu item.
        case .stopRouter: .owned("M20")
        // No disable operation exists on the control API: `ServerPatch` carries `projects`,
        // `warm`, `idleMs` and `placard`, and nothing that stops a server answering. The mock
        // draws the button — `Disable mobbin`, in the quarantine sheet — and no ledger item claims
        // it. Recorded so the absence is visible rather than reading as built.
        case .disableServer:
            .unclaimed(reason: "No disable operation on the control API; ServerPatch has no such field.")
        case .removeInstalledCapability, .acceptHeldChanges, .tripBreakerOrWake,
             .approveQueuedInstall, .resetCallHistory:
            .built
        }
    }
}
