import Foundation

/// The only shape the app may send to the control API's PATCH.
///
/// The fields mirror what the router actually accepts on
/// `PATCH /servers/:name` — `projects`, `warm`, `idleMs`, `placard` and `disabled`. Anything else it
/// silently ignores, so inventing a field here would produce a call that appears to work and
/// changes nothing. Approving a held tool-surface change is **not** part of this shape: it is a
/// separate `POST /servers/:name/approve`, and it is modelled as its own operation on
/// `ControlAPIClient`.
///
/// **`command`, `args` and `env` are absent by construction, and that is the whole point.** A
/// control API that can rewrite a command line is a control API that can run anything on the
/// machine, so the guarantee is structural rather than a validation rule someone could later
/// relax: there is no field here to set.
///
/// `ControlContractTests` asserts this three ways, because each alone can be defeated. It checks
/// the **encoded JSON**, since a computed property or a `CodingKeys` mapping could put a
/// forbidden key on the wire without ever being a stored property; it checks the **stored
/// properties**, since an added `var command: String?` left nil is omitted by the default encoder
/// and would sail past a JSON-only check until the day someone assigned it; and it exercises
/// **`encodedBody()`**, which is the path the app actually uses and the only one that can catch a
/// caller-supplied encoder renaming a field onto a forbidden key.
public struct ServerPatch: Codable, Hashable, Sendable {
    /// What to do with the server's placard, if anything.
    ///
    /// Three states, because the wire has three. The router branches on `'placard' in b`
    /// (`src/control.ts` ~line 382), so an omitted key leaves the mark alone and an explicit
    /// `null` removes it. `Placard?` alone cannot express that difference — the synthesised
    /// encoder omits a nil optional, so "clear it" and "leave it" produce identical bytes. This
    /// type's own documentation said "or clear the mark" while having no way to send one, which is
    /// a documented capability that silently did nothing.
    public enum PlacardEdit: Hashable, Sendable {
        /// Mark the server inoperative with this reason.
        case set(Placard)
        /// Remove the mark. Encodes as an explicit `null`, which is what the router reads.
        case clear
    }

    /// Restrict the server to these project directories. An empty array clears the restriction;
    /// omitting the field leaves it unchanged.
    public var projects: [String]?
    /// Keep the server resident rather than reaping it when idle.
    public var warm: Bool?
    /// Override how long this server may sit idle before it is reaped.
    public var idleMs: Int?
    /// Mark the server inoperative with a reason, or clear the mark.
    public var placard: PlacardEdit?
    /// Stop serving this server entirely, or start again.
    ///
    /// Not a placard. A placard leaves the tools listed and answering with a reason; this removes
    /// them from `tools/list` and refuses them by name, while the manifest row, the digest and the
    /// approved surface all survive — so switching a server back on cannot launder an approval the
    /// user refused by switching it off.
    ///
    /// A plain optional rather than the three-state `PlacardEdit` beside it, because the router
    /// reads this one with `'disabled' in b` and then plain truthiness: `false` and `null` both
    /// remove the member, so "off" and "clear it" are the same request and there is no third state
    /// to express.
    public var disabled: Bool?

    public init(
        projects: [String]? = nil,
        warm: Bool? = nil,
        idleMs: Int? = nil,
        placard: PlacardEdit? = nil,
        disabled: Bool? = nil
    ) {
        self.projects = projects
        self.warm = warm
        self.idleMs = idleMs
        self.placard = placard
        self.disabled = disabled
    }

    private enum CodingKeys: String, CodingKey {
        case projects, warm, idleMs, placard, disabled
    }

    /// Written by hand for one reason: `encodeNil` is the only way to put an explicit `null` on
    /// the wire, and the synthesised encoder never emits one.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(projects, forKey: .projects)
        try container.encodeIfPresent(warm, forKey: .warm)
        try container.encodeIfPresent(idleMs, forKey: .idleMs)
        switch placard {
        case .none: break
        case .clear: try container.encodeNil(forKey: .placard)
        case let .set(placard): try container.encode(placard, forKey: .placard)
        }
        try container.encodeIfPresent(disabled, forKey: .disabled)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([String].self, forKey: .projects)
        warm = try container.decodeIfPresent(Bool.self, forKey: .warm)
        idleMs = try container.decodeIfPresent(Int.self, forKey: .idleMs)
        if container.contains(.placard) {
            placard = try container.decodeNil(forKey: .placard)
                ? .clear
                : .set(container.decode(Placard.self, forKey: .placard))
        } else {
            placard = nil
        }
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
    }

    /// The fields the control API will never accept, named so the tests can assert on them and so
    /// the next person to extend this type meets the rule before adding a case.
    public static let forbiddenWireKeys: Set<String> = ["command", "args", "env"]

    /// Exactly the keys this type is allowed to put on the wire. `encodedBody()` enforces this at
    /// runtime, so a new field cannot reach the router without a deliberate edit here.
    public static let permittedWireKeys: Set<String> = [
        "projects", "warm", "idleMs", "placard", "disabled"
    ]

    /// Why serialising a patch is a function on the type rather than something each caller does
    /// with its own `JSONEncoder`.
    ///
    /// A test that encodes a value it constructed itself proves what *that encoder* did to *that
    /// value*, and nothing about the bytes the app actually sends. Two things defeat it. A caller
    /// can configure its own encoder — `keyEncodingStrategy` can rename `warm` to `command` on the
    /// way out, and the type never sees it happen. And a field added later as
    /// `public var command: String?` is omitted by the synthesised encoder while it stays nil, so
    /// a key-set assertion stays green right up until the day someone assigns it.
    ///
    /// So this is the one sanctioned way to turn a patch into a request body: it fixes the encoder
    /// configuration rather than accepting one, and it checks the key set of the bytes it is about
    /// to return. The check runs on the real output, at the moment of use, which is the only place
    /// a rename or a late-added field is still visible.
    public func encodedBody() throws -> Data {
        // Deliberately a fresh, default-configured encoder. Accepting one as a parameter would
        // reintroduce exactly the hole this closes.
        let data = try JSONEncoder().encode(self)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControlWireError.bodyWasNotAJSONObject
        }
        let keys = Set(object.keys)

        let forbidden = keys.intersection(Self.forbiddenWireKeys)
        guard forbidden.isEmpty else {
            throw ControlWireError.forbiddenKeys(forbidden.sorted())
        }
        let unexpected = keys.subtracting(Self.permittedWireKeys)
        guard unexpected.isEmpty else {
            throw ControlWireError.unpermittedKeys(unexpected.sorted())
        }
        return data
    }
}

/// Refusals raised while turning a request shape into bytes.
///
/// Separate from `ControlAPIError`, which describes a request that was *sent* and went wrong. These
/// mean the request was never sent, because building it would have violated the contract — a
/// distinction worth keeping, since the two call for opposite responses: retry the one, fix the
/// code for the other.
public enum ControlWireError: Error, Equatable, Sendable {
    /// The encoder produced something other than a JSON object.
    case bodyWasNotAJSONObject
    /// A key the control API must never receive reached the encoded body.
    case forbiddenKeys([String])
    /// A key outside the permitted set reached the encoded body.
    case unpermittedKeys([String])
}
