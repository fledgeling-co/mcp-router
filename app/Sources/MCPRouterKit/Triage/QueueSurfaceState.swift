import Foundation

/// What the Queue surface is showing.
///
/// **Two of `DESIGN.md` §5's nine states have no case here, and both absences are decisions.**
/// There is no `partial`: the queue is one local file read whole, so there is no half of it to
/// arrive. There is no `offline`: the queue is local, it reads and writes without a router and
/// without a Mac, so there is nothing remote to be offline *from*. Writing plausible copy for a
/// state that cannot occur is scaffolding wearing a design's clothes, so neither is written.
public enum QueueSurfaceState: Sendable, Equatable {
    case populated([QueuedCapability])
    case empty
    case loading
    /// A17, and the state this surface exists to get right. The file is present and will not
    /// decode. **Never rendered as `empty`.**
    case unreadable
    /// A write was refused, so an item the user tried to queue is not there. Distinct from
    /// `unreadable`: the file is fine, the write was not.
    case writeRefused([QueuedCapability])

    public static func resolve(
        items: Result<[QueuedCapability], CapabilityQueueError>?,
        lastWriteFailed: Bool = false
    ) -> QueueSurfaceState {
        guard let items else { return .loading }

        switch items {
        case .failure:
            // Every `CapabilityQueueError` reaching a *read* is an unreadable file: a missing file
            // is an empty queue and never throws, which is the one place emptiness is honest.
            return .unreadable
        case let .success(list):
            if lastWriteFailed { return .writeRefused(list) }
            return list.isEmpty ? .empty : .populated(list)
        }
    }

    public var copyKey: QueueCopy.Key? {
        switch self {
        case .populated, .loading: nil
        case .empty: .state(.empty)
        case .unreadable: .state(.unreadable)
        case .writeRefused: .state(.writeRefused)
        }
    }

    /// Newest first. The user's most recent decision is the one they are most likely looking for.
    public static func ordered(_ items: [QueuedCapability]) -> [QueuedCapability] {
        items.sorted { $0.queuedAt > $1.queuedAt }
    }
}
