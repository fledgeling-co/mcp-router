#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Activity's one dialog: discard the recorded call history.
    ///
    /// **Every string is `CleanupPresentation`'s, by call and never by copy.** Two boards offer this
    /// act — `prototype.html:716` in Activity's header and `:930` in Cleanup's — and `DESIGN.md` §6
    /// wants one wording per state across the app. Duplicating the literals here would be the two
    /// boards telling the user different things about the same irreversible act, which is the shape
    /// DEF-012 already found twice in this build.
    ///
    /// Cancel leads and the consequence is named, per `DESIGN.md` §9's escalation clause: `POST
    /// /usage/reset` has no restore, and it also moves the observation window every reading on the
    /// Cleanup board is measured against.
    struct ActivityResetHistorySheet: View {
        @Bindable var model: ActivityModel

        var body: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.gap * 2) {
                Text(CleanupPresentation.resetTitle)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)

                // `window: nil` is a fact, not a gap. Cleanup passes the span it judges over;
                // Activity judges nothing and holds a rolling feed, so the sentence reads "recorded
                // so far", which is what this board can actually vouch for.
                Text(
                    CleanupPresentation.resetConsequence(
                        calls: model.records?.count,
                        window: nil
                    )
                )
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

                if let error = model.writeError {
                    Text(error.userFacingDescription)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.fail.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Cancel") { model.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button(CleanupPresentation.resetConfirm) {
                        Task { await model.resetHistory() }
                    }
                    .buttonStyle(StandardButtonStyle())
                }
            }
            .padding(M7BoardMetrics.panePadding)
            .frame(width: M7BoardMetrics.sheetWidth)
        }
    }
#endif
