import MCPRouterKit
import SwiftUI

/// What queueing this entry would actually mean, drawn above the commit.
///
/// **Never behind a disclosure control.** The brief's rule: the security fact is never behind a tap
/// the user can skip. There is no chevron here, no "show details", no collapsed-by-default section
/// — a fact a user has to ask for is a fact most users never see, and this is the one they are
/// being asked to decide on.
///
/// Every amber line carries its reason **in words**, so colour is never the only signal
/// (`DESIGN.md` §2 and its protan/deuteran argument for keeping `--attn` 39.8° from `--fail`).
struct CapabilityPlateView: View {
    let lines: [CapabilityPlate.Line]
    let invocation: String?

    private var severity: CapabilityPlate.Severity {
        CapabilityPlate.severity(of: lines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.normal) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: PhoneMetric.snug) {
                    IconView(symbol(for: line.kind), size: TypeToken.callout.size)
                        .foregroundStyle(colour(for: line.severity).color)
                        .accessibilityHidden(true)

                    Text(line.text)
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t1.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let invocation {
                VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                    Text(DiscoverCopy.entry(.plateInvocationLabel).body)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)

                    // The literal invocation: the evidence the plain-language lines interpret.
                    // Monospace because it is instrument data (`DESIGN.md` §2), and scrolling
                    // horizontally rather than wrapping because a command broken mid-token reads
                    // as a different command.
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(invocation)
                            .typeRole(.caption, monospaced: true)
                            .foregroundStyle(ColorToken.t2.color)
                            .lineLimit(1)
                            .padding(PhoneMetric.snug)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: PhoneMetric.invocationRadius)
                            .fill(ColorToken.f3.color)
                    )
                }
            }
        }
        .padding(PhoneMetric.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.plateRadius)
                .fill(wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhoneMetric.plateRadius)
                .strokeBorder(border, lineWidth: PhoneMetric.hairline)
        )
    }

    /// `--attnWash` and `--attnLine` are still absent from `ColorToken` — I1 reported this and it
    /// has not landed. The alphas are read from `PhoneMetric`, traced to the design representation
    /// they came from, rather than added to a shared token surface from inside a feature.
    private var wash: Color {
        severity == .attention
            ? ColorToken.attention.color.opacity(PhoneMetric.tintedWashOpacity)
            : ColorToken.panel.color
    }

    private var border: Color {
        severity == .attention
            ? ColorToken.attention.color.opacity(PhoneMetric.tintedBorderOpacity)
            : ColorToken.line.color
    }

    private func colour(for severity: CapabilityPlate.Severity) -> ColorToken {
        severity == .attention ? .attention : .t3
    }

    private func symbol(for kind: CapabilityPlate.Kind) -> Icon {
        switch kind {
        case .runsLocally: .bolt
        case .remote: .conduit
        case .credential: .shield
        case .archived: .warn
        case .unknownTransport: .bang
        }
    }
}
