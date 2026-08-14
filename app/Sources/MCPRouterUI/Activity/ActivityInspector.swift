#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Everything about one call, untruncated.
    ///
    /// This is the other half of `DESIGN.md` §5's overflow rule — "long names truncate **with the
    /// full value in the inspector**". The row is allowed to truncate precisely because nothing is
    /// lost: the whole tool name and the whole working directory are here.
    ///
    /// It reads and offers nothing. A call has already happened; there is no action a surface could
    /// honestly put beside it, and a disabled one would be worse than none (§3.4).
    struct ActivityInspector: View {
        let record: CallRecord
        let age: String

        static let identifier = "activity-inspector"
        static let toolIdentifier = "activity-inspector-tool"
        static let directoryIdentifier = "activity-inspector-directory"

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                head
                Divider().overlay(ColorToken.line.color)
                fields
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ColorToken.panel.color)
            .accessibilityIdentifier(Self.identifier)
        }

        private var head: some View {
            VStack(alignment: .leading, spacing: MetricToken.selectionInset.leadingScalar) {
                Text(record.tool)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    // The whole name, wrapped rather than truncated — this is where it is complete.
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(Self.toolIdentifier)
                Text("\(record.server) · \(age)")
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ActivityColumn.inset)
        }

        private var fields: some View {
            VStack(alignment: .leading, spacing: MetricToken.selectionRadius.leadingScalar) {
                // Prose, not instrument data — §2 keeps monospace for numerals, counts, durations,
                // error codes and status subtitles, and "Succeeded" is none of those.
                field("Outcome", record.ok ? "Succeeded" : "Failed", isBad: !record.ok, prose: true)
                if let err = record.err, !err.isEmpty {
                    field("Error", err, isBad: true)
                }
                field("Took", ActivityCopy.duration(ms: record.ms))
                field("Start", ActivityCopy.startDescription(cold: record.cold), prose: true)
                field("Session", sessionText)
                field(
                    "Directory",
                    record.cwd ?? ActivityCopy.unattributed,
                    identifier: Self.directoryIdentifier
                )
                field("Timestamp", record.ts)
            }
            .padding(ActivityColumn.inset)
        }

        /// The session, as the router resolved it. `pid` and `client` are both optional on the wire
        /// — `ClientResolver` returns an empty identity whenever `lsof` could not name the caller —
        /// so an unresolved one says so rather than guessing.
        private var sessionText: String {
            ActivityCopy.sessionFull(pid: record.pid, client: record.client)
        }

        private func field(
            _ name: String,
            _ value: String,
            isBad: Bool = false,
            prose: Bool = false,
            identifier: String? = nil
        ) -> some View {
            HStack(alignment: .top, spacing: MetricToken.selectionRadius.leadingScalar) {
                Text(name)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(
                        width: MetricToken.controlExtraLarge.leadingScalar * 2,
                        alignment: .leading
                    )
                Text(value)
                    .typeRole(.subheadline, monospaced: !prose)
                    .foregroundStyle(isBad ? ColorToken.fail.color : ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(identifier ?? "")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name): \(value)")
        }
    }
#endif
