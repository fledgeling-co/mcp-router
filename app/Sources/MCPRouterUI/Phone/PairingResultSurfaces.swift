import MCPRouterKit
import SwiftUI

/// Picks a button style at runtime.
///
/// SwiftUI's `buttonStyle` takes a concrete type, so a conditional between two styles cannot be
/// written inline without this. It exists because §3.4 allows exactly one prominent action per view
/// and the refusal pane deliberately is not it.
struct AnyPhoneButton: ButtonStyle {
    enum Kind { case prominent, standard }
    private let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .prominent: PhoneProminentButtonStyle().makeBody(configuration: configuration)
            case .standard: PhoneStandardButtonStyle().makeBody(configuration: configuration)
            }
        }
    }
}

/// Paired. A tick and a sentence, proportional to what happened.
///
/// The narrowing is restated here, at the one moment the user is actually thinking about what they
/// just granted. `DESIGN.md` §9: pairing hands a remote party the ability to put executable code on
/// a laptop, and this app's answer is that it queues and never installs — which is worth saying
/// again exactly when permission changes hands.
struct PairedSuccessView: View {
    let mac: PairedMac
    let onDone: () -> Void

    var body: some View {
        let entry = PairingCopy.entry(.pairedSuccess).resolved(macName: mac.name)

        VStack(alignment: .leading, spacing: PhoneMetric.loose) {
            Spacer(minLength: PhoneMetric.section)

            // Deliberately `--accent`, not `--live`. `DESIGN.md` §2 gives the three indicator hues
            // exclusive meanings — `--live` is "a child process is running" — and §11 already names
            // a decorative `--live` in the prototype as a defect. A confirmation mark reports that
            // an interaction completed, not that a process is up; the connection banner directly
            // below carries the process state, in `--live`, where it is genuinely observed.
            IconView(.check, size: PhoneMetric.successMark, weight: .semibold)
                .foregroundStyle(ColorToken.accent.color)
                .accessibilityHidden(true)

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)

            PhoneNoticeList(
                entry: PairingCopy.Entry(
                    headline: PairingCopy.entry(.pairedCapabilities).headline,
                    body: PairingCopy.neverInstalls
                ),
                tone: .neutral,
                glyph: .shield
            )

            Button(entry.actionLabel ?? "Done", action: onDone)
                .buttonStyle(PhoneProminentButtonStyle())
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
