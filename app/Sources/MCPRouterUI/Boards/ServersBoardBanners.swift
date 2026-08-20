#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    // MARK: - The two banners and the failure pane

    /// Partial, in `DESIGN.md` §5's sense: what arrived, what did not, and the reason.
    ///
    /// F4's `.stale` exists so this can be drawn without either throwing away good data to show a
    /// failure or hiding a failure to keep the data. Both of those are wrong, and a stale snapshot
    /// under a live error is the most common real condition of the four.
    ///
    /// **A router that was running and has stopped lands here, not on the Offline pane**, because
    /// `.failed` means nothing ever loaded — which is only true of an app launched against a dead
    /// router. That is the ordinary case rather than an edge one, so the banner takes its whole
    /// wording *and its action* from the error, which means `routerNotRunning` still says "The
    /// router isn't running" and still offers "Start the router" here. `SWIFT_PRACTICES.md` §3 asks
    /// for that state to be rendered as itself on every surface and never as a generic banner, and
    /// this is how a surface that still has rows to show honours it.
    ///
    /// The copy deliberately does not call the rows a snapshot. `ServerStateTracker` records that
    /// stale servers are the last poll **as corrected by any call records seen since**, so "as of
    /// {time}" would overstate what is on screen.
    struct StaleReadingBanner: View {
        let error: ControlAPIError

        var body: some View {
            Banner(icon: error == .routerNotRunning ? .bolt : .warn, tint: .attention) {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                    Text(
                        """
                        \(error.headline). These servers are the last reading the router gave, kept \
                        rather than cleared. Nothing about them is current. \(error.advice)
                        """
                    )
                    // The offer exists and is dimmed with its reason, rather than being a button
                    // that does nothing. See `ServersBoardModel.cannotStartRouterReason`.
                    if let label = error.actionLabel {
                        DisabledAction(
                            label: label,
                            reason: ServersBoardModel.cannotStartRouterReason
                        )
                    }
                }
            }
        }
    }

    /// A server whose index failed contributes zero tools to the header's total, so the total
    /// genuinely understates. Saying so is the whole of §5's Partial rule.
    struct PartialIndexNote: View {
        let text: String

        var body: some View {
            Banner(icon: .warn, tint: .attention) { Text(text) }
        }
    }

    struct Banner<Content: View>: View {
        let icon: Icon
        let tint: ColorToken
        @ViewBuilder let content: Content

        var body: some View {
            HStack(alignment: .top, spacing: ServersBoardMetrics.gap) {
                IconView(icon, size: TypeToken.body.size)
                    .foregroundStyle(tint.color)
                content
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(ServersBoardMetrics.rowPadding)
            .background(
                RoundedRectangle(
                    cornerRadius: MetricToken.selectionRadius.leadingScalar,
                    style: .continuous
                )
                .fill(ColorToken.f3.color)
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// The Offline and Error panes, both from `ControlAPIError`'s own three strings.
    ///
    /// One source rather than two wordings: `DESIGN.md` §6 asks for one name per state, and F3's
    /// `ControlCopyTests` already pins these against the connection-states mock. A second set of
    /// strings written here would be the surface and the client disagreeing about the same
    /// condition.
    struct ConnectionFailurePane: View {
        let error: ControlAPIError

        var body: some View {
            VStack(spacing: ServersBoardMetrics.gap) {
                MessageState(
                    // The action is deliberately withheld from `MessageState`, which would render it
                    // as an enabled prominent button. This board cannot start a daemon — nothing in
                    // this repo can yet — so the offer is shown dimmed with its reason instead
                    // (§3.4: disabled dims in place with a discoverable reason and never
                    // disappears). A button that looks live and does nothing is the worse failure.
                    StateMessage(title: error.headline, detail: error.advice, actionLabel: nil),
                    icon: error == .routerNotRunning ? .bolt : .bang,
                    tint: error == .routerNotRunning ? .attention : .fail
                )
                if let label = error.actionLabel {
                    DisabledAction(label: label, reason: ServersBoardModel.cannotStartRouterReason)
                        .measured(
                            "failure-action", role: "state-action-disabled", kind: .leaf,
                            type: .body, text: label
                        )
                }
            }
            .measured("failure-pane", role: "state-container", kind: .vstack)
        }
    }

#endif
