import MCPRouterKit
import SwiftUI

/// The nine states from `DESIGN.md` §5, as containers a surface has to answer for.
///
/// "A populated-only screen is a third of a design, and shipping only the populated state is the
/// most reliable failure in AI-generated UI." The set is an enum rather than a loose collection of
/// views precisely so that a surface switching over it **cannot compile** while ignoring one — a
/// convention would be followed until the first surface in a hurry.
///
/// The copy below is the servers board's, because the servers board is the canonical surface and
/// `DESIGN.md` §5 requires real wording for the unhappy paths rather than placeholders. Placeholder
/// copy hides both layout and comprehension failures: "Error" in a box tells you nothing about
/// whether the real sentence fits or reads.
public enum SurfaceState: String, CaseIterable, Sendable {
    case populated = "Default"
    case empty = "Empty"
    case loading = "Loading"
    case partial = "Partial"
    case error = "Error"
    case success = "Success"
    case offline = "Offline"
    case disabled = "Disabled"
    case overflow = "Overflow"
}

/// What one unhappy state says, and the one thing it offers.
///
/// `DESIGN.md` §6: buttons are verb-first and name the action, errors state what happened *and*
/// how to fix it, next to the thing that failed, without blaming and without emoting.
public struct StateMessage: Sendable, Equatable {
    public let title: String
    public let detail: String
    /// `nil` where the state genuinely offers nothing — never a disabled placeholder button.
    public let actionLabel: String?

    public init(title: String, detail: String, actionLabel: String? = nil) {
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }
}

/// The servers board's real copy, held as data so a test can read it and the gallery can render it.
public enum ServersBoardCopy {
    public static let empty = StateMessage(
        title: "No servers declared yet",
        detail: """
        MCP Router reads the servers your agents already have configured. \
        Point it at a config, or declare one by hand.
        """,
        actionLabel: "Add server…"
    )

    public static let partial = StateMessage(
        title: "6 of 8 servers loaded",
        detail: """
        Two entries name a transport this version does not read. \
        The other six are live and usable.
        """,
        actionLabel: "Show the two"
    )

    public static let error = StateMessage(
        title: "Could not read servers.json",
        detail: """
        The file is there but line 12 is not valid JSON, so nothing was loaded rather than \
        some of it. Fix the line and it will reload on its own.
        """,
        actionLabel: "Reveal in Finder"
    )

    /// The router is loopback, so unreachable never means "the network is down" — it means the
    /// daemon is not running on this machine. `DESIGN.md` §5 and `SWIFT_PRACTICES.md` §3 both
    /// require this to be its own state rather than a generic error banner.
    public static let offline = StateMessage(
        title: "The router is not running",
        detail: """
        Nothing is listening on 127.0.0.1. Your agents will fall back to spawning their own \
        servers until it starts.
        """,
        actionLabel: "Start the router"
    )

    /// Dims in place with a discoverable reason; §3.4 forbids hiding it.
    public static let disabledReason =
        "Available once the server has run at least once. It has not been called yet."

    /// The overflow case needs a name long enough to actually truncate.
    public static let longServerName =
        "anthropic-internal-documentation-and-knowledge-base-retrieval-server"
}

// MARK: - The containers

/// Title, sentence, and at most one action — the shape every unhappy state takes.
///
/// One view rather than four near-identical ones, so the states cannot drift apart in spacing or
/// hierarchy while nobody is comparing them side by side.
public struct MessageState: View {
    private let message: StateMessage
    private let icon: Icon
    private let tint: ColorToken
    private let action: (() -> Void)?

    public init(
        _ message: StateMessage,
        icon: Icon,
        tint: ColorToken = .t3,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        VStack(spacing: MetricToken.selectionInset.leadingScalar * 3) {
            IconView(icon, size: TypeToken.largeTitle.size)
                .foregroundStyle(tint.color)

            VStack(spacing: MetricToken.selectionInset.leadingScalar) {
                Text(message.title)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                Text(message.detail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let label = message.actionLabel {
                Button(label) { action?() }
                    .buttonStyle(ProminentButtonStyle())
            }
        }
        .frame(maxWidth: MetricToken.sidebar.leadingScalar + MetricToken.titlebar.leadingScalar)
        .padding(MetricToken.selectionRadius.leadingScalar * 3)
    }
}

/// The loading state: skeleton rows at the real row geometry.
///
/// `DESIGN.md` §5 — "skeleton matching the real row geometry; never a spinner over a blank pane".
/// The height is read from `MetricToken.serversRow`, the same value the populated board uses, so
/// nothing jumps when the data lands. A spinner over a blank pane tells you the app is busy and
/// nothing about what is arriving.
public struct SkeletonRows: View {
    private let count: Int
    public init(count: Int = 4) {
        self.count = count
    }

    public var body: some View {
        VStack(spacing: 1) {
            ForEach(0 ..< count, id: \.self) { _ in
                HStack(spacing: MetricToken.selectionRadius.leadingScalar) {
                    RoundedRectangle(cornerRadius: BreakerGeometry.standard.housingRadius)
                        .fill(ColorToken.f2.color)
                        .frame(
                            width: BreakerGeometry.standard.housingWidth,
                            height: BreakerGeometry.standard.housingHeight
                        )
                    VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar) {
                        RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                            .fill(ColorToken.f2.color)
                            .frame(width: MetricToken.sidebar.leadingScalar / 2, height: TypeToken.body.size)
                        RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar)
                            .fill(ColorToken.f3.color)
                            .frame(width: MetricToken.sidebar.leadingScalar, height: TypeToken.caption.size)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MetricToken.selectionRadius.leadingScalar)
                .frame(height: MetricToken.serversRow.leadingScalar)
            }
        }
        .accessibilityLabel("Loading servers")
    }
}

/// The overflow case: a long name truncates, and the row height does not move.
///
/// `DESIGN.md` §5 — "long names truncate with the full value in the inspector; rows never change
/// height". The fixed frame is the assertion: without it a long name wraps and the row grows, which
/// is the failure this state exists to rule out.
public struct OverflowRow: View {
    private let name: String
    private let state: BreakerState

    public init(name: String = ServersBoardCopy.longServerName, state: BreakerState = .running) {
        self.name = name
        self.state = state
    }

    public var body: some View {
        HStack(spacing: MetricToken.selectionRadius.leadingScalar) {
            Breaker(state: state)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.accessibilityDescription)
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MetricToken.selectionRadius.leadingScalar)
        .frame(height: MetricToken.serversRow.leadingScalar)
        // The full value is what the inspector would show, and what a screen reader gets.
        .accessibilityLabel(name)
    }
}

/// The disabled case: dimmed where it is, with the reason readable rather than hidden.
public struct DisabledAction: View {
    private let label: String
    private let reason: String

    public init(label: String = "Reset", reason: String = ServersBoardCopy.disabledReason) {
        self.label = label
        self.reason = reason
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar) {
            Button(label) {}
                .buttonStyle(StandardButtonStyle())
                .disabled(true)
            // Helper text is one quiet secondary sentence under its control (§6).
            Text(reason)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHint(reason)
    }
}
