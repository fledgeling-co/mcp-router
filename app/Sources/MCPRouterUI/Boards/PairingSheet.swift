#if os(macOS)
    import CoreImage
    import CoreImage.CIFilterBuiltins
    import MCPRouterKit
    import SwiftUI

    /// The QR, drawn from bytes that already exist.
    ///
    /// **It takes the encoded text, never a `PairingPayload`.** That is the control, not a style
    /// choice: a view handed a payload could build its own encoding, and a second encoder is exactly
    /// how the Mac and the phone come to disagree about a wire I1 already fixed. There is one
    /// encoder, `MacPairing.encode`, and this draws what it produced.
    ///
    /// `CIQRCodeGenerator` is in the platform, so the kit's no-external-dependencies promise holds.
    /// Correction level M — the code sits on a screen being photographed at a slight angle rather
    /// than printed on something that will be scuffed, and a higher level costs resolution for
    /// robustness this situation does not need.
    struct PairingQRView: View {
        let encoded: String
        let side: Double

        var body: some View {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: side, height: side)
                } else {
                    // A failure to render is stated rather than left as a blank square that reads as
                    // a code the camera simply cannot see.
                    RoundedRectangle(cornerRadius: InboxBoardMetrics.qrRadius, style: .continuous)
                        .fill(ColorToken.f2.color)
                        .frame(width: side, height: side)
                        .overlay {
                            Text(InboxCopy.Pairing.preparing)
                                .typeRole(.caption)
                                .foregroundStyle(ColorToken.t3.color)
                        }
                }
            }
            .background {
                // A QR needs a light quiet zone around it or a scanner cannot find its finder
                // patterns against a graphite ground. This is the code's *substrate* rather than
                // chrome — the same role paper plays — and the system has no token for that.
                //
                // `--onAccent` is used because it is the one token that is `#FFFFFF` in **both**
                // appearances, which is exactly the property a substrate needs: a quiet zone that
                // darkened in light mode would break the contrast the scanner depends on. The name
                // is a stretch and is recorded as such — `D-m6-e` asks DESIGN.md for a substrate
                // token, since inventing a literal here would put a colour outside the one document
                // that is meant to be authoritative for every colour in the product.
                RoundedRectangle(cornerRadius: InboxBoardMetrics.qrRadius, style: .continuous)
                    .fill(ColorToken.onAccent.color)
                    .padding(-InboxBoardMetrics.tightGap)
            }
            .accessibilityLabel("Pairing code, as a QR code")
        }

        private var image: CGImage? {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(encoded.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage else { return nil }
            // Scaled at generation rather than by the view, so the modules stay square pixels
            // instead of being resampled into blur that a camera then has to work through.
            let scale = side / output.extent.width
            let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return CIContext().createCGImage(scaled, from: scaled.extent)
        }
    }

    /// The expiry, drawn as a depleting arc beside the words that say the same thing.
    ///
    /// **Determinate, where the mock's ring is an indeterminate spinner.** The mock defines it as
    /// `animation:spin 2s linear infinite`, `design/mocks/prototype.html:287` at `08a24ed`, and a
    /// head that turns at the same rate with four minutes left and with four seconds left carries
    /// no information about the thing it sits next to. Worse on this build than in general: nothing in
    /// either app target binds a listener, so a spinner on the pairing sheet reads as this Mac
    /// waiting for a phone, which is the one thing it is not doing.
    ///
    /// The fraction it draws IS observed — this Mac issued the code and holds both ends of its
    /// window — so `IssuedPairingCode.fractionRemaining(at:)` is what `DESIGN.md` §6 permits to
    /// reach a screen, and a spinner is what it does not.
    ///
    /// **The design of record draws no ring at all**: it states the expiry as text alone, reading
    /// `expires in 2:41`, `design/mcp-router-console.html:3853` at `08a24ed`. This sheet is not converted to
    /// it — its lede is the prototype's
    /// word for word — so the prototype is the citable design for this surface (`ORCHESTRATOR.md`,
    /// Design authority), and converting it is `M23`'s contract rather than this item's.
    ///
    /// No animation and no implicit transition: the arc changes once a second because
    /// `PairingSessionModel.now` changes, which is a redraw rather than motion, so there is nothing
    /// here for Reduce Motion to switch off.
    ///
    /// Hidden from the accessibility tree because the label beside it carries the same fact in
    /// words. VoiceOver reading one countdown twice is noise, and the ring is never the only place
    /// the remaining time appears.
    ///
    /// **The head is `--t2`, not the mock's `--attn`, and `InboxConformanceTests` is what settled
    /// that.** Its A15 census pins which files spend an indicator colour and how many times, and it
    /// went red on a third `attention` in this file. It was right to: §2 gives `--attn` the meaning
    /// *wants a human decision*, and on this sheet that is the warning about who can queue into
    /// your inbox — nothing needs deciding while a code is simply running down. The countdown's own
    /// label is `--t2`, *secondary text, metadata*, so an arc drawn in a louder colour than the
    /// words it duplicates would be claiming an urgency the product never acts on. §2 also gives
    /// `--attn` the `pairedWithAWord` role at 2.31:1 on the light ground, which an arc carrying no
    /// word of its own does not satisfy on its own terms.
    struct PairingExpiryRing: View {
        let fraction: Double

        var body: some View {
            ZStack {
                Circle()
                    .strokeBorder(
                        ColorToken.lineStrong.color,
                        lineWidth: InboxBoardMetrics.expiryRingStroke
                    )
                Circle()
                    .inset(by: InboxBoardMetrics.expiryRingStroke / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(
                        ColorToken.t2.color,
                        style: StrokeStyle(
                            lineWidth: InboxBoardMetrics.expiryRingStroke,
                            lineCap: .round
                        )
                    )
                    // Twelve o'clock rather than three, so the arc empties the way a clock face
                    // reads. A static transform, not motion.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: InboxBoardMetrics.expiryRing, height: InboxBoardMetrics.expiryRing)
            .accessibilityHidden(true)
        }
    }

    /// The Mac half of pairing.
    ///
    /// **The state a Release build reaches is `noEndpoint`, and that is the point of the sheet's
    /// shape.** Every other branch needs a `PairingEndpoint`, which no shipping build has, so the
    /// code and the QR simply have no path to the screen — rather than being drawn from placeholder
    /// values that a phone would then act on.
    struct PairingSheet: View {
        @Bindable var session: PairingSessionModel

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: InboxBoardMetrics.gap) {
                    Text(InboxCopy.Pairing.title)
                        .typeRole(.title2)
                        .foregroundStyle(ColorToken.t1.color)
                    content
                }
                .padding(InboxBoardMetrics.panePadding)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                actionBar
            }
            .frame(width: InboxBoardMetrics.sheetWidth)
            .background(ColorToken.panel.color)
        }

        @ViewBuilder
        private var content: some View {
            switch session.phase {
            case .noEndpoint:
                unavailable(title: InboxCopy.Pairing.noEndpointTitle, detail: InboxCopy.Pairing.noEndpointDetail)
            case .listenerOff:
                unavailable(title: InboxCopy.Pairing.listenerOffTitle, detail: InboxCopy.Pairing.listenerOffDetail)
            case .preparing:
                Text(InboxCopy.Pairing.preparing)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
            case let .live(issued, encoded):
                live(issued: issued, encoded: encoded)
            case .expired:
                expired
            case let .failed(detail):
                failed(detail)
            }
        }

        /// Names what is missing and what would provide it. No action control: the thing that would
        /// fix this is another item shipping, which is not something a button can do — the same
        /// judgement the retired scaffold copy made.
        private func unavailable(title: String, detail: String) -> some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                Text(title)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(detail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func live(issued: IssuedPairingCode, encoded: String) -> some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.gap) {
                Text(InboxCopy.Pairing.lede)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)

                PairingQRView(encoded: encoded, side: InboxBoardMetrics.qrSize)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, InboxBoardMetrics.gap)

                // `PairingCode.formatted`, not a second formatter: the Mac shows the code in the
                // shape the phone's field renders it back in.
                Text(issued.code.formatted)
                    .typeRole(.title1)
                    .monospaced()
                    .foregroundStyle(ColorToken.t1.color)
                    .frame(maxWidth: .infinity, alignment: .center)

                warning
                countdown
                typedFallback
            }
        }

        /// `--attn`, and legitimately: it is asking for a human decision about who may put things on
        /// this machine, which is precisely what that token means (§2). Never `--fail` — nothing has
        /// failed.
        private var warning: some View {
            HStack(alignment: .top, spacing: InboxBoardMetrics.labelGap) {
                IconView(.warn, size: TypeToken.caption.size)
                Text(InboxCopy.Pairing.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .typeRole(.caption)
            .foregroundStyle(ColorToken.attention.color)
        }

        /// An **observed** expiry — this Mac issued it — which is what makes a countdown here
        /// legitimate where the phone's typed path has none.
        ///
        /// The ring and the text are two renderings of one reading: both come off
        /// `PairingSessionModel.now`, and both are absent together, because a live code always has
        /// a remaining interval and a fraction of the window it was issued for. The ring is drawn
        /// only where the model hands one over rather than defaulted to full, so a window that
        /// could not be read draws nothing instead of drawing a lie about how much time is left.
        @ViewBuilder
        private var countdown: some View {
            if let remaining = session.remaining {
                HStack(spacing: InboxBoardMetrics.labelGap) {
                    if let fraction = session.fractionRemaining {
                        PairingExpiryRing(fraction: fraction)
                    }
                    Text(InboxCopy.Pairing.expiresIn(remaining))
                        .typeRole(.caption)
                        .monospaced()
                        .foregroundStyle(ColorToken.t2.color)
                }
            }
        }

        /// What to do when the camera will not read the code.
        ///
        /// A sentence rather than a button, and `InboxCopy.Pairing.typeInsteadDetail` carries the
        /// argument for that. It sits under the countdown rather than beside it because it wraps
        /// and the countdown does not.
        private var typedFallback: some View {
            Text(InboxCopy.Pairing.typeInsteadDetail)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
        }

        private var expired: some View {
            VStack(alignment: .leading, spacing: InboxBoardMetrics.tightGap) {
                Text(InboxCopy.Pairing.expiredTitle)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(InboxCopy.Pairing.expiredDetail)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func failed(_ detail: String) -> some View {
            HStack(alignment: .top, spacing: InboxBoardMetrics.labelGap) {
                IconView(.bang, size: TypeToken.caption.size)
                Text(detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .typeRole(.caption)
            .foregroundStyle(ColorToken.fail.color)
        }

        /// One prominent action, trailing (§3.4). The reissue offer appears only in the state that
        /// can use it, rather than sitting dimmed on every other.
        private var actionBar: some View {
            HStack(spacing: InboxBoardMetrics.tightGap) {
                if case .expired = session.phase {
                    Button("Show a new code") { session.reissue() }
                        .buttonStyle(StandardButtonStyle())
                }
                Spacer(minLength: 0)
                Button(InboxCopy.Pairing.doneAction) { session.close() }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(InboxBoardMetrics.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
