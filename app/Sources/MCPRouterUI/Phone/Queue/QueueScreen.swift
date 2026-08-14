import MCPRouterKit
import Observation
import SwiftUI

/// The Queue's state: what is on this phone, and nothing about a Mac.
@MainActor
@Observable
public final class QueueModel {
    @ObservationIgnored public let queue: any CapabilityQueueReader

    public var macName: String?
    public var connection: ConnectionState

    public internal(set) var state: QueueSurfaceState = .loading
    public internal(set) var undo: QueuedCapability?

    public init(
        queue: any CapabilityQueueReader,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        self.queue = queue
        self.connection = connection
        self.macName = macName
    }

    public func load() async {
        let items: Result<[QueuedCapability], CapabilityQueueError>
        do {
            items = try await .success(queue.all())
        } catch let error as CapabilityQueueError {
            items = .failure(error)
        } catch {
            items = .failure(.unreadable(error.localizedDescription))
        }
        state = QueueSurfaceState.resolve(items: items)
    }

    /// Undoable rather than confirmed. Removing something from your own outbox has no blast radius,
    /// and the named-consequence dialog `DESIGN.md` §9 reserves is the Mac's.
    public func remove(_ item: QueuedCapability) async {
        try? await queue.remove(item.id)
        undo = item
        await load()
    }

    /// There is no re-enqueue on the reader, so undo is offered only where the surface can honour
    /// it. This is stated rather than silently degraded: the reader removes, and putting an item
    /// back needs the writer, which the Queue deliberately does not hold — a surface that can write
    /// to the queue is a surface that can queue things, and this one only shows them.
    public func clearUndo() {
        undo = nil
    }
}

/// Queue: what this phone has queued, and when it queued it.
///
/// **No Mac-side status and no send control**, and neither is an omission. There is no transport
/// (M6 deferred it as D-m6-a), so a Mac-side disposition is not observable and a send act is not
/// available. The prototype's WAITING / ADDED / NO badges and its "last seen just now" subtitle are
/// removed rather than reworded.
public struct QueueScreen: View {
    @State private var model: QueueModel

    public init(
        queue: any CapabilityQueueReader,
        connection: ConnectionState = .reachable,
        macName: String? = nil
    ) {
        _model = State(wrappedValue: QueueModel(
            queue: queue,
            connection: connection,
            macName: macName
        ))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(PhoneShell<EmptyView>.Tab.queue.title)
                .background(ColorToken.ground.color)
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            skeletonList

        case let .populated(items):
            list(items)

        case let .writeRefused(items):
            list(items, banner: .state(.writeRefused))

        case .empty:
            pane(.state(.empty), icon: .tray)

        case .unreadable:
            // The state this surface exists to get right. An unreadable queue is never an empty
            // queue: something is saved, this build cannot decode it, and nothing has been deleted.
            pane(.state(.unreadable), icon: .warn, tint: .fail)
        }
    }

    private func list(_ items: [QueuedCapability], banner: QueueCopy.Key? = nil) -> some View {
        List {
            if !model.connection.canQueue {
                pairingBanner
            } else {
                Text(resolved(.chrome(.subtitle)).body)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
            }

            if let banner {
                bannerRow(banner)
            }

            if let undone = model.undo {
                UndoBar(
                    text: resolved(.chrome(.undoRemoved), extra: [.name: undone.displayName]).body,
                    onUndo: { model.clearUndo() }
                )
                .listRowSeparator(.hidden)
            }

            // No section header. The list is one section, so a header partitions nothing, and the
            // only word it could carry is the badge vocabulary this surface removes.
            ForEach(QueueSurfaceState.ordered(items)) { item in
                QueueRow(
                    item: item,
                    onRemove: { Task { await model.remove(item) } }
                )
            }

            Text(resolved(.chrome(.footer)).body)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private var pairingBanner: some View {
        let entry = resolved(.state(.neverPaired))
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
            if entry.carriesNarrowing {
                Text(PairingCopy.neverInstalls)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func bannerRow(_ key: QueueCopy.Key) -> some View {
        let entry = resolved(key)
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

    private func pane(_ key: QueueCopy.Key, icon: Icon, tint: ColorToken = .t3) -> some View {
        let entry = resolved(key)
        return PhoneMessageState(
            headline: entry.headline,
            message: entry.body,
            actionLabel: entry.actionLabel,
            icon: icon,
            tint: tint,
            action: { Task { await model.load() } }
        )
        .frame(maxHeight: .infinity)
    }

    private var skeletonList: some View {
        List {
            ForEach(0 ..< 3, id: \.self) { _ in TriageSkeletonRow() }
        }
        .listStyle(.plain)
    }

    private func resolved(
        _ key: QueueCopy.Key,
        extra: [QueueCopy.Token: String] = [:]
    ) -> QueueCopy.Entry {
        var values = extra
        values[.mac] = model.macName ?? "your Mac"
        return QueueCopy.entry(key).resolved(values)
    }
}

/// One queued row: what it is, what it would be able to do, and when this phone queued it.
struct QueueRow: View {
    let item: QueuedCapability
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PhoneMetric.snug) {
            IconView(item.install?.type == .stdio ? .bolt : .conduit)
                .foregroundStyle(ColorToken.t3.color)
                .frame(width: PhoneMetric.tile, height: PhoneMetric.tile)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PhoneMetric.tight) {
                Text(item.displayName)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                CapabilityLine(summary: summary)

                Text(
                    QueueCopy.entry(.chrome(.stamp))
                        .resolved([.when: TriagePresentation.queuedStamp(item.queuedAt)]).body
                )
                // Instrument data — `DESIGN.md` §2 — and the only temporal fact this surface may
                // state, because it is the only one the phone observed.
                .typeRole(.caption, monospaced: true)
                .foregroundStyle(ColorToken.t3.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                IconView(.chev)
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(ColorToken.t3.color)
                    .frame(width: PhoneMetric.minimumTarget, height: PhoneMetric.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                QueueCopy.entry(.chrome(.remove))
                    .resolved([.name: item.displayName]).body
            )
        }
        .padding(.vertical, PhoneMetric.tight)
    }

    /// The row carries the same derived capability line the Triage row does — one derivation, three
    /// renderings, so a queued item cannot describe itself differently from the row it came from.
    ///
    /// `archived` is nil rather than guessed: `QueuedCapability` does not carry it, and defaulting
    /// it to `false` would state "the repository is maintained" from a field nobody stored.
    private var summary: CapabilitySummary.Resolved {
        CapabilitySummary.resolve(install: item.install, archived: nil)
    }
}
