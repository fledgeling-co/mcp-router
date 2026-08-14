import MCPRouterKit
import Observation
import SwiftUI

/// The Library's state: the paired Mac's declared servers, read-only.
@MainActor
@Observable
public final class LibraryModel {
    @ObservationIgnored public let client: any ControlAPIClient

    public var macName: String?
    public var filter: String = ""

    public internal(set) var state: LibrarySurfaceState = .loading
    private var servers: Result<[MCPServer], ControlAPIError>?

    public init(client: any ControlAPIClient, macName: String? = nil) {
        self.client = client
        self.macName = macName
    }

    public func load() async {
        state = .loading
        do {
            servers = try await .success(client.servers().servers)
        } catch let error as ControlAPIError {
            servers = .failure(error)
        } catch {
            servers = .failure(.transport(detail: error.localizedDescription))
        }
        refilter()
    }

    /// Filtering is client-side and re-runs without a fetch: `/servers` returns the whole list and
    /// takes no query, so asking the router again would be the same request for the same document.
    public func refilter() {
        state = LibrarySurfaceState.resolve(servers: servers, filter: filter)
    }

    public func clearFilter() {
        filter = ""
        refilter()
    }
}

/// Library: what the paired Mac has declared, read-only from here.
///
/// **Servers, not skills.** There is no skills index and no `/skills` route on either router, so
/// the skills absence is stated as a fact rather than drawn as an empty list. **And nothing here
/// mutates anything**: the phone queues and never installs, and this is the narrowest surface in
/// the app — its only control is a client-side filter.
public struct LibraryScreen: View {
    @State private var model: LibraryModel

    public init(client: any ControlAPIClient, macName: String? = nil) {
        _model = State(wrappedValue: LibraryModel(client: client, macName: macName))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(PhoneShell<EmptyView>.Tab.library.title)
                .background(ColorToken.ground.color)
                .searchable(
                    text: $model.filter,
                    prompt: Text(LibraryCopy.entry(.chrome(.filterPlaceholder)).body)
                )
        }
        .task { await model.load() }
        .onChange(of: model.filter) { _, _ in model.refilter() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            skeletonList

        case let .populated(servers):
            list(servers)

        case .empty:
            pane(.state(.empty), icon: .book)

        case let .emptyFiltered(query, total):
            pane(
                .state(.emptyFiltered),
                icon: .search,
                extra: [.query: query, .count: String(total)],
                action: { model.clearFilter() }
            )

        case .failed:
            pane(.state(.failed), icon: .bang, tint: .fail)

        case .offline:
            // Its own state. The tint is a label tier, not `--attn`: a router that is not running
            // asks for an action rather than a decision.
            pane(.state(.offline), icon: .bolt)
        }
    }

    private func list(_ servers: [MCPServer]) -> some View {
        List {
            Text(resolved(.chrome(.subtitle), extra: [.count: String(servers.count)]).body)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.t2.color)
                .listRowSeparator(.hidden)

            ForEach(servers) { server in
                LibraryRow(server: server)
            }

            skillsAbsentBlock

            Text(LibraryCopy.entry(.chrome(.footer)).body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)

            // The narrowing, which moved here from the placeholder this item retires. Its
            // placement is inherited: `PairingCopy` put it on the library surface as "the surface
            // most likely to be mistaken for an install surface", and that is still true.
            Text(LibraryCopy.entry(.chrome(.narrowing)).body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    /// An absence stated as a fact, not drawn as an empty list.
    private var skillsAbsentBlock: some View {
        let entry = LibraryCopy.entry(.state(.skillsAbsent))
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
        .padding(PhoneMetric.normal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhoneMetric.cardRadius, style: .continuous)
                .fill(ColorToken.f3.color)
        )
        .listRowSeparator(.hidden)
    }

    private var skeletonList: some View {
        List {
            ForEach(0 ..< 4, id: \.self) { _ in TriageSkeletonRow() }
        }
        .listStyle(.plain)
    }

    private func pane(
        _ key: LibraryCopy.Key,
        icon: Icon,
        tint: ColorToken = .t3,
        extra: [LibraryCopy.Token: String] = [:],
        action: (() -> Void)? = nil
    ) -> some View {
        let entry = resolved(key, extra: extra)
        return PhoneMessageState(
            headline: entry.headline,
            message: entry.body,
            actionLabel: entry.actionLabel,
            icon: icon,
            tint: tint,
            action: action ?? { Task { await model.load() } }
        )
        .frame(maxHeight: .infinity)
    }

    private func resolved(
        _ key: LibraryCopy.Key,
        extra: [LibraryCopy.Token: String] = [:]
    ) -> LibraryCopy.Entry {
        var values = extra
        values[.mac] = model.macName ?? "your Mac"
        return LibraryCopy.entry(key).resolved(values)
    }
}

/// One server row. Every fact is a named `MCPServer` field.
struct LibraryRow: View {
    let server: MCPServer

    private var fact: LibraryRowFact { LibraryRowFact.resolve(for: server) }

    var body: some View {
        HStack(spacing: PhoneMetric.snug) {
            IconView(server.transport == .stdio ? .bolt : .conduit)
                .foregroundStyle(ColorToken.t3.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                Text(server.name)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(TriagePresentation.libraryFacts(for: server).joined(separator: " · "))
                    // Instrument data, and every element a named field.
                    .typeRole(.caption, monospaced: true)
                    // `--live` appears here and only here, meaning exactly what it means: a child
                    // process is running.
                    .foregroundStyle(fact.isLive ? ColorToken.live.color : ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: PhoneMetric.minimumTarget)
        .padding(.vertical, PhoneMetric.tight)
    }
}
