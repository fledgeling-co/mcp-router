import Foundation

/// What went wrong reading a queued item, kept as three outcomes rather than one.
///
/// The same three shapes `PairingPayloadError` uses, and for the same reason: "that isn't from
/// Conduit", "your phone is running a newer version" and "that item could not be read" send the
/// reader to three different places, and one collapsed message fits none of them.
public enum InboxEnvelopeError: Error, Equatable, Sendable {
    /// Not one of ours at all.
    case notAQueueItem
    /// Ours, a version this build does not speak.
    case unsupportedVersion(found: Int)
    /// Ours and our version, but the body did not hold up. The failing field is named.
    case malformedPayload(detail: String)
}

/// What a phone is allowed to say about something it queued.
///
/// **A coordinate, never a description.** The phone names *which* entry it means; the Mac reads that
/// entry from the registry itself and derives what it does. So a compromised or spoofed sender
/// cannot present a shell command as "read-only" — it has no field in which to say anything about
/// capability at all. That is the security argument, and it is also why the contract I3 has to
/// implement is five facts rather than a schema of judgements.
///
/// Decoded envelope-first, exactly as `PairingPayload` is, because `JSONDecoder` cannot say *why* it
/// stopped in terms a reader needs. Nothing here is `try?`-and-default: an absent field is a failure
/// with a name, never a zero value that flows on to be rendered (`SWIFT_PRACTICES.md` §2).
public struct InboxEnvelope: Sendable, Equatable, Identifiable {
    /// The discriminator. Anything not carrying exactly this is not ours.
    public static let discriminator = "mcp-router-queue"

    /// The versions this build speaks. **A closed set**, so an unknown one is a named outcome rather
    /// than a silent empty read. A later phone item adds to this rather than widening v1.
    public static let supportedVersions: Set<Int> = [1]

    public let version: Int
    /// The item's stable identity, minted by the phone. Row identity comes from this, so a list that
    /// reorders as items arrive does not bleed state between rows.
    public let id: String
    /// The registry entry id — **the coordinate the Mac resolves.**
    public let entryID: String
    /// The name the phone displayed.
    ///
    /// Rendered **only** when the entry cannot be read, so a Partial row still says which thing it
    /// is. Where the Mac resolved the entry it shows what it read, because that is the name attached
    /// to the thing that would actually run.
    public let displayName: String
    public let queuedAt: Date
    /// Which paired device sent it.
    public let deviceName: String

    private struct Envelope: Decodable {
        let t: String?
        let v: Int?
    }

    private struct Body: Decodable {
        let id: String
        let entry: String
        let name: String
        let queued: String
        let device: String
    }

    public static func decode(_ text: String) throws(InboxEnvelopeError) -> InboxEnvelope {
        guard let data = text.data(using: .utf8) else { throw .notAQueueItem }
        let version = try recognisedVersion(in: data)
        return try validated(decodedBody(in: data), version: version)
    }

    private static func recognisedVersion(in data: Data) throws(InboxEnvelopeError) -> Int {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            // Unparseable bytes are indistinguishable from someone else's payload, and that is the
            // honest reading: we cannot claim a version problem for bytes we could not parse.
            throw .notAQueueItem
        }
        guard envelope.t == discriminator else { throw .notAQueueItem }
        guard let version = envelope.v else { throw .malformedPayload(detail: "no version") }
        guard supportedVersions.contains(version) else { throw .unsupportedVersion(found: version) }
        return version
    }

    private static func decodedBody(in data: Data) throws(InboxEnvelopeError) -> Body {
        do {
            return try JSONDecoder().decode(Body.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw .malformedPayload(detail: "missing \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, context) {
            throw .malformedPayload(
                detail: "wrong type for \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch {
            throw .malformedPayload(detail: "unreadable body")
        }
    }

    /// A field can be present, correctly typed and still meaningless. An empty `entry` is the one
    /// that matters most: it would resolve to nothing and render as a permanently Partial row that
    /// nobody could act on or explain.
    private static func validated(
        _ body: Body,
        version: Int
    ) throws(InboxEnvelopeError) -> InboxEnvelope {
        guard !body.id.isEmpty else { throw .malformedPayload(detail: "empty id") }
        guard !body.entry.isEmpty else { throw .malformedPayload(detail: "empty entry") }
        guard !body.name.isEmpty else { throw .malformedPayload(detail: "empty name") }
        guard !body.device.isEmpty else { throw .malformedPayload(detail: "empty device") }
        guard let queued = ISO8601Instant.parse(body.queued) else {
            throw .malformedPayload(detail: "queued is not an ISO-8601 instant")
        }
        return InboxEnvelope(
            version: version,
            id: body.id,
            entryID: body.entry,
            displayName: body.name,
            queuedAt: queued,
            deviceName: body.device
        )
    }

    public init(
        version: Int,
        id: String,
        entryID: String,
        displayName: String,
        queuedAt: Date,
        deviceName: String
    ) {
        self.version = version
        self.id = id
        self.entryID = entryID
        self.displayName = displayName
        self.queuedAt = queuedAt
        self.deviceName = deviceName
    }
}

/// One row of the inbox: what the phone said, and what the Mac managed to resolve.
///
/// **`resolved == nil` IS the Partial state**, rather than a flag beside it. That is what makes
/// "an unreadable item cannot be accepted" structural instead of a rule the view has to remember:
/// the accept path takes an `AcceptableInboxItem`, which cannot be constructed without an entry.
public struct InboxItem: Sendable, Equatable, Identifiable {
    public var id: String { envelope.id }

    public let envelope: InboxEnvelope
    public let resolved: RegistryEntry?

    public init(envelope: InboxEnvelope, resolved: RegistryEntry?) {
        self.envelope = envelope
        self.resolved = resolved
    }

    /// The name to render: what the Mac read where it could, and what the phone said where it could
    /// not. Never both, and never a placeholder.
    public var title: String {
        resolved?.displayName ?? envelope.displayName
    }

    public var isPartial: Bool { resolved == nil }
}

/// Permission to accept an item, which only a resolved item can obtain.
///
/// The same device `ScaffoldedDestination` used before M6 retired it, applied to the decision that
/// now matters most: a plain `InboxItem` parameter would let a future edit hand the installer an
/// item whose entry nobody could read, and nothing would object until a server was declared from a
/// name the Mac never resolved. This makes that a `nil` at the call site instead.
public struct AcceptableInboxItem: Sendable, Equatable {
    public let item: InboxItem
    public let entry: RegistryEntry

    public init?(_ item: InboxItem) {
        guard let entry = item.resolved else { return nil }
        self.item = item
        self.entry = entry
    }
}

/// What happened to an item the user acted on, held for the single-slot undo.
///
/// `DESIGN.md` §9 asks for reversible-and-reported rather than confirmed. One slot rather than a
/// stack, deliberately: a deeper history would promise a record this surface does not keep.
public enum InboxDisposition: Sendable, Equatable {
    case declined(InboxItem)
    case accepted(InboxItem)

    public var item: InboxItem {
        switch self {
        case let .declined(item), let .accepted(item): item
        }
    }
}
