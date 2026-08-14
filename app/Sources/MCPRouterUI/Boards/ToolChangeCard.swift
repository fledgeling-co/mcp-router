#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    // MARK: - One changed tool, both halves of it

    struct ToolChangeCard: View {
        let change: ToolChange

        /// The schema half of the diff.
        ///
        /// **M8 added this, and the gap it closes was a real hole in the security surface.** The
        /// router holds a change when the description **or** the input schema differs
        /// (`src/manifest.ts:80-93`) and ships both on `ToolShape` — this card rendered only the
        /// description. A server that left its description untouched and rewrote `inputSchema` to
        /// add, say, a `context` parameter produced a review sheet showing two identical text fields
        /// and no indication that anything had changed, so the user was asked to accept a diff they
        /// could not see. That is worse than not holding the change, because it manufactures the
        /// appearance of review.
        private var schema: SchemaDiff.Result {
            SchemaDiff.compare(before: change.before?.schema, after: change.after?.schema)
        }

        private var descriptionChanged: Bool {
            change.before?.description != change.after?.description
        }

        var body: some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.gap) {
                HStack {
                    Text(change.name)
                        .typeRole(.body, monospaced: true)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(change.kind.rawValue)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                }
                if let before = change.before?.description {
                    field("was", before, tint: .t2)
                }
                if let after = change.after?.description {
                    field("now", after, tint: .t1)
                }
                // The case that used to render as two identical fields and nothing else.
                if !descriptionChanged, case .changed = schema {
                    Text(SchemaDiff.descriptionUnchanged)
                        .typeRole(.callout)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                schemaSection
                if let invisible = change.invisible, !invisible.isEmpty {
                    // Named explicitly, never silently kept. A description carrying codepoints that
                    // render as nothing and that a model still reads is this surface's whole reason
                    // to exist.
                    Banner(icon: .warn, tint: .fail) {
                        Text(
                            """
                            This description carries \(invisible.count) invisible \
                            \(invisible.count == 1 ? "character" : "characters") that render as \
                            nothing and that a model still reads: \
                            \(invisible.joined(separator: ", ")).
                            """
                        )
                    }
                }
            }
            .padding(ServersBoardMetrics.rowPadding)
            .background(
                RoundedRectangle(
                    cornerRadius: MetricToken.selectionRadius.leadingScalar,
                    style: .continuous
                )
                .fill(ColorToken.raised.color)
            )
        }

        @ViewBuilder
        private var schemaSection: some View {
            switch schema {
            case .identical:
                // Nothing. A schema that did not change is not news, and saying so on every card
                // would teach people to skim past the line that matters.
                EmptyView()

            case let .changed(parameters, beforePretty, afterPretty):
                if !parameters.isEmpty {
                    VStack(alignment: .leading, spacing: ServersBoardMetrics.tightGap) {
                        Text(SchemaDiff.parametersHeading)
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                        ForEach(parameters) { parameter in
                            HStack(spacing: ServersBoardMetrics.tightGap) {
                                // An added input is the shape an exfiltration takes, so it is the
                                // one the reader must not have to find by eye. `--attn` means
                                // "wants a human decision", which is exactly what this is.
                                if parameter.wantsAttention {
                                    IconView(.warn, size: TypeToken.caption.size)
                                        .foregroundStyle(ColorToken.attention.color)
                                }
                                Text(parameter.sentence)
                                    .typeRole(.callout, monospaced: true)
                                    .foregroundStyle(
                                        (parameter.wantsAttention ? ColorToken.attention : ColorToken.t2)
                                            .color
                                    )
                            }
                        }
                    }
                }
                field(SchemaDiff.approvedSchemaHeading, beforePretty, tint: .t2)
                field(SchemaDiff.pendingSchemaHeading, afterPretty, tint: .t1)

            case let .unreadable(beforeRaw, afterRaw, reason):
                // Never folded into "no change". A schema this app cannot decode is itself worth
                // seeing, and a decode path whose failure mode is silence is what
                // `SWIFT_PRACTICES.md` §2 forbids.
                Banner(icon: .bang, tint: .attention) { Text(reason) }
                field(SchemaDiff.approvedSchemaHeading, beforeRaw, tint: .t2)
                field(SchemaDiff.pendingSchemaHeading, afterRaw, tint: .t1)
            }
        }

        private func field(_ label: String, _ value: String, tint: ColorToken) -> some View {
            VStack(alignment: .leading, spacing: ServersBoardMetrics.tightGap) {
                Text(label)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                Text(value)
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle(tint.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
