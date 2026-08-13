import Foundation

/// The only shape the app may send to the control API's PATCH.
///
/// The fields mirror what the router actually accepts on
/// `PATCH /servers/:name` — `projects`, `warm`, `idleMs` and `placard`. Anything else it
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
    /// Restrict the server to these project directories. An empty array clears the restriction;
    /// omitting the field leaves it unchanged.
    public var projects: [String]?
    /// Keep the server resident rather than reaping it when idle.
    public var warm: Bool?
    /// Override how long this server may sit idle before it is reaped.
    public var idleMs: Int?
    /// Mark the server inoperative with a reason, or clear the mark.
    public var placard: Placard?

    public init(
        projects: [String]? = nil,
        warm: Bool? = nil,
        idleMs: Int? = nil,
        placard: Placard? = nil
    ) {
        self.projects = projects
        self.warm = warm
        self.idleMs = idleMs
        self.placard = placard
    }

    /// The fields the control API will never accept, named so the tests can assert on them and so
    /// the next person to extend this type meets the rule before adding a case.
    public static let forbiddenWireKeys: Set<String> = ["command", "args", "env"]

    /// Exactly the keys this type is allowed to put on the wire. `encodedBody()` enforces this at
    /// runtime, so a new field cannot reach the router without a deliberate edit here.
    public static let permittedWireKeys: Set<String> = ["projects", "warm", "idleMs", "placard"]

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
