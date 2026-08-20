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

    /// The text the system keyboard is editing. `entry` stays the source of truth for what is
    /// *drawn*; this is only what the field currently holds, pushed through
    /// `PairingCodeEntry.append(contentsOf:)` so Crockford normalisation and the length cap live in
    /// one place rather than being reimplemented here.
    @State private var typed: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // The real control. It is invisible and it is the thing being typed into: the boxes
            // below draw the glyphs and the caret, and this supplies the system keyboard, hardware
            // keys on iPad, paste, dictation, and an element `app.textFields` can find.
            //
            // **Deliberately not `.textContentType(.oneTimeCode)`.** Apple's one-time-code AutoFill
            // reads codes out of Messages and Mail. This code is read off the Mac's own screen, so
            // that content type would put unrelated SMS codes in the QuickType bar — an AutoFill
            // suggestion that is always wrong is worse than none.
            keyboardConfigured(TextField("", text: $typed))
                .focused($isFocused)
                .autocorrectionDisabled()
                .foregroundStyle(Color.clear)
                .tint(Color.clear)
                .accessibilityLabel("Pairing code")
                .accessibilityValue(spokenValue)
                .onChange(of: typed) { _, next in
                    var rebuilt = PairingCodeEntry()
                    rebuilt.append(contentsOf: next)
                    entry = rebuilt
                    // Reflect back what the model accepted, so a rejected character does not sit
                    // in the field invisibly and shift every later keystroke.
                    if rebuilt.characters != next { typed = rebuilt.characters }
                }

            boxes
                .allowsHitTesting(false)
                // The boxes are decoration now. Leaving them as an accessibility element would
                // publish a second "Pairing code" beside the field, and the one VoiceOver landed
                // on first would be the one that cannot be typed into.
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
    }

    /// The keyboard hints, which exist only on iOS.
    ///
    /// `MCPRouterUI` compiles for macOS as well — that is what lets every phone surface be
    /// exercised on the host test target — so `keyboardType` and `textInputAutocapitalization`
    /// have to be gated rather than applied inline. The code is Crockford base-32 and alphanumeric,
    /// so `.asciiCapable` rather than a number pad, and uppercase because that is how the Mac draws
    /// it.
    @ViewBuilder
    private func keyboardConfigured(_ field: some View) -> some View {
        #if os(iOS)
            field
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
        #else
            field
        #endif
    }

    private var spokenValue: String {
        entry.characters.isEmpty
            ? "empty"
            : entry.characters.map(String.init).joined(separator: " ")
    }

    private var boxes: some View {
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
                        lineWidth: isCaret || isInvalid ? MetricToken.focusRing.leadingScalar : PhoneMetric
                            .hairline
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
            // `PairingCopy.entry(.typedEntryReady)` has carried a headline since it was written and
            // this view drew only the body, so the one surface a user reaches by *choosing* it —
            // "Enter the code instead" — was the one that never confirmed where they had arrived.
            // Every other pairing surface renders its headline; this follows the same shape as
            // `PairingResultSurfaces`.
            if let headline = ready.headline {
                Text(headline)
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                Text(PairingCopy.entry(.typedEntryHelper).body)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
            }

            if inlineKey == .typedEntryExpired {
                Button(PairingCopy.entry(.typedEntryExpired).actionLabel ?? "", action: onScanInstead)
                    .buttonStyle(PhoneStandardButtonStyle(fillsWidth: true))
            } else {
                // Disabled until all eight are present, and disabled **dims in place** rather than
                // disappearing — §3.4. A button that vanishes takes its own explanation with it.
                Button(ready.actionLabel ?? "Pair Mac", action: onSubmit)
                    .buttonStyle(PhoneProminentButtonStyle(fillsWidth: true))
                    .disabled(!entry.isComplete)
            }
        }
    }
}
