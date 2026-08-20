import Foundation

/// One server as the app sees it.
///
/// **Env and header VALUES never appear here** — only their key names. This endpoint is reachable
/// by anything that can open a loopback socket, and a server's env is where its API keys live
/// (B10). The construction below never receives a value: it maps the pair arrays to their keys
/// before anything else touches them.
///
/// Every member is placed in the reference's own order, and a member whose value is `undefined` is
/// **omitted** rather than emitted as null (S3, B2, B3).
public enum Describe {
    public static func row(_ upstream: UpstreamConfig, _ deps: ControlDeps) -> JSONValue {
        let name = upstream.name
        // The same name as UTF-16 code units, which is how every port keyed by a server name
        // compares it. Swift's `==` is canonical equivalence, so a decomposed live row would match
        // a composed config entry and report another server's state (S5, B24).
        let key = JSString(name)
        let entry = deps.manifest.entry(named: name)
        // `.find` — first match. `last(where:)` passes any single-row fixture and is wrong (B6, B7).
        let live = deps.pool.firstStatus(key)
        let stat = deps.usage.statFor(name)
        let pending = deps.pool.firstPending(key)
        // `!isStdio(u) && u.oauth !== false` — `oauth` absent means supported, because the test is
        // against `false` specifically, not against nullish.
        let needsAuth = !upstream.isStdio && upstream.oauth != false

        var members: [JSONMember] = [
            JSONMember(key: "name", value: .string(JSString(name))),
            JSONMember(key: "transport", value: .string(JSString(upstream.transport.rawValue))),
            // `?? 'idle'` and `?? 0` are nullish, so a live row reporting 0 stays 0 (S2).
            JSONMember(key: "state", value: .string(JSString(live?.state ?? "idle"))),
            JSONMember(key: "inFlight", value: .number(Double(live?.inFlight ?? 0))),
            JSONMember(key: "callsServed", value: .number(Double(live?.callsServed ?? 0))),
            JSONMember(key: "idleSec", value: .number(Double(live?.idleSec ?? 0)))
        ]

        members.append(contentsOf: transportMembers(upstream))
        members.append(JSONMember(
            key: "hash", value: .string(JSString(UpstreamHash.hash(upstream)))
        ))
        members.append(contentsOf: manifestMembers(entry))
        members.append(contentsOf: scopeMembers(upstream))

        // `placardFor` is `u.placard || (entry.error && {reason: entry.error})`, and `u.placard` is
        // the RAW config value — the reference echoes whatever was written there, including a bare
        // string. `ServerParser` types it into a `Placard`, which drops anything that is not the
        // `{reason, …}` shape, so a config saying `"placard": "on hold"` reported no placard at all
        // while the reference reports the string. Same rule as command/args/projects above.
        if let raw = upstream.raw.member("placard"), raw.isTruthy {
            members.append(JSONMember(key: "placard", value: raw))
        } else if let placard = ToolUnion.placardFor(upstream, entry: entry) {
            members.append(JSONMember(key: "placard", value: placardValue(placard)))
        }
        if let entry, entry.pending?.isTruthy == true {
            members.append(JSONMember(key: "pendingChange", value: pendingChange(entry)))
        }
        members.append(JSONMember(key: "auth", value: authValue(
            needsAuth: needsAuth, name: key, deps: deps, pending: pending, entry: entry
        )))
        // The stat is passed through unchanged, including members this item does not model (B9).
        members.append(JSONMember(key: "usage", value: (stat ?? .zero).value))
        return .object(members)
    }

    /// The transport-conditional block, which lands between `idleSec` and `hash` — the spread's
    /// position in the reference's object literal, and therefore its position on the wire.
    private static func transportMembers(_ upstream: UpstreamConfig) -> [JSONMember] {
        var members: [JSONMember] = []
        if upstream.isStdio {
            // `command: u.command` and `args: u.args ?? []` in `config.ts`, both **raw**. The typed
            // fields cannot stand in: `ServerParser` coerces `command` to a string and maps `args`
            // to `[String]`, so a config carrying `"command": true` or `"args": [1,2]` — both of
            // which the reference accepts and stores — would be reported back as `"true"` and
            // `["1","2"]`. `cwd` was already read this way; these are the same rule.
            members.append(JSONMember(
                key: "command",
                value: upstream.raw.member("command") ?? .string(JSString(upstream.command ?? ""))
            ))
            members.append(JSONMember(key: "args", value: rawOrEmptyArray(upstream.raw.member("args"))))
            // `cwd` is the one member where absent and null are both reachable and different:
            // `JSON.stringify` omits an undefined member and emits `"cwd":null` for a null one, so
            // the raw config is consulted rather than the parsed optional, which collapses them.
            if let raw = upstream.raw.member("cwd") {
                members.append(JSONMember(key: "cwd", value: raw))
            }
            members.append(JSONMember(key: "envKeys", value: .array(sortedKeys(upstream.env))))
        } else {
            members.append(JSONMember(key: "url", value: .string(JSString(upstream.url ?? ""))))
            members.append(JSONMember(
                key: "headerKeys", value: .array(sortedKeys(upstream.headers))
            ))
        }
        return members
    }

    /// The tool counts and index metadata read off the manifest entry.
    private static func manifestMembers(_ entry: CachedServer?) -> [JSONMember] {
        // `entry?.error ? 0 : …` is JavaScript truthiness, so an `error: ""` is **false** and the
        // cached tools survive. A Swift `!= nil` reports zero tools here and passes every recorded
        // fixture (S1, B5).
        let failed = entry?.hasError ?? false
        let tools = entry?.tools ?? []
        var members: [JSONMember] = [
            JSONMember(key: "tools", value: .number(failed ? 0 : Double(tools.count))),
            JSONMember(
                key: "toolNames",
                value: .array(failed ? [] : tools.map { .string($0.name ?? JSString("")) })
            )
        ]
        // A member present in the manifest file is either a value or an explicit null, and both
        // serialise; only an absent member is omitted. That is the whole of the distinction, and
        // reading the member rather than a parsed optional is what preserves it (S3).
        if let builtAt = entry?.member("builtAt") {
            members.append(JSONMember(key: "indexedAt", value: builtAt))
        }
        if let error = entry?.member("error") {
            members.append(JSONMember(key: "indexError", value: error))
        }
        return members
    }

    /// `projects` and `warm` — one nullish default and one truthiness coercion, deliberately
    /// asymmetric because the reference is.
    private static func scopeMembers(_ upstream: UpstreamConfig) -> [JSONMember] {
        [
            // `projects: u.projects ?? []`, and `u.projects` is `s.projects` verbatim. The `??` is
            // nullish, so a truthy non-array survives to the wire. PATCH already preserves such a
            // value on disk (`b.projects?.length` is a property read), so reporting `[]` here made
            // the router deny a value it had just written.
            JSONMember(key: "projects", value: rawOrEmptyArray(upstream.raw.member("projects"))),
            JSONMember(
                key: "warm", value: .bool(upstream.raw.member("warm")?.isTruthy ?? false)
            )
        ]
    }

    /// `x ?? []` — **nullish**, so `false`, `0` and `"abc"` all survive and only absent or `null`
    /// becomes an empty array.
    private static func rawOrEmptyArray(_ member: JSONValue?) -> JSONValue {
        guard let member, member != .null else { return .array([]) }
        return member
    }

    private static func pendingChange(_ entry: CachedServer) -> JSONValue {
        var change: [JSONMember] = []
        if let seenAt = entry.pending?.member("seenAt") {
            change.append(JSONMember(key: "seenAt", value: seenAt))
        }
        change.append(JSONMember(
            key: "count",
            value: .number(Double(DiffTools.diff(
                before: entry.tools, after: entry.pendingTools
            ).count))
        ))
        return .object(change)
    }

    /// `Object.keys(map).sort()` — key **names** only, ordered by UTF-16 code unit.
    ///
    /// Two things are load-bearing. The values never leave this function, which is what makes B10
    /// structural rather than a promise. And the ordering is `JSString`'s code-unit comparison, not
    /// Swift's `<` on `String`: the two disagree above the BMP, and they disagree about canonically
    /// equivalent keys, which JavaScript keeps distinct (S5, B4).
    private static func sortedKeys(_ pairs: [JSStringPair]) -> [JSONValue] {
        pairs.map(\.key).sorted { $0 < $1 }.map { JSONValue.string($0) }
    }

    private static func placardValue(_ placard: Placard) -> JSONValue {
        var members = [JSONMember(key: "reason", value: .string(JSString(placard.reason)))]
        if let substitute = placard.substitute {
            members.append(JSONMember(key: "substitute", value: .string(JSString(substitute))))
        }
        if let until = placard.until {
            members.append(JSONMember(key: "until", value: .string(JSString(until))))
        }
        return .object(members)
    }

    private static func authValue(
        needsAuth: Bool,
        name: JSString,
        deps: ControlDeps,
        pending: PendingAuthRow?,
        entry: CachedServer?
    ) -> JSONValue {
        guard needsAuth else {
            return .object([
                JSONMember(key: "supported", value: .bool(false)),
                JSONMember(key: "authorized", value: .bool(true))
            ])
        }
        /*
         * `authorized` used to be `hasTokens(name)` alone, which reports that a FILE exists.
         * Measured on a live router on 2026-08-20: this object carried
         * `indexError: "[-32603] Internal error: Authentication required"` and
         * `auth.authorized: true` at the same time, three lines apart, because the token file
         * was on disk and the server had stopped honouring the refresh inside it. REQ-007 says
         * the router never displays what it does not observe, and a field named `authorized`
         * reporting a fact about the filesystem is exactly that.
         *
         * Read from the MANIFEST rather than from the pool's pending map, deliberately: the
         * pending map is in-memory and empty on a fresh start, while the recorded index error
         * persists, so a restarted router would otherwise report `authorized: true` again until
         * something happened to re-index.
         */
        let rejection: String? = {
            guard case let .string(text)? = entry?.member("error"),
                  AuthRefusal.isRefusal(text.string) else { return nil }
            // A refusal the manifest recorded BEFORE the credential was last authorized is stale,
            // and reporting it tells the user the credential they have just fixed is still being
            // refused. `control.ts` carries the measurement this mirrors: completing an
            // authorization re-indexes, that re-index is fire-and-forget on both routers, and a
            // `GET /servers/:name` immediately afterwards may read a manifest written before the
            // browser hop. Whichever side loses that race is a property of the machine that day.
            if let authorizedAt = deps.auth.authorizedAt(name),
               case let .string(builtAt)? = entry?.member("builtAt"),
               AuthStamp.isAfter(authorizedAt, builtAt.string) { return nil }
            return text.string
        }()
        var members = [
            JSONMember(key: "supported", value: .bool(true)),
            JSONMember(
                key: "authorized",
                value: .bool(deps.auth.hasTokens(name) && rejection == nil)
            )
        ]
        // Present only when we hold a credential the upstream has refused, which is the state
        // that has a remedy: `mcp-router auth <name>`. Absent means either working, or never
        // authorized at all — and those two are told apart by `authorizedAt`, which a server
        // that has never authorized does not carry.
        if let rejection {
            members.append(JSONMember(key: "rejected", value: .string(JSString(rejection))))
        }
        // Both are omitted when undefined, which is what the recorded pending-auth fixture shows:
        // a supported, unauthorized server carrying neither key.
        if let at = deps.auth.authorizedAt(name) {
            members.append(JSONMember(key: "authorizedAt", value: .string(JSString(at))))
        }
        if let pending {
            members.append(JSONMember(key: "pendingUrl", value: .string(JSString(pending.url))))
        }
        return .object(members)
    }
}
