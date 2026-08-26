#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The product header: the mark, the name, the publisher and the one-line pitch.
    ///
    /// It arrived in the mock at `6c513b0`, after the brief was written, and its commit message
    /// gives the reason this item carries it: *the reader's question eight paragraphs into a README
    /// is still "and do I install it"*. So the identity stays put while the document scrolls under
    /// it. `spec-M19.md` §2's second assumption is that decision.
    ///
    /// **The mark is a drawn monogram plate, not generated chrome.** `DESIGN.md` §4 is explicit
    /// that a gradient rectangle standing where authored artwork belongs is the loudest
    /// low-fidelity tell available; the plate is the same one the Discover board's rows draw.
    struct CapabilityDocumentHeader: View {
        let identity: CapabilityDocument.Identity

        var body: some View {
            HStack(alignment: .center, spacing: DocumentMetrics.quoteInset) {
                mark
                VStack(alignment: .leading, spacing: DocumentMetrics.labelGap) {
                    Text(identity.name)
                        .typeRole(.title2)
                        .foregroundStyle(ColorToken.t1.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    publisher
                    // Omitted rather than drawn empty. §6's rule that a figure the router does not
                    // observe is never displayed applies to a blank row as much as to an invented
                    // one: a server declared in a config file has no pitch anybody observed, and an
                    // empty `Text` here would reserve the stack's spacing for it anyway.
                    if let pitch = identity.pitch, !pitch.isEmpty {
                        Text(pitch)
                            .typeRole(.callout)
                            .foregroundStyle(ColorToken.t2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DocumentMetrics.bandPadding)
            .padding(.vertical, DocumentMetrics.quoteInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorToken.panel.color)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColorToken.line.color).frame(height: DocumentMetrics.hairline)
            }
            .measured(
                "product-header", role: "title-block", kind: .hstack,
                alignment: "leading", tokens: ["background": .panel], text: identity.name
            )
        }

        private var mark: some View {
            RoundedRectangle(cornerRadius: DocumentMetrics.markRadius, style: .continuous)
                .fill(ColorToken.raised2.color)
                .overlay {
                    Text(monogram)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t2.color)
                }
                .frame(width: DocumentMetrics.markSide, height: DocumentMetrics.markSide)
                .accessibilityHidden(true)
        }

        /// The first letter of the name, uppercased. Empty names cannot reach here from a parsed
        /// document, and an empty plate is still a plate rather than a crash.
        private var monogram: String {
            identity.name.first.map { String($0).uppercased() } ?? ""
        }

        /// The publisher, with the verified glyph only where the marketplace actually marks them.
        ///
        /// The word `Official` carries the meaning and the glyph accompanies it, never the other way
        /// round: `DESIGN.md` §6 requires a word beside every state that has a mark, which is also
        /// what exempts the pairing from the non-text contrast floor.
        @ViewBuilder private var publisher: some View {
            if let name = identity.publisher, !name.isEmpty {
                publisherRow(name)
            }
        }

        private func publisherRow(_ name: String) -> some View {
            HStack(spacing: DocumentMetrics.labelGap) {
                Text(name)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
                if identity.publisherIsVerified {
                    // The mock draws its own `#i-verified` glyph and `Icon` has no such case. A
                    // new case would re-base `DesignSystemTests`' sprite inventory, which asserts
                    // the count against the *prototype*'s sprite — the trap
                    // `planning/fidelity/settings.layers.json` records as its second divergence.
                    // A checkmark beside the word says the same thing and costs no re-basing.
                    IconView(.check, size: TypeToken.subheadline.size)
                        .foregroundStyle(ColorToken.accentText.color)
                        .measured(
                            "verified-mark",
                            role: "verified-mark",
                            kind: .leaf,
                            tokens: ["foreground": .accentText]
                        )
                    Text("Official")
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.accentText.color)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The five-cell facts strip under the header.
    ///
    /// A list rather than five named fields, because a fact nobody observed must be **absent**
    /// rather than empty — `DESIGN.md` §6's rule that nothing is displayed the router does not
    /// observe, expressed as a shape rather than as a convention. A capability with two known facts
    /// draws two cells; one with none draws no strip at all.
    struct CapabilityFactsStrip: View {
        let facts: [CapabilityDocument.Fact]

        var body: some View {
            if facts.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        cell(fact)
                        if index < facts.count - 1 {
                            Rectangle()
                                .fill(ColorToken.line.color)
                                .frame(width: DocumentMetrics.hairline)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(ColorToken.ground.color)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ColorToken.line.color).frame(height: DocumentMetrics.hairline)
                }
                .measured("product-facts", role: "table", kind: .hstack, tokens: ["background": .ground])
            }
        }

        private func cell(_ fact: CapabilityDocument.Fact) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(fact.label)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                Text(fact.value)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DocumentMetrics.factPaddingVertical)
            .padding(.horizontal, DocumentMetrics.factPaddingHorizontal)
            // One stop per cell, label and reading together, for the reason `DESIGN.md` gives for
            // the sidebar's readout card: a cell carrying a value announces as one sentence.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(fact.label), \(fact.value)")
        }
    }
#endif
