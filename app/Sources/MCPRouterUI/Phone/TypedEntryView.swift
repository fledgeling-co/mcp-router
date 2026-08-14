import MCPRouterKit
import SwiftUI

/// The eight-box code field.
///
/// **An input, not a display.** This is the correction the design representation records as its most
/// important: the shared prototype had the phone *showing* a code for the Mac to read, which inverts
/// the direction the whole design depends on. The Mac issues; the phone consumes. The only
/// characters this view ever renders are the ones the user typed.
///
/// No countdown appears here. The phone has not spoken to the Mac yet, so it has observed no
/// expiry, and `DESIGN.md` §6 forbids displaying a number the system has not observed. The helper
/// line says the code expires and points at the Mac, which is where the number actually is.
struct TypedCodeField: View {
    @Binding var entry: PairingCodeEntry
    var isInvalid: Bool = false

    var body: some View {
        HStack(spacing: PhoneMetric.snug) {
            ForEach(0 ..< PairingCode.length, id: \.self) { index in
                box(at: index)
                if index == 3 {
                    Text("–")
                        .typeRole(.title3, monospaced: true)
                        .foregroundStyle(ColorToken.t4.color)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // One element: eight separate boxes would be read out one character at a time.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code")
        .accessibilityValue(entry.characters.isEmpty ? "empty" : entry.characters.map(String.init).joined(separator: " "))
    }

    @ViewBuilder
    private func box(at index: Int) -> some View {
        let character = entry.character(at: index)
        let isCaret = index == entry.caret

        Text(character.map(String.init) ?? "·")
            .typeRole(.title2, monospaced: true)
            .foregroundStyle((character == nil ? ColorToken.t4 : boxTextColor).color)
            .frame(width: PhoneMetric.codeBox, height: PhoneMetric.codeBoxHeight)
            .background(
                RoundedRectangle(cornerRadius: PhoneMetric.codeBoxRadius, style: .continuous)
                    .fill(ColorToken.raised.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhoneMetric.codeBoxRadius, style: .continuous)
                    .strokeBorder(
                        borderColor(isCaret: isCaret).color,
                        lineWidth: isCaret || isInvalid ? MetricToken.focusRing.leadingScalar : PhoneMetric.hairline
                    )
            )
    }

    private var boxTextColor: ColorToken { isInvalid ? .fail : .t1 }

    private func borderColor(isCaret: Bool) -> ColorToken {
        if isInvalid { return .fail }
        return isCaret ? .accent : .lineStrong
    }
}

/// Inline copy sitting directly beside the control that produced it.
///
/// `DESIGN.md` §6: an error states what happened and how to fix it, next to the thing that failed,
/// without blaming and without emoting. A banner at the top of the screen fails the "next to"
/// clause, which is the part that makes the message findable.
struct InlineMessage: View {
    let text: String
    var glyph: Icon = .warn
    var tone: PhoneMessageBlock.Tone = .failure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PhoneMetric.snug) {
            IconView(glyph, size: TypeToken.callout.size)
                .foregroundStyle(tone.accent.color)
                .accessibilityHidden(true)
            Text(text)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Typed entry: the fallback, and a first-class path rather than an apology.
struct TypedEntryView: View {
    @Binding var entry: PairingCodeEntry
    let failure: PairingOutcome?
    let onSubmit: () -> Void
    let onScanInstead: () -> Void

    /// Which inline message applies, if any. Only two failures land on this surface; the rest get a
    /// whole pane, because their recovery is not "type it again".
    private var inlineKey: PairingCopy.Key? {
        switch failure {
        case .notRecognised: .typedEntryNotRecognised
        case .expired: .typedEntryExpired
        default: nil
        }
    }

    var body: some View {
        let ready = PairingCopy.entry(.typedEntryReady)

        VStack(alignment: .leading, spacing: PhoneMetric.loose) {
            Text(ready.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

            TypedCodeField(entry: $entry, isInvalid: inlineKey == .typedEntryNotRecognised)

            if let inlineKey {
                InlineMessage(
                    text: PairingCopy.entry(inlineKey).body,
                    glyph: inlineKey == .typedEntryExpired ? .bang : .warn,
                    // Expiry is a recovery, not a failure — the Mac has already issued the next
                    // code, so this is amber rather than red.
                    tone: inlineKey == .typedEntryExpired ? .caution : .failure
                )
            } else {
                Text("The code expires. Your Mac is showing how long is left.")
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
            }

            if inlineKey == .typedEntryExpired {
                Button(PairingCopy.entry(.typedEntryExpired).actionLabel ?? "", action: onScanInstead)
                    .buttonStyle(StandardButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
                    .frame(maxWidth: .infinity)
            } else {
                // Disabled until all eight are present, and disabled **dims in place** rather than
                // disappearing — §3.4. A button that vanishes takes its own explanation with it.
                Button(ready.actionLabel ?? "Pair Mac", action: onSubmit)
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(!entry.isComplete)
                    .frame(minHeight: PhoneMetric.minimumTarget)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
