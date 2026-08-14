import MCPRouterKit
import SwiftUI

/// The one commit this feature offers: sending a capability to the Mac for review.
///
/// **There is no install action here, and there is no second one.** `DESIGN.md` §9: pairing grants
/// a remote party the ability to put executable code on a laptop, so the phone's commit sends items
/// to the Mac's inbox for review. That is narrower than remote install and deliberately so, and
/// every one of the seven states below carries `PairingCopy.neverInstalls` verbatim (A20).
struct QueueCommitBar: View {
    let state: CommitState
    let entry: DiscoverCopy.Entry
    /// Surfaced rather than swallowed. A refused write must render as a failure and never as a
    /// queued item — I1's `PairingStorageFailureTests` is the precedent, where a `try?` made a
    /// refused Keychain write render as paired.
    let failure: CapabilityQueueError?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            // The reason sits **above** the control and is present whether or not it is dimmed,
            // because `DESIGN.md` §3.4 asks a disabled control to dim in place with a discoverable
            // reason — and a reason that only appears once the control is dead is not discoverable.
            Text(entry.body)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let failure {
                Text(failureText(failure))
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.fail.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(entry.actionLabel ?? "") { action() }
                .buttonStyle(PhoneProminentButtonStyle())
                // Dims in place, never hidden. Disabled for exactly two states — no Mac paired,
                // and no install descriptor (A17) — plus the three already-committed states, which
                // are dimmed because there is nothing left to do rather than because the act is
                // refused.
                .disabled(!state.isActionable)
                .frame(maxWidth: .infinity, minHeight: PhoneMetric.minimumTarget)

            // The narrowing, once, in the words `PairingCopy` owns. One constant rather than a
            // paraphrase per surface: three paraphrases of a permission boundary is how a user
            // ends up believing the loosest one.
            Text(PairingCopy.neverInstalls)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PhoneMetric.loose)
        .background(ColorToken.panel.color)
    }

    /// The write failed. States what happened and what to do, next to the thing that failed, and
    /// does not blame or emote (`DESIGN.md` §6, `SWIFT_PRACTICES.md` §3).
    private func failureText(_ failure: CapabilityQueueError) -> String {
        switch failure {
        case .unreadable:
            "This phone's queue couldn't be read, so nothing was saved. Try again."
        case .writeFailed:
            "This phone couldn't save the item, so nothing was queued. Try again."
        }
    }
}
