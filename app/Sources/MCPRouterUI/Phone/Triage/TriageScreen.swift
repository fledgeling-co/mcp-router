import MCPRouterKit
import SwiftUI

/// Triage: the checklist that replaced the swipe deck.
///
/// The rejected alternatives and the reasons are in `design/mocks/i3-phone-triage.html` §F. The two
/// decisions this screen embodies: the row is **two targets**, and expansion is **in place** rather
/// than a push, because the surface's premise is a comparison across rows and a push destroys it.
public struct TriageScreen: View {
    @State private var model: TriageModel

    public init(
        client: any ControlAPIClient,
        queue: any CapabilityQueueWriter & CapabilityQueueReader,
        dismissals: any DismissalStore,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        _model = State(wrappedValue: TriageModel(
            client: client,
            queue: queue,
            dismissals: dismissals,
            connection: connection,
            macName: macName
        ))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                // Rendered after the list, so the bar is a sibling rather than an overlay. A
                // floating bar that relies on z-index to sit above a scrolling list is one stacking
                // context away from vanishing.
                TriageCommitBar(
                    state: model.commitState,
                    macName: model.macName,
                    onCommit: { Task { await model.queueSelected() } },
                    onDismiss: { Task { await model.dismissSelected() } }
                )
            }
            .navigationTitle(PhoneShell<EmptyView>.Tab.triage.title)
            .background(ColorToken.ground.color)
            .toolbar {
                if model.bucket == .undecided, !model.selectableIDs.isEmpty {
                    ToolbarItem(placement: .primaryAction) { selectAllButton }
                }
            }
        }
        .task { await model.load() }
    }

    private var selectAllButton: some View {
        Button(
            TriageCopy.entry(
                .control(model.isAllSelected ? .clearSelection : .selectAll)
            ).body
        ) {
            model.selectAllOrClear()
        }
        .frame(minHeight: PhoneMetric.minimumTarget)
    }

    @ViewBuilder
    private var content: some View {
        switch model.displayState {
        case .loading:
            skeletonList

        case let .populated(buckets):
            list(buckets: buckets, warnings: [])

        case let .partial(buckets, warnings):
            // Rows still shown: a partial surface that hides what did arrive is worse than one that
            // explains what did not.
            list(buckets: buckets, warnings: warnings)

        case let .empty(bucket):
            emptyPane(for: bucket)

        case .failed:
            // **The reason is deliberately not rendered, and the parameter that pretended to carry
            // it is gone.** Two signatures took a `DiscoverFailureReason` and bound it to `_`, which
            // reads as a wiring bug rather than a decision. `TriageCopy.state(.failed)` has no
            // `{reason}` token, so surfacing it is a copy change and belongs to whoever writes that
            // copy — until then the omission is visible in the code instead of disguised.
            message(.state(.failed), extra: [:], icon: .bang, tint: .fail)

        case .offline:
            // Its own state, never a generic error. The tint is a label tier, not `--attn`: amber
            // means "wants a human decision", and a router that is not running asks for an action.
            message(.state(.offline), extra: [:], icon: .bolt, tint: .t3)

        case .dismissalsUnreadable:
            message(.state(.dismissalsUnreadable), extra: [:], icon: .warn, tint: .fail)

        case .queueUnreadable:
            // A9's symmetry, honoured rather than asserted: the queue file fails the way the
            // dismissal file does, so it gets a state of its own rather than degrading to "nothing
            // is queued" and re-offering everything already sent.
            message(.state(.queueUnreadable), extra: [:], icon: .warn, tint: .fail)
        }
    }

    private var skeletonList: some View {
        List {
            segments
            ForEach(0 ..< 5, id: \.self) { _ in TriageSkeletonRow() }
        }
        .listStyle(.plain)
    }

    private func list(buckets: TriageBuckets, warnings: [WarningClass]) -> some View {
        List {
            segments

            if let undo = model.undo {
                UndoBar(
                    text: TriageCopy.entry(undo.copyKey)
                        .resolved([.count: String(undo.ids.count)]).body,
                    onUndo: { Task { await model.undoLast() } }
                )
                .listRowSeparator(.hidden)
            }

            if let failure = model.writeFailure {
                writeFailureRow(failure)
            }

            if model.bucket == .undecided {
                Text(TriageCopy.entry(.control(.hint)).body)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
            }

            ForEach(warnings, id: \.self) { warning in
                warningRow(warning)
            }

            ForEach(buckets.entries(in: model.bucket)) { entry in
                TriageRow(
                    entry: entry,
                    bucket: model.bucket,
                    isSelected: model.selected.contains(entry.id),
                    isExpanded: model.expanded.contains(entry.id),
                    onToggleSelection: { model.toggleSelection(entry.id) },
                    onToggleExpansion: { model.toggleExpansion(entry.id) },
                    onRestore: { Task { await model.restore(entry.id) } }
                )
            }
        }
        .listStyle(.plain)
    }

    private var segments: some View {
        BucketSegments(
            buckets: model.buckets,
            selected: model.bucket,
            onSelect: { model.select(bucket: $0) }
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: PhoneMetric.snug,
            leading: 0,
            bottom: PhoneMetric.tight,
            trailing: 0
        ))
    }

    private func emptyPane(for bucket: TriageBucket) -> some View {
        VStack(spacing: 0) {
            segments.padding(.horizontal, PhoneMetric.loose)
            Spacer(minLength: PhoneMetric.section)
            messageState(for: emptyKey(bucket), icon: emptyIcon(bucket))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyKey(_ bucket: TriageBucket) -> TriageCopy.Key {
        switch bucket {
        case .undecided: .state(.emptyUndecided)
        case .queued: .state(.emptyQueued)
        case .dismissed: .state(.emptyDismissed)
        }
    }

    private func emptyIcon(_ bucket: TriageBucket) -> Icon {
        switch bucket {
        case .undecided: .check
        case .queued: .tray
        case .dismissed: .list
        }
    }

    private func message(
        _ key: TriageCopy.Key,
        extra: [TriageCopy.Token: String],
        icon: Icon,
        tint: ColorToken
    ) -> some View {
        messageState(for: key, icon: icon, tint: tint, extra: extra)
            .frame(maxHeight: .infinity)
    }

    private func messageState(
        for key: TriageCopy.Key,
        icon: Icon,
        tint: ColorToken = .t3,
        extra: [TriageCopy.Token: String] = [:]
    ) -> some View {
        var values = extra
        values[.mac] = model.macName ?? "your Mac"
        let entry = TriageCopy.entry(key).resolved(values)

        return PhoneMessageState(
            headline: entry.headline,
            message: entry.body,
            actionLabel: entry.actionLabel,
            icon: icon,
            tint: tint,
            action: { Task { await model.load() } }
        )
    }

    private func writeFailureRow(_ failure: TriageWriteFailure) -> some View {
        let entry = TriageCopy.entry(failure.copyKey)
            .resolved([.count: String(failure.saved)])
        return VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
            }
            Text(entry.body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowSeparator(.hidden)
    }

    /// Each warning class gets its own copy; one matching no class renders verbatim under a generic
    /// heading rather than being dropped.
    private func warningRow(_ warning: WarningClass) -> some View {
        let key: TriageCopy.Key = switch warning {
        case .officialDown: .state(.partialOfficialDown)
        case .smitheryDown: .state(.partialSmitheryDown)
        case .githubLimited: .state(.partialGitHubLimited)
        case .unrecognised: .state(.partialUnrecognised)
        }
        // `.partialUnrecognised`'s body is the bare `{warning}` token, so an empty substitution
        // renders a headline over nothing. That cannot happen for the three classified cases, which
        // use their own keys and never read this value — but an unrecognised warning whose raw text
        // is empty is a real wire shape, and the honest rendering is to say the router reported a
        // problem it did not describe rather than to draw a blank.
        let text = if case let .unrecognised(raw) = warning, !raw.isEmpty {
            raw
        } else if case .unrecognised = warning {
            "The router did not say what went wrong."
        } else { "" }
        let entry = TriageCopy.entry(key).resolved([.warning: text])

        return VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
            }
            Text(entry.body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowSeparator(.hidden)
    }
}

/// A loading row built from the real row's own layout — three bars, the third the capability line —
/// so the list does not jump when data lands. Never a spinner over a blank pane.
struct TriageSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: PhoneMetric.snug) {
            Color.clear.frame(width: PhoneMetric.minimumTarget, height: PhoneMetric.minimumTarget)
            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                bar(width: PhoneMetric.skeletonTitle)
                bar(width: PhoneMetric.skeletonSubtitle)
                bar(width: PhoneMetric.skeletonTitle * 1.4)
            }
            .frame(minHeight: PhoneMetric.minimumTarget, alignment: .top)
        }
        .padding(.vertical, PhoneMetric.tight)
        .accessibilityHidden(true)
    }

    private func bar(width: Double) -> some View {
        RoundedRectangle(cornerRadius: PhoneMetric.tight)
            .fill(ColorToken.f2.color)
            .frame(width: width, height: TypeToken.subheadline.size)
    }
}
