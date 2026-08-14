import MCPRouterKit
import SwiftUI

/// What the phone shows when it cannot open its own storage.
///
/// **This exists so the app has somewhere to put a failure it would otherwise have to swallow.**
/// `FileCapabilityQueueWriter.defaultDirectory()` throws, and the obvious handling — `try?` with an
/// in-memory fallback — would produce an app that looks entirely normal and forgets everything the
/// user queues at the next launch. That is the same shape as I1's swallowed Keychain error, which
/// rendered "Paired." while nothing had been written.
///
/// So the failure gets a surface. It states what happened, what it means, and what to do
/// (`DESIGN.md` §6), and it carries the narrowing because a screen that says the app is broken is
/// exactly where a reader might wonder what it had been doing to their Mac.
public struct StorageUnavailableView: View {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var body: some View {
        let entry = QueueCopy.entry(.state(.storageUnavailable))

        VStack(spacing: PhoneMetric.normal) {
            IconView(.warn, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(ColorToken.fail.color)
                .accessibilityHidden(true)

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .multilineTextAlignment(.center)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The underlying reason, in the instrument voice. It is a system message rather than a
            // sentence written for this screen, and rendering it as prose would misrepresent it.
            Text(reason)
                .typeRole(.caption, monospaced: true)
                .foregroundStyle(ColorToken.t3.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(PairingCopy.neverInstalls)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PhoneMetric.snug)
        }
        .padding(.horizontal, PhoneMetric.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorToken.ground.color)
    }
}
