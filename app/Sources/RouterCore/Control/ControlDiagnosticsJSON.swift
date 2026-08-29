import Foundation

/// The two diagnostics documents, member by member — R22.
///
/// Hand-built out of ``JSONMember`` rather than encoded from a `Codable`, which
/// `scripts/lint/no-wire-codable.sh` enforces across this surface.
extension ControlHandler {
    // MARK: - GET /diagnostics — the preview

    /// What a bundle would gather, and what it would redact, disclosing neither.
    ///
    /// Every number here is derived by the same code the bundle uses, not by a second count that
    /// could drift from it: the log tail is actually read, the usage window is actually taken. A
    /// preview that estimated would be a preview that could be wrong about the thing the user is
    /// being asked to approve.
    func previewValue(_ deps: ControlDeps) -> JSONValue {
        let (redactor, _) = redaction(deps)
        let tail = DiagnosticsBundle.logTail(path: deps.config.logPath, fileSystem: deps.fileSystem)
        let calls = deps.usage.recent(
            limit: Double(DiagnosticsBundle.usageRecordLimit), server: nil, cwd: nil
        )
        var categories: [JSONValue] = [
            categoryValue("servers", available: true, count: deps.config.upstreams.count),
            categoryValue("liveUpstreams", available: true, count: deps.pool.status().count),
            categoryValue("recentCalls", available: true, count: calls.count)
        ]
        switch tail {
        case let .lines(lines):
            categories.append(categoryValue("routerLog", available: true, count: lines.count))
        case let .unavailable(reason):
            categories.append(.object([
                JSONMember(key: "category", value: .string(JSString("routerLog"))),
                JSONMember(key: "available", value: .bool(false)),
                JSONMember(key: "reason", value: .string(JSString(reason)))
            ]))
        }
        return .object([
            JSONMember(key: "categories", value: .array(categories)),
            JSONMember(key: "redaction", value: redactionPlanValue(redactor)),
            JSONMember(key: "bundleRoute", value: .string(JSString("POST /diagnostics/bundle")))
        ])
    }

    private func categoryValue(_ name: String, available: Bool, count: Int) -> JSONValue {
        .object([
            JSONMember(key: "category", value: .string(JSString(name))),
            JSONMember(key: "available", value: .bool(available)),
            JSONMember(key: "count", value: .number(Double(count)))
        ])
    }

    /// What redaction will do, by key name and count.
    ///
    /// `unscrubbable` names the keys whose values are too short to use as scrub needles. It is the
    /// one place in either document where a specific key is singled out for a reason connected to
    /// its value, and it is still not a disclosure — "shorter than 8 characters" is the whole of it,
    /// and layer 1 withholds the value regardless. It is here because a reader about to send this
    /// bundle to somebody is entitled to know which values were not swept out of the free text.
    func redactionPlanValue(_ redactor: SecretRedactor) -> JSONValue {
        .object([
            JSONMember(key: "secretsKnown", value: .number(Double(redactor.needles.needles.count))),
            JSONMember(key: "unscrubbable", value: .array(
                redactor.needles.unscrubbable.map { entry in
                    .object([
                        JSONMember(key: "key", value: .string(JSString(entry.label))),
                        JSONMember(key: "reason", value: .string(JSString(entry.reason)))
                    ])
                }
            )),
            JSONMember(key: "homePathsElided", value: .bool(true))
        ])
    }

    // MARK: - POST /diagnostics/bundle

    /// The bundle.
    ///
    /// Built raw, then passed through layer 2 and layer 3 **once, here, at the end**. Every string
    /// in the document therefore goes through the scrubber by construction rather than because each
    /// site remembered to call it — which is the property that survives the next person adding a
    /// section.
    func bundleValue(_ deps: ControlDeps) -> JSONValue {
        let (redactor, elision) = redaction(deps)
        let gathered = JSONValue.object([
            JSONMember(key: "generatedAt", value: .string(JSString(
                JSDate.iso8601(milliseconds: deps.clock.nowMilliseconds)
            ))),
            JSONMember(key: "router", value: routerValue(deps)),
            JSONMember(key: "servers", value: .array(
                deps.config.upstreams.map { serverValue($0, deps) }
            )),
            JSONMember(key: "recentCalls", value: .array(
                deps.usage.recent(
                    limit: Double(DiagnosticsBundle.usageRecordLimit), server: nil, cwd: nil
                ).map(Self.callValue)
            )),
            JSONMember(key: "routerLog", value: logValue(deps))
        ])
        let (scrubbed, tally) = redactor.redact(gathered)
        let elided = elision.elide(scrubbed)
        guard case var .object(members) = elided else { return elided }
        // The redaction block goes through BOTH passes too, and it has to be said why, because
        // appending it after the scrub is the obvious way to write this and it is wrong.
        //
        // Every label in that block is a key path — `<server>.env.<KEY>` — and a config is free to
        // put a credential in a key name or a server name. Gemini raised exactly that as a leak
        // vector: layer 2 keeps object keys and redacts values, so a secret in a key survives
        // unless the scrub reads keys as well. It does, everywhere in `gathered` — and this block
        // is not in `gathered`, so appending it unscrubbed would open at the last line the hole
        // the whole pass exists to close.
        //
        // `tally` stays the body's count. A second tally would report the redaction block's own
        // removals inside the redaction block, and a number describing the sentence it sits in is
        // worse than one that says plainly what it covers.
        let block = elision.elide(redactor.redact(appliedRedactionValue(redactor, tally)).0)
        members.append(JSONMember(key: "redaction", value: block))
        return .object(members)
    }

    /// The redaction plan plus what it actually did.
    ///
    /// The tally is the difference between a scrubber that ran and a scrubber that had something to
    /// do. Both read as a clean bundle and only one of them is evidence, so the count is on the
    /// wire where a case can assert on it.
    private func appliedRedactionValue(
        _ redactor: SecretRedactor, _ tally: SecretRedactor.Tally
    ) -> JSONValue {
        guard case var .object(members) = redactionPlanValue(redactor) else { return .null }
        members.append(JSONMember(
            key: "occurrencesRemoved", value: .number(Double(tally.occurrences))
        ))
        members.append(JSONMember(key: "secretsFoundInText", value: .array(
            tally.labels.sorted().map { .string(JSString($0)) }
        )))
        return .object(members)
    }

    private func routerValue(_ deps: ControlDeps) -> JSONValue {
        .object([
            JSONMember(key: "port", value: .number(Double(deps.config.port))),
            JSONMember(key: "host", value: .string(JSString(deps.config.host))),
            JSONMember(key: "idleMs", value: .number(Double(deps.config.idleMs))),
            JSONMember(
                key: "startupTimeoutMs", value: .number(Double(deps.config.startupTimeoutMs))
            ),
            JSONMember(key: "configPath", value: .string(JSString(deps.configPath))),
            JSONMember(key: "logPath", value: .string(JSString(deps.config.logPath))),
            JSONMember(key: "since", value: .string(JSString(deps.usage.summarySince())))
        ])
    }

    /// One upstream. **No `env` value, no header value, and no raw URL reaches this function's
    /// output** — the pairs are mapped to their keys and a shape before anything else touches them,
    /// which is the same construction ``Describe/row(_:_:)`` uses and for the same reason.
    private func serverValue(_ upstream: UpstreamConfig, _ deps: ControlDeps) -> JSONValue {
        let key = JSString(upstream.name)
        var members: [JSONMember] = [
            JSONMember(key: "name", value: .string(key)),
            JSONMember(key: "transport", value: .string(JSString(upstream.transport.rawValue))),
            JSONMember(key: "disabled", value: .bool(upstream.disabled ?? false))
        ]
        if upstream.isStdio {
            members.append(JSONMember(
                key: "command", value: .string(JSString(upstream.command ?? ""))
            ))
            members.append(JSONMember(key: "args", value: .array(
                upstream.args.map { .string(JSString($0)) }
            )))
            if let cwd = upstream.cwd {
                members.append(JSONMember(key: "cwd", value: .string(JSString(cwd))))
            }
            members.append(JSONMember(
                key: "env", value: .array(upstream.env.map(Self.pairShapeValue))
            ))
        } else {
            members.append(JSONMember(key: "url", value: .string(JSString(
                DiagnosticsBundle.safeURL(upstream.url ?? "")
            ))))
            members.append(JSONMember(key: "headers", value: .array(
                upstream.headers.map(Self.pairShapeValue)
            )))
        }
        if let live = deps.pool.firstStatus(key) {
            members.append(JSONMember(key: "live", value: Self.liveValue(live)))
        }
        members.append(JSONMember(
            key: "cache", value: Self.cacheValue(deps.manifest.entry(named: upstream.name))
        ))
        return .object(members)
    }

    /// A configured key and the *shape* of its value. Never the value, and never its exact length —
    /// see ``DiagnosticsBundle/ValueShape``.
    static func pairShapeValue(_ pair: JSStringPair) -> JSONValue {
        .object([
            JSONMember(key: "key", value: .string(pair.key)),
            JSONMember(key: "value", value: .string(JSString(
                DiagnosticsBundle.shape(of: pair.value.string).rawValue
            )))
        ])
    }

    static func liveValue(_ live: LiveUpstream) -> JSONValue {
        var members: [JSONMember] = []
        if let state = live.state {
            members.append(JSONMember(key: "state", value: .string(JSString(state))))
        }
        if let inFlight = live.inFlight {
            members.append(JSONMember(key: "inFlight", value: .number(Double(inFlight))))
        }
        if let served = live.callsServed {
            members.append(JSONMember(key: "callsServed", value: .number(Double(served))))
        }
        if let idle = live.idleSec {
            members.append(JSONMember(key: "idleSec", value: .number(Double(idle))))
        }
        return .object(members)
    }

    /// The cached tool surface. `null` for a server the manifest has never indexed — distinct from
    /// a server it indexed and found no tools on, which is a real state with a real cause.
    static func cacheValue(_ entry: CachedServer?) -> JSONValue {
        guard let entry else { return .null }
        var members: [JSONMember] = []
        if let tools = entry.value.member("tools")?.asArray {
            members.append(JSONMember(key: "tools", value: .number(Double(tools.count))))
        }
        for name in ["error", "indexedAt", "digest", "builtAt"] {
            if let value = entry.value.member(JSString(name)) {
                members.append(JSONMember(key: JSString(name), value: value))
            }
        }
        return .object(members)
    }

    /// One recorded tool call. `err` is carried in full and is the single most likely place in this
    /// whole document for an upstream to have quoted a credential back at the router — which is the
    /// leak layer 1 cannot reach and layer 2 exists for.
    static func callValue(_ record: UsageRecord) -> JSONValue {
        var members: [JSONMember] = [
            JSONMember(key: "ts", value: .string(JSString(record.ts))),
            JSONMember(key: "server", value: .string(JSString(record.server))),
            JSONMember(key: "tool", value: .string(JSString(record.tool))),
            JSONMember(key: "ok", value: .bool(record.ok)),
            JSONMember(key: "ms", value: .number(record.ms)),
            JSONMember(key: "cold", value: .bool(record.cold))
        ]
        if let project = record.project {
            members.append(JSONMember(key: "project", value: .string(JSString(project))))
        }
        if let client = record.client {
            members.append(JSONMember(key: "client", value: .string(JSString(client))))
        }
        if let err = record.err { members.append(JSONMember(key: "err", value: .string(JSString(err)))) }
        return .object(members)
    }

    /// The log tail, or the reason there is none.
    ///
    /// An unreadable log is reported as `available: false` with the reason rather than as an empty
    /// array. The two are the same document to a careless reader and they mean opposite things.
    private func logValue(_ deps: ControlDeps) -> JSONValue {
        switch DiagnosticsBundle.logTail(path: deps.config.logPath, fileSystem: deps.fileSystem) {
        case let .lines(lines):
            .object([
                JSONMember(key: "available", value: .bool(true)),
                JSONMember(key: "lines", value: .number(Double(lines.count))),
                JSONMember(key: "tail", value: .array(lines.map { JSONValue.string(JSString($0)) }))
            ])
        case let .unavailable(reason):
            .object([
                JSONMember(key: "available", value: .bool(false)),
                JSONMember(key: "reason", value: .string(JSString(reason)))
            ])
        }
    }
}
