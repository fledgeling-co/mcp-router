import Foundation

/// The JSON the cache routes answer with.
///
/// Built out of ``JSONValue`` members in a fixed order rather than through an encoder — the
/// constraint `scripts/lint/no-wire-codable.sh` enforces over this half of the router.
///
/// **Every member is present, and an unobserved figure is `null` rather than `0`.** `bytes` is the
/// member where that matters most here: a caller is about to decide whether to spend it, and a
/// directory whose walk failed reporting `0` would read as free.
extension ControlHandler {
    static func rowValue(_ row: CacheRow) -> JSONValue {
        .object([
            JSONMember(key: JSString("cache"), value: .string(JSString(row.cache.rawValue))),
            JSONMember(key: JSString("subject"), value: .string(JSString(row.subject))),
            JSONMember(
                key: JSString("path"), value: row.path.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("bytes"), value: row.bytes.map { JSONValue.number(Double($0)) } ?? .null
            ),
            // The member this whole family turns on: what brings the row back. A `null` here is a
            // row the router refuses to remove, and the sentence beside it says why.
            JSONMember(
                key: JSString("refetch"), value: row.refetch.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("problem"),
                value: row.problem.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    static func cacheGroupValue(_ name: CacheName, _ rows: [CacheRow]) -> JSONValue {
        let measured = rows.compactMap(\.bytes)
        return .object([
            JSONMember(key: JSString("cache"), value: .string(JSString(name.rawValue))),
            JSONMember(key: JSString("entries"), value: .number(Double(rows.count))),
            JSONMember(key: JSString("bytes"), value: .number(Double(measured.reduce(0, +)))),
            // The denominator for the figure above, so a byte count over a partly-unreadable cache
            // is read as the floor it is.
            JSONMember(key: JSString("unmeasured"), value: .number(Double(rows.count - measured.count))),
            JSONMember(
                key: JSString("irreplaceable"),
                value: .number(Double(rows.count { $0.refetch == nil }))
            ),
            JSONMember(key: JSString("rows"), value: .array(rows.map(rowValue)))
        ])
    }

    static func inventoryValue(_ inventory: CacheInventory) -> JSONValue {
        .object(CacheName.allCases.map { name in
            JSONMember(key: JSString(name.rawValue), value: cacheGroupValue(name, inventory.rows(name)))
        })
    }

    static func stepValue(_ step: CacheStep) -> JSONValue {
        let effect: (String, String) = switch step.effect {
        case let .removeDirectory(path): ("remove-directory", path)
        case let .reindexServer(name): ("reindex-server", name)
        }
        return .object([
            JSONMember(key: JSString("cache"), value: .string(JSString(step.cache.rawValue))),
            JSONMember(key: JSString("subject"), value: .string(JSString(step.subject))),
            JSONMember(key: JSString("effect"), value: .string(JSString(effect.0))),
            JSONMember(key: JSString("on"), value: .string(JSString(effect.1))),
            JSONMember(
                key: JSString("bytes"), value: step.bytes.map { JSONValue.number(Double($0)) } ?? .null
            ),
            JSONMember(key: JSString("refetch"), value: .string(JSString(step.refetch)))
        ])
    }

    static func cacheRefusalValue(_ refusal: CacheRefusal) -> JSONValue {
        .object([
            JSONMember(key: JSString("error"), value: .string(JSString(refusal.message))),
            JSONMember(key: JSString("reason"), value: .string(JSString(refusal.reason))),
            JSONMember(
                key: JSString("fallback"),
                value: refusal.fallback.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(
                key: JSString("fallbackBytes"),
                value: refusal.fallbackBytes.map { JSONValue.number(Double($0)) } ?? .null
            )
        ])
    }

    static func planValue(_ plan: CachePlan, applied: CacheInvalidation.Applied?) -> JSONValue {
        .object([
            JSONMember(key: JSString("target"), value: .string(JSString(plan.target.description))),
            // `false` on a plan-only reply, so a caller can never mistake a plan for a change.
            JSONMember(key: JSString("applied"), value: .bool(applied != nil)),
            JSONMember(key: JSString("steps"), value: .array(plan.steps.map(stepValue))),
            JSONMember(key: JSString("bytes"), value: .number(Double(plan.bytes))),
            JSONMember(key: JSString("unmeasured"), value: .number(Double(plan.unmeasured))),
            // Rows that match the target and are not being touched, each with the reason. Present
            // and empty rather than omitted: a caller has to be able to tell "nothing was held"
            // from "held rows were not reported".
            JSONMember(key: JSString("held"), value: .array(plan.held.map(rowValue))),
            JSONMember(
                key: JSString("refusal"),
                value: plan.refusal.map(cacheRefusalValue) ?? .null
            ),
            JSONMember(
                key: JSString("removed"),
                value: .array((applied?.removed ?? []).map { .string(JSString($0)) })
            ),
            // Named rather than performed here: re-deriving a manifest row needs a live pool, which
            // this handler does not reach into. `mcp-router index` and `POST /servers/:name/reindex`
            // are the two things that do.
            JSONMember(
                key: JSString("reindex"),
                value: .array((applied?.reindexed ?? []).map { .string(JSString($0)) })
            ),
            JSONMember(
                key: JSString("failures"),
                value: .array((applied?.failures ?? []).map { .string(JSString($0)) })
            )
        ])
    }
}
