import MCPRouterKit
import SwiftUI

/// Discover: the companion's reason to exist, and the surface I2 replaces `AwaitingTab` with.
///
/// **Two bands, not three**, and search as the only filter, because `q` is the only filter the
/// endpoint takes. See `DiscoverBands` for why the brief's trending band cannot ship, and
/// `DiscoverPresentation` for why no view here formats anything.
public struct DiscoverScreen: View {
    @State private var model: DiscoverModel
    @State private var selected: RegistryEntry?

    public init(
        client: any ControlAPIClient,
        queue: any CapabilityQueueWriter,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        _model = State(wrappedValue: DiscoverModel(
            client: client,
            queue: queue,
            connection: connection,
            macName: macName
        ))
    }

    public var body: some View {
        NavigationStack {
            content
                // `Tab` is nested inside a generic `PhoneShell`, so the generic has to be named to
                // reach it. `EmptyView` is arbitrary — the enum does not depend on it — and naming
                // the tab here rather than restating "Discover" keeps one source for the title.
                .navigationTitle(PhoneShell<EmptyView>.Tab.discover.title)
                .background(ColorToken.ground.color)
                .searchable(
                    text: $model.query,
                    prompt: Text(DiscoverCopy.entry(.unit(.searchPlaceholder)).body)
                )
                .navigationDestination(item: $selected) { entry in
                    CapabilityDetailView(entry: entry, model: model)
                }
        }
        // `.task(id:)` rather than a `Task {}` in the body: it is cancelled when the view goes
        // away and re-runs when the query changes, which is both the debounce and the cancellation
        // (`SWIFT_PRACTICES.md` §1).
        .task(id: model.query) {
            await model.search()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            loadingList

        case .populated:
            populatedList(warnings: [])

        case let .partial(warnings):
            // Results arrived and something was degraded. The rows are still shown — a partial
            // surface that hides what did arrive is worse than one that explains what did not.
            populatedList(warnings: warnings)

        case .emptyNoQuery:
            DiscoverMessageState(
                entry: model.copy(.list(.emptyNoQuery)),
                action: { Task { await model.search() } }
            )
            .frame(maxHeight: .infinity)

        case let .emptyQuery(query):
            DiscoverMessageState(
                entry: model.copy(.list(.emptyQuery), extra: [.query: query]),
                action: { Task { await model.clearSearch() } }
            )
            .frame(maxHeight: .infinity)

        case let .failed(reason):
            DiscoverMessageState(
                entry: model.copy(.list(.failed), extra: [.reason: reason.text]),
                icon: .bang,
                tint: .fail,
                action: { Task { await model.search() } }
            )
            .frame(maxHeight: .infinity)

        case .offline:
            // A27: its own state, never a generic error banner. `DESIGN.md` §5 asks Offline to
            // offer to start the router; the phone cannot start a process on the Mac, so it gives
            // the instruction instead — a recorded deviation with its reason.
            //
            // The tint is `--t3`, a label tier, and deliberately **not** `--attn`. §2 reserves
            // amber for "wants a human decision", and a router that is not running asks for an
            // action rather than a decision — there is nothing here to weigh. `ConnectionBanner`
            // already settled this for the same class of state on this device: reachable is
            // `--live` and "the other two are label tiers, not indicators". Spending amber here
            // is the dilution §2 names as the thing that stops one amber dot meaning anything.
            DiscoverMessageState(entry: model.copy(.list(.offline)), icon: .bolt, tint: .t3)
                .frame(maxHeight: .infinity)
        }
    }

    private var loadingList: some View {
        List {
            ForEach(0 ..< 5, id: \.self) { _ in
                DiscoverSkeletonRow()
            }
        }
        .listStyle(.plain)
        .accessibilityLabel(DiscoverCopy.entry(.unit(.searchingAccessibility)).body)
    }

    private func populatedList(warnings: [WarningClass]) -> some View {
        List {
            if !warnings.isEmpty {
                Section {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        warningRow(warning)
                    }
                }
            }

            if model.entries.isEmpty {
                // A degraded search can return warnings *and* nothing else, and `resolve` reports
                // that as `.partial` so the surface can say why it is empty. Drawing the bands here
                // put a per-band empty state on both bands over a page with no results at all —
                // two "this band is empty" sentences standing in for "nothing came back". The
                // warnings above explain the degradation; this says what arrived.
                DiscoverMessageState(
                    entry: model.isSearching
                        ? model.copy(.list(.emptyQuery), extra: [.query: model.query])
                        : model.copy(.list(.emptyNoQuery)),
                    icon: .discover,
                    action: { Task { await model.search() } }
                )
                .listRowBackground(Color.clear)
            } else if model.isSearching {
                // A10: bands order the whole page and stop meaning anything once the user has
                // narrowed it, so a query shows one flat ranked list in the endpoint's own order.
                Section {
                    ForEach(model.entries) { entry in
                        Button { selected = entry } label: {
                            DiscoverRow(entry: entry, band: nil)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    windowControl
                }
            } else {
                Section { windowControl }
                ForEach(DiscoverBand.allCases) { band in
                    DiscoverBandSection(
                        band: band,
                        entries: model.members(of: band),
                        isEmptyWithinResults: model.isBandEmpty(band),
                        window: model.window,
                        onSelect: { selected = $0 },
                        onResetWindow: { model.resetWindow() }
                    )
                }
            }

            if let truncation = model.truncationText {
                // A8: disclosed only when the results exactly fill the limit. A silently truncated
                // list invites the user to conclude the index holds nothing more.
                Text(truncation)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listStyle(.plain)
    }

    private var windowControl: some View {
        DiscoverWindowControl(window: $model.window, isSearching: model.isSearching)
            .textCase(nil)
            .padding(.vertical, PhoneMetric.snug)
    }

    /// A25: each warning class gets its own copy, and one matching no class renders verbatim under
    /// a generic heading rather than being dropped.
    @ViewBuilder
    private func warningRow(_ warning: WarningClass) -> some View {
        let entry: DiscoverCopy.Entry = if case let .unrecognised(text) = warning {
            model.copy(warning.copyKey, extra: [.warning: text])
        } else {
            model.copy(warning.copyKey)
        }

        VStack(alignment: .leading, spacing: PhoneMetric.tight) {
            if let headline = entry.headline {
                Text(headline)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
            }
            Text(entry.body)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
            if let label = entry.actionLabel {
                Button(label) { Task { await model.search() } }
                    .buttonStyle(PhoneStandardButtonStyle())
                    .frame(minHeight: PhoneMetric.minimumTarget)
            }
        }
        .padding(.vertical, PhoneMetric.snug)
    }
}
