import MCPRouterKit
import SwiftUI

/// The scanner viewfinder's frame. Brackets, not a magnifier.
///
/// A camera glyph and scanner brackets say "point this at something"; the prototype's magnifier
/// says "search", which is a different verb and a different expectation.
struct ViewfinderFrame<Content: View>: View {
    var isLive: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PhoneMetric.finderRadius, style: .continuous)
                .fill(ColorToken.panel.color)

            RoundedRectangle(cornerRadius: PhoneMetric.finderRadius, style: .continuous)
                .strokeBorder(ColorToken.line.color, lineWidth: PhoneMetric.hairline)

            if isLive {
                ForEach(Corner.allCases, id: \.self) { corner in
                    BracketShape(corner: corner)
                        .stroke(
                            ColorToken.accent.color,
                            style: .init(lineWidth: PhoneMetric.bracketWeight, lineCap: .round)
                        )
                }
                .padding(PhoneMetric.loose)
            }

            content()
        }
        .frame(height: PhoneMetric.finder)
        .accessibilityElement(children: .combine)
    }

    enum Corner: CaseIterable, Hashable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    struct BracketShape: Shape {
        let corner: Corner

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let length = PhoneMetric.bracket
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
            case .topTrailing:
                path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
            case .bottomLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
            case .bottomTrailing:
                path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
            }
            return path
        }
    }
}

/// A short list of statements under a heading — the "before you scan" caution and the "what this
/// phone can do" summary both take this shape.
struct PhoneNoticeList: View {
    let entry: PairingCopy.Entry
    var tone: PhoneMessageBlock.Tone = .caution
    var glyph: Icon = .warn

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.snug) {
            if let headline = entry.headline {
                HStack(spacing: PhoneMetric.snug) {
                    IconView(glyph, size: TypeToken.callout.size)
                        .foregroundStyle(tone.accent.color)
                        .accessibilityHidden(true)
                    Text(headline)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t1.color)
                }
            }
            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PhoneMetric.normal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(ColorToken.f3.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .strokeBorder(tone == .neutral ? ColorToken.line.color : tone.accent.color.opacity(PhoneMetric.tintedBorderOpacity), lineWidth: PhoneMetric.hairline)
        )
    }
}

/// The scan surface: camera live, caution stated before the camera is useful.
///
/// The caution's placement is the design decision. A pairing code lets a remote party put executable
/// code on someone's laptop, and a warning shown *after* a successful scan is a warning about a
/// thing that already happened. It is `--attn` rather than `--fail` because nothing has failed when
/// we warn somebody before they act — that is precisely the "wants a human decision" the token
/// means.
struct ScanView<Preview: View>: View {
    let onTypeInstead: () -> Void
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneMetric.loose) {
            Text("On your Mac, open MCP Router → Settings → Pair iPhone, then point this camera at the code it shows.")
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

            ViewfinderFrame(isLive: true) {
                preview()
            }
            .accessibilityLabel(PairingCopy.entry(.scanReady).body)

            PhoneNoticeList(entry: PairingCopy.entry(.scanCaution))

            Button(PairingCopy.entry(.scanReady).actionLabel ?? "", action: onTypeInstead)
                .buttonStyle(StandardButtonStyle())
                .frame(minHeight: PhoneMetric.minimumTarget)
                .frame(maxWidth: .infinity)

            Text(PairingCopy.entry(.scanNoCode).body)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The three camera states that are not "authorized".
///
/// `restricted` is separated from `denied` on purpose: a restricted device may not be the user's to
/// change, so its primary action is the typed path rather than a trip to Settings that cannot help.
struct CameraPermissionView: View {
    let authorization: CameraAuthorization
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    let onTypeInstead: () -> Void

    var body: some View {
        let key = authorization.copyKey ?? .cameraNotDetermined
        let entry = PairingCopy.entry(key)

        VStack(alignment: .leading, spacing: PhoneMetric.loose) {
            ViewfinderFrame(isLive: false) {
                Text(placeholderLabel)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t3.color)
            }

            PhoneNoticeList(
                entry: entry,
                tone: authorization == .notDetermined ? .neutral : .failure,
                glyph: authorization == .notDetermined ? .shield : .warn
            )

            Button(entry.actionLabel ?? "", action: primaryAction)
                .buttonStyle(ProminentButtonStyle())
                .frame(minHeight: PhoneMetric.minimumTarget)
                .frame(maxWidth: .infinity)

            if let secondary = entry.secondaryActionLabel {
                Button(secondary, action: onTypeInstead)
                    .buttonStyle(StandardButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var placeholderLabel: String {
        switch authorization {
        case .notDetermined: "Camera not started"
        case .denied, .restricted: "Camera unavailable"
        case .authorized: ""
        }
    }

    private var primaryAction: () -> Void {
        switch authorization {
        case .notDetermined: onRequest
        case .denied: onOpenSettings
        // Restricted's primary action is the typed path. Sending a restricted user to Settings is
        // a recovery they may be unable to take.
        case .restricted: onTypeInstead
        case .authorized: onRequest
        }
    }
}

/// The handshake in flight.
///
/// **The countdown exists on exactly one of these two paths.** A scanned payload carried the code's
/// expiry, so the phone has observed it and may show it. A typed code has told the phone nothing —
/// the Mac has not answered yet — so this shows a working indicator and no number. The two frames
/// are otherwise identical, and that is the honesty rule made visible.
struct VerifyingView: View {
    let attempt: PairingAttempt
    var now: Date = .init()

    private var key: PairingCopy.Key {
        switch attempt {
        case .scanned: .verifyingScanned
        case .typed: .verifyingTyped
        }
    }

    /// The countdown text, or nil when there is no observed expiry.
    var countdown: String? {
        guard case let .scanned(payload) = attempt,
              let remaining = payload.timeRemaining(at: now) else { return nil }
        let total = Int(remaining)
        return String(format: "code expires in %d:%02d", total / 60, total % 60)
    }

    var body: some View {
        let entry = PairingCopy.entry(key).resolved(macName: attempt.macName)

        VStack(spacing: PhoneMetric.normal) {
            Spacer(minLength: PhoneMetric.section)

            IconView(.conduit, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(ColorToken.t3.color)
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

            HStack(spacing: PhoneMetric.snug) {
                WorkingIndicator()
                Text(countdown ?? "working…")
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
            }
            .padding(.top, PhoneMetric.snug)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A rotating arc.
///
/// Transform only, never opacity, and it **starts at full opacity** — `DESIGN.md` §7 forbids
/// animating opacity from 0 on entry, because content is unreadable for half of a fade. Under
/// Reduce Motion the arc holds its position: the animation goes, the state it reports stays.
struct WorkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(ColorToken.accent.color, style: .init(lineWidth: PhoneMetric.bracketWeight, lineCap: .round))
            .frame(width: TypeToken.body.size, height: TypeToken.body.size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                value: spinning
            )
            .onAppear { if !reduceMotion { spinning = true } }
            .accessibilityHidden(true)
    }
}

/// A pairing outcome that gets a whole pane — the four that cannot be fixed by retyping, plus the
/// two decode failures.
struct PairingOutcomeView: View {
    let outcome: PairingOutcome
    let macName: String?
    let onPrimary: () -> Void

    var body: some View {
        let key = PairingCopy.key(for: outcome) ?? .outcomeMalformedPayload
        let entry = PairingCopy.entry(key).resolved(macName: macName)

        VStack(alignment: .leading, spacing: PhoneMetric.loose) {
            Spacer(minLength: PhoneMetric.section)

            IconView(glyph, size: PhoneMetric.emptyGlyph, weight: .light)
                .foregroundStyle(ColorToken.t3.color)
                .accessibilityHidden(true)

            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.body)
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)

            Button(entry.actionLabel ?? "", action: onPrimary)
                // Refused is reported without alarm and **without retry as the primary action** —
                // someone made a decision at the Mac, and pressing a prominent "Try again" against
                // that decision is the app arguing with its user.
                .buttonStyle(isRefusal ? AnyPhoneButton(.standard) : AnyPhoneButton(.prominent))
                .frame(minHeight: PhoneMetric.minimumTarget)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isRefusal: Bool {
        if case .refused = outcome { return true }
        return false
    }

    private var glyph: Icon {
        switch outcome {
        case .unreachable: .bolt
        default: .warn
        }
    }
}

/// Picks a button style at runtime.
///
/// SwiftUI's `buttonStyle` takes a concrete type, so a conditional between two styles cannot be
/// written inline without this. It exists because §3.4 allows exactly one prominent action per view
/// and the refusal pane deliberately is not it.
struct AnyPhoneButton: ButtonStyle {
    enum Kind { case prominent, standard }
    private let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .prominent: ProminentButtonStyle().makeBody(configuration: configuration)
            case .standard: StandardButtonStyle().makeBody(configuration: configuration)
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

            IconView(.check, size: PhoneMetric.successMark, weight: .semibold)
                .foregroundStyle(ColorToken.live.color)
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
                    headline: "What this phone can do",
                    body: PairingCopy.neverInstalls
                ),
                tone: .neutral,
                glyph: .shield
            )

            Button(entry.actionLabel ?? "Done", action: onDone)
                .buttonStyle(ProminentButtonStyle())
                .frame(minHeight: PhoneMetric.minimumTarget)
                .frame(maxWidth: .infinity)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
