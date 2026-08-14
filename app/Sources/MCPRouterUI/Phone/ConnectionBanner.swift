import MCPRouterKit
import SwiftUI

/// Whether anything you send will arrive, stated before you commit to sending it.
///
/// **The colour choice here is the one the out-of-family review corrected, and it is worth stating
/// rather than leaving in the diff.** `DESIGN.md` §2 gives `--attn` exactly one meaning — "wants a
/// human decision" — and an unreachable Mac wants no decision: it recovers on its own and the queued
/// work sends itself when it returns. Painting it amber spends an exclusive indicator hue on a
/// state that is merely informational, which is the decorative use §2 forbids. So not-reachable is
/// **neutral**, and only reachable takes an indicator colour, because a reachable Mac genuinely has
/// the router process running, which is what `--live` means.
///
/// Colour is never the only signal: each state also has its own words, and the dot is accompanied
/// by text that says the same thing.
public struct ConnectionBanner: View {
    private let state: ConnectionState
    private let macName: String?

    public init(_ state: ConnectionState, macName: String? = nil) {
        self.state = state
        self.macName = macName
    }

    /// The dot's colour. Reachable is `--live`; the other two are label tiers, not indicators.
    private var dotColor: ColorToken {
        switch state {
        case .reachable: .live
        case .notReachable: .t3
        case .neverPaired: .t4
        }
    }

    private var fill: ColorToken {
        state == .reachable ? .f2 : .f3
    }

    /// What the banner says. One vocabulary, reused wherever sending is offered.
    var message: String {
        let name = macName ?? "your Mac"
        switch state {
        case .reachable:
            return "\(name) — items you send arrive now."
        case .notReachable:
            return "Can't reach \(name). Anything you send waits here until it's back."
        case .neverPaired:
            return "No Mac paired. Pair one to send anything."
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PhoneMetric.snug) {
            Circle()
                .fill(dotColor.color)
                .frame(width: PhoneMetric.dot, height: PhoneMetric.dot)
                // The dot repeats what the text says, so it is decoration to a screen reader.
                .accessibilityHidden(true)

            Text(message)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, PhoneMetric.normal)
        .padding(.vertical, PhoneMetric.snug)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(fill.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .strokeBorder(ColorToken.line.color, lineWidth: PhoneMetric.hairline)
        )
        // The banner is one statement, so it is one accessibility element rather than a dot and a
        // sentence read separately.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// A commit control on a surface that offers to send, with the reason it cannot sitting above it.
///
/// I1 ships no sending surface of its own — Queue is I3's — so this is the component and its
/// behaviour, tested here, and wired there. It exists in this item because the brief's requirement
/// is about *this* behaviour: "a phone that silently fails to send is worse than one that says it
/// cannot", which means the refusal has to happen **before** the tap, not after it.
///
/// The disabled control and the waiting copy are not in tension, and both are shown together on
/// purpose: the button that sends *now* is disabled, and the note says the queued items go on their
/// own when the Mac comes back. A user who sees only the disabled button concludes their work is
/// stuck.
public struct SendCommitBar: View {
    private let state: ConnectionState
    private let macName: String?
    private let itemCount: Int
    private let action: () -> Void

    public init(
        state: ConnectionState,
        macName: String?,
        itemCount: Int,
        action: @escaping () -> Void = {}
    ) {
        self.state = state
        self.macName = macName
        self.itemCount = itemCount
        self.action = action
    }

    /// Verb-first, and it names what it will do — `DESIGN.md` §6.
    var commitLabel: String { "Send \(itemCount) to Mac" }

    /// Why the commit is unavailable, or nil when it is available.
    var blockedReason: String? {
        guard state != .reachable else { return nil }
        let entry = PairingCopy.entry(.sendingBlocked).resolved(macName: macName)
        guard let headline = entry.headline else { return entry.body }
        return "\(headline) \(waitingClause)"
    }

    private var waitingClause: String {
        itemCount == 1 ? "One item is waiting to go." : "\(itemCount) items are waiting to go."
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            if let blockedReason {
                Text(blockedReason)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(commitLabel, action: action)
                .buttonStyle(ProminentButtonStyle())
                .disabled(!state.canSend)
                .frame(minHeight: PhoneMetric.minimumTarget)
                .frame(maxWidth: .infinity)

            if !state.canSend {
                // Said after the button as well, because the disabled control is the thing that
                // looks like a dead end and this is the sentence that says it is not one.
                Text(PairingCopy.entry(.sendingBlocked).body)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
