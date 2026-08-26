#!/usr/bin/env python3
"""Red-green proving pass for the F3 control layer.

A test that has never failed is not known to work (SWIFT_PRACTICES.md §7). This applies one
mutation at a time to the *implementation*, runs the suite, and records which tests went red.
The tests themselves are never touched — a mutation that edits a test proves nothing.

Each entry names the test it is supposed to kill. A mutation that leaves the suite green is a
decoration exposed, and is reported as SURVIVED.

Usage:  python3 scripts/red-green.py [--only ID] [--json OUT]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"
SRC = APP / "Sources" / "MCPRouterKit" / "Control"


class Mutation:
    def __init__(self, mid, clause, guard, path, find, replace, expect, extra_file=None):
        self.id = mid
        self.clause = clause
        self.guard = guard
        self.path = path
        self.find = find
        self.replace = replace
        # Substrings of the test names that must go red.
        self.expect = expect if isinstance(expect, list) else [expect]
        # (relative path, contents) for a mutation that adds a file rather than editing one.
        self.extra_file = extra_file


M = []


def mut(*args, **kwargs):
    M.append(Mutation(*args, **kwargs))


# ---------------------------------------------------------------- error mapping (A2, A3, A4)

mut(
    "M01", "A2", "a refused loopback connection is its own case, not a generic transport error",
    SRC / "LiveControlAPIClient.swift",
    "            if error.code == .cannotConnectToHost || error.code == .cannotFindHost {\n"
    "                throw ControlAPIError.routerNotRunning\n"
    "            }\n",
    "",
    "a refused connection is routerNotRunning",
)

mut(
    "M02", "A3", "a 401 is unauthorized and nothing else",
    SRC / "LiveControlAPIClient.swift",
    "        if http.statusCode == 401 {",
    "        if http.statusCode == 999_401 {",
    ["a 401 is unauthorized", "a rotated token is re-read"],
)

mut(
    "M03", "A4", "an unreadable shape fails loudly rather than as any other error",
    SRC / "LiveControlAPIClient.swift",
    "            throw ControlAPIError.malformedResponse(detail: \"\\(Response.self): \\(error)\")",
    "            throw ControlAPIError.transport(detail: \"\\(Response.self): \\(error)\")",
    "a shape this version doesn't understand fails loudly",
)

# ---------------------------------------------------------------- headers (A8)

mut(
    "M04", "A8", "a mutating request announces a JSON body — the router's CSRF defence",
    SRC / "LiveControlAPIClient.swift",
    "            request.setValue(\"application/json\", forHTTPHeaderField: \"content-type\")",
    "            _ = \"application/json\"",
    "a mutating request carries the bearer token and the JSON content type",
)

mut(
    "M05", "A8", "every request carries the bearer token",
    SRC / "LiveControlAPIClient.swift",
    "            request.setValue(\"Bearer \\(token)\", forHTTPHeaderField: \"Authorization\")",
    "            _ = token",
    "a mutating request carries the bearer token and the JSON content type",
)

mut(
    "M06", "A8", "a read does not announce a body it is not sending",
    SRC / "LiveControlAPIClient.swift",
    "        if method.isMutating, body != nil || method != .delete {",
    "        if true {",
    "a read does not need to announce a JSON body",
)

# ---------------------------------------------------------------- rotation (A6)

mut(
    "M07", "A6", "an unchanged token is not retried — the loop guard",
    SRC / "LiveControlAPIClient.swift",
    "        guard let fresh = tokenFile.read(), fresh != sent else { return nil }",
    "        guard let fresh = tokenFile.read() else { return nil }",
    "an unchanged token is not retried",
)

mut(
    "M08", "A6", "the retry happens exactly once, tracked per call",
    SRC / "LiveControlAPIClient.swift",
    "            return try await perform(\n"
    "                method, path,\n"
    "                query: query, body: body,\n"
    "                typedFailureStatuses: typedFailureStatuses,\n"
    "                allowRetry: false\n"
    "            )",
    "            _ = try? await perform(\n"
    "                method, path, query: query, body: body,\n"
    "                typedFailureStatuses: typedFailureStatuses, allowRetry: false\n"
    "            )\n"
    "            return try await perform(\n"
    "                method, path, query: query, body: body,\n"
    "                typedFailureStatuses: typedFailureStatuses, allowRetry: false\n"
    "            )",
    "a rotated token is re-read and the request retried exactly once",
)

# ---------------------------------------------------------------- the hint (A16)

mut(
    "M09", "A16", "the router's advice on a refused add survives into the error",
    SRC / "LiveControlAPIClient.swift",
    "                hint: failure?.hint",
    "                hint: nil",
    "a router error carries its status, its message, and the hint",
)

# ---------------------------------------------------------------- path encoding

mut(
    "M10", "A9", "a server name needing encoding still reaches its route",
    SRC / "LiveControlAPIClient.swift",
    "        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: \"-._~\")))\n"
    "            ?? raw",
    "        raw",
    "a server name needing encoding still reaches the right route",
)

# ---------------------------------------------------------------- stream (A10, A11, A12)

mut(
    "M11", "A12", "heartbeat and greeting comments are skipped rather than decoded",
    SRC / "ControlEventStream.swift",
    "            if line.hasPrefix(\":\") { continue }",
    "            if line.hasPrefix(\":\") { continuation.yield(.phase(.live)); continue }",
    "heartbeat and greeting comments are ignored",
)

mut(
    "M12", "A11", "the backoff doubles",
    SRC / "ControlEventStream.swift",
    "        let scaled = initialDelay * Int(truncating: NSDecimalNumber(decimal: pow(2, doublings)))",
    "        let scaled = initialDelay * 1",
    "the delay doubles from the first retry",
)

mut(
    "M13", "A11", "the backoff holds at a 30s ceiling",
    SRC / "ControlEventStream.swift",
    "        ceiling: Duration = .seconds(30),",
    "        ceiling: Duration = .seconds(30000),",
    "the stated policy is the one you get without asking",
)

mut(
    "M14", "A11", "retrying stops after the stated number of consecutive failures",
    SRC / "ControlEventStream.swift",
    "        maximumAttempts: Int = 6",
    "        maximumAttempts: Int = 600",
    "the stated policy is the one you get without asking",
)

mut(
    "M15", "A11", "a connection that delivered anything resets the consecutive count",
    SRC / "ControlEventStream.swift",
    "                        attempt = worked ? 0 : attempt + 1",
    "                        attempt += 1",
    "a connection that stayed up resets",
)

mut(
    "M16", "A10", "records are yielded as they arrive, not batched at the end",
    SRC / "ControlEventStream.swift",
    "            continuation.yield(.record(record))\n"
    "        }\n"
    "        return delivered",
    "            batched.append(record)\n"
    "        }\n"
    "        for record in batched { continuation.yield(.record(record)) }\n"
    "        return delivered",
    "events arrive as they happen",
)

# M16 needs the accumulator declared; paired edit applied with it.
M[-1].paired = (
    "        var delivered = false\n",
    "        var delivered = false\n        var batched: [CallRecord] = []\n",
)

# ---------------------------------------------------------------- state merge (A13)

mut(
    "M17", "A13", "an arriving call corrects an idle server to running",
    SRC / "ServerStateTracker.swift",
    "        guard server.state != .running else { return }",
    "        guard server.state != .idle else { return }",
    "a call record marks an idle server running",
)

mut(
    "M18", "A13", "a call for a server the router never listed invents nothing",
    SRC / "ServerStateTracker.swift",
    "        guard var server = servers[record.server] else { return }",
    "        guard var server = servers[record.server] ?? servers.values.first else { return }",
    "a call record for a server the router never listed invents nothing",
)
M[-1].paired = (
    "        servers[record.server] = server\n",
    "        servers[server.name] = server\n",
)

mut(
    "M19", "A13", "a poll is authoritative — a dropped server leaves no stale row",
    SRC / "ServerStateTracker.swift",
    "        servers = next\n        order = nextOrder",
    "        servers = servers.merging(next) { _, new in new }\n"
    "        order = order + nextOrder.filter { !order.contains($0) }",
    "a poll removing a server removes it",
)

mut(
    "M20", "A13", "the router's own ordering is preserved",
    SRC / "ServerStateTracker.swift",
    "        let visible = order.compactMap { servers[$0] }",
    "        let visible = order.sorted().compactMap { servers[$0] }",
    "the router's own ordering is preserved",
)

# ---------------------------------------------------------------- failure states (F4)

# The defect F4 exists to fix. Reintroducing `try?` discards every typed error, and the
# ONLY tests that notice are the ones driving the real poll loop — the direct
# apply(pollFailure:) tests pass against the defect, which is why they are not the anchor
# here.
mut(
    "M50", "F4-A1", "the poll loop reports a typed error instead of discarding it",
    SRC / "ServerStateTracker.swift",
    "            do {\n"
    "                let response = try await client.servers()\n"
    "                apply(poll: response)\n"
    "            } catch {",
    "            if let response = try? await client.servers() { apply(poll: response) }\n"
    "            if false {",
    "a router that is not running is reported",
)
M[-1].paired = (
    "                apply(pollFailure: error)\n",
    "                apply(pollFailure: .routerNotRunning)\n",
)

mut(
    "M51", "F4-A3", "a stale snapshot is not collapsed into a plain failure",
    SRC / "ServerStateTracker.swift",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)",
    "        loadKind = .failed(error)",
    "a failure after a success is stale",
)

mut(
    "M52", "F4-A3", "a failed poll does not delete the servers it already had",
    SRC / "ServerStateTracker.swift",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)\n        publish()",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)\n"
    "        servers = [:]\n        order = []\n        publish()",
    "a failure after a success is stale",
)

mut(
    "M53", "F4-A6", "a tracker with no stream is not born claiming a dropped one",
    SRC / "ServerStateTracker.swift",
    "        streamCondition = stream == nil ? .notConfigured : .phase(.disconnected)",
    "        streamCondition = .phase(.disconnected)",
    "is not-configured, never a dropped stream",
)

mut(
    "M54", "F4-A8", "a phase cannot be fabricated for a tracker that has no stream",
    SRC / "ServerStateTracker.swift",
    "        guard case let .phase(current) = streamCondition else { return }",
    "        let current = if case let .phase(p) = streamCondition { p } "
    "else { StreamPhase.disconnected }",
    "a phase cannot be fabricated",
)

# Registration must complete before `updates()` returns.
#
# The obvious mutation — `Task { self.register(id, continuation) }` — is an EQUIVALENT MUTANT and
# was measured as one: it survived 4 of 5 full-suite runs, and the fifth red was an unrelated
# flake this pass then fixed. The reason is scheduling, not coverage. `Task {}` inside an
# actor-isolated method inherits that actor's executor and is enqueued during `updates()`, so it
# is ahead of every call an external caller can make afterwards; the actor runs it first and no
# outside observer can see the difference. No test can kill it, and pretending otherwise would
# have meant writing a priority-race test that is flaky by construction.
#
# `Task.detached` was adopted next on the reasoning that not inheriting the executor would make
# the registration genuinely land after a following publish. **That reasoning is wrong, and was
# measured wrong.** Not inheriting the executor changes where the task *starts*, not where the
# actor-isolated call it makes is *queued*: the detached task is created while `updates()` still
# holds the actor, so its `await self.register(...)` is enqueued on the actor ahead of anything an
# external caller can enqueue afterwards. `firstStateIsTheStateAtSubscription` asserts the
# invariant that would expose the loss — the first element a subscriber receives must be the state
# current when `updates()` returned — over 40 consecutive trials, and the deferred registration
# won all 40. M55 therefore stays SURVIVED, honestly, rather than being relabelled as killed.
#
# It is NOT marked equivalent, because it is not: ordering here is an implementation detail of the
# actor executor, and `Task.detached` runs at unspecified priority, so a priority difference or a
# loaded machine can still make it lose. The synchronous `register` is kept because it is a
# language-level guarantee rather than an observed schedule, and the 40-trial test is the guard
# that catches the deferral on any run where it does lose. What no test can do is force the loss
# on demand — a test that tried would be flaky by construction, which is worse than a recorded
# survivor.
mut(
    "M55", "F4-A11", "subscribing registers before updates() returns, losing nothing",
    SRC / "ServerStateTracker.swift",
    "        register(id, continuation)",
    "        Task.detached { await self.register(id, continuation) }",
    "published immediately after subscribing is delivered",
)

mut(
    "M56", "F4-A11", "an unchanged state is not republished",
    SRC / "ServerStateTracker.swift",
    "        guard snapshot != lastPublished else { return }",
    "        if false { return }",
    "an identical state is not published twice",
)

mut(
    "M57", "F4-A4", "run() twice does not start a second poll loop",
    SRC / "ServerStateTracker.swift",
    "        guard !isRunning else { return }",
    "        if false { return }",
    "running twice does not start a second poll loop",
)

# A failure that is stored but never published leaves a subscribed surface frozen on the last good
# frame — the same invisible failure as the original `try?`, one layer further out. Nothing
# mutated this line before, so the `publish()` in `apply(pollFailure:)` was a decoration.
mut(
    "M58", "F4-A11", "a poll failure is published, not merely recorded",
    SRC / "ServerStateTracker.swift",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)\n        publish()",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)",
    ["notified of a poll failure", "the failure and its recovery"],
)

# A cancelled `run()` is a deliberate teardown, not a stream that gave up. Without this guard the
# ordinary shutdown path publishes `.disconnected` to every subscriber — a drop that did not
# happen, which is the same lie as the pinned `.disconnected` F4 exists to remove, arriving from
# the other end of the lifecycle. Found by the Phase D completeness critic.
mut(
    "M59", "F4-A7", "a cancelled run() does not report the stream as dropped",
    SRC / "ServerStateTracker.swift",
    "        guard !Task.isCancelled else { return }\n        apply(phase: .disconnected)",
    "        apply(phase: .disconnected)",
    "cancelling run() does not report a parked stream as dropped",
)

# ---------------------------------------------------------------- secrets (A5, A7)

mut(
    "M21", "A7", "a token is logged by its shape, never its value",
    SRC / "ControlTokenStore.swift",
    "        return \"<\\(secret.count) chars>\"",
    "        return secret",
    "the log records that a token exists and its length",
)

mut(
    "M22", "A7", "an absent token is described as absent, not as an empty one",
    SRC / "ControlTokenStore.swift",
    "        guard let secret, !secret.isEmpty else { return \"<none>\" }",
    "        guard let secret else { return \"<none>\" }",
    "redaction describes an absent token as absent",
)

mut(
    "M23", "A5", "the token goes to the Keychain and never to UserDefaults",
    SRC / "ControlTokenStore.swift",
    "        let status = SecItemAdd(query as CFDictionary, nil)",
    "        UserDefaults.standard.set(token, forKey: \"control-token\")\n"
    "        let status = SecItemAdd(query as CFDictionary, nil)",
    "no token-shaped value is ever written to UserDefaults",
)

mut(
    "M24", "A5", "the token file is read as the router writes it",
    SRC / "ControlTokenStore.swift",
    "        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)",
    "        let trimmed = text",
    "the token file is read as the router writes it",
)

mut(
    "M25", "A5", "MCP_ROUTER_HOME moves the token file",
    SRC / "ControlTokenStore.swift",
    "        let base = home.map { URL(fileURLWithPath: $0) } ?? Self.defaultHome",
    "        let base = Self.defaultHome",
    "MCP_ROUTER_HOME moves the token file",
)

# ---------------------------------------------------------------- closed sets (A23)

mut(
    "M26", "A23", "an unrecognised registry source fails decoding rather than defaulting",
    SRC / "RegistryModels.swift",
    "    public enum Source: String, Codable, Hashable, Sendable, CaseIterable {\n"
    "        case official\n"
    "        case smithery\n"
    "        case both\n"
    "    }",
    "    public enum Source: String, Codable, Hashable, Sendable, CaseIterable {\n"
    "        case official\n"
    "        case smithery\n"
    "        case both\n"
    "        public init(from decoder: any Decoder) throws {\n"
    "            let raw = try decoder.singleValueContainer().decode(String.self)\n"
    "            self = Source(rawValue: raw) ?? .official\n"
    "        }\n"
    "    }",
    "an unrecognised registry source fails decoding",
)

# ---------------------------------------------------------------- the standing guarantee (A20)

mut(
    "M27", "A20", "a patch can never carry command, args or env",
    SRC / "ServerPatch.swift",
    "    public var placard: PlacardEdit?\n",
    "    public var placard: PlacardEdit?\n    public var command: String?\n",
    ["no stored property is named after a forbidden wire key",
     "adding a server is the only shape that carries a command"],
)

mut(
    "M27b", "A20", "a non-nil forbidden field reaches the encoded JSON and is caught there",
    SRC / "ServerPatch.swift",
    "        try container.encodeIfPresent(idleMs, forKey: .idleMs)\n",
    "        try container.encodeIfPresent(idleMs, forKey: .idleMs)\n"
    "        try container.encode(\"/bin/sh\", forKey: .command)\n",
    ["an encoded ServerPatch can never carry command",
     "encodedBody emits only permitted keys",
     "a fully-populated patch encodes exactly the keys the router reads"],
)
M[-1].paired = (
    "        case projects, warm, idleMs, placard\n",
    "        case projects, warm, idleMs, placard, command\n",
)

mut(
    "M28", "A20", "encodedBody's allowlist rejects a key that is merely unexpected",
    SRC / "ServerPatch.swift",
    "        try container.encodeIfPresent(idleMs, forKey: .idleMs)\n",
    "        try container.encodeIfPresent(idleMs, forKey: .idleMs)\n"
    "        try container.encode(\"x\", forKey: .extra)\n",
    ["encodedBody emits only permitted keys",
     "a fully-populated patch encodes exactly the keys the router reads"],
)
M[-1].paired = (
    "        case projects, warm, idleMs, placard\n",
    "        case projects, warm, idleMs, placard, extra\n",
)

mut(
    "M30", "A15", "a recording nothing decodes is a failure, not an unused file",
    SRC / "Fixtures" / "servers.json", "", "",
    "no recording exists that nothing decodes",
    extra_file=(SRC / "Fixtures" / "orphan-shape.json", '{"nothing":"decodes this"}'),
)

# ---------------------------------------------------------------- the double (A18, A19)

mut(
    "M29", "A19", "the offline scenario refuses in the one way that has its own surface",
    SRC / "FixtureControlAPIClient.swift",
    "        case .offline: .routerNotRunning",
    "        case .offline: .unauthorized",
    "the offline scenario refuses in the one way",
)

# ---------------------------------------------------------------- copy and shape fidelity

mut(
    "M31", "A25", "the approved wording is the wording the client returns",
    SRC / "ControlAPIClient.swift",
    '        case .routerNotRunning: "The router isn\'t running"',
    '        case .routerNotRunning: "The router is not currently running"',
    ["the two whole-screen conditions read exactly as approved",
     "the approved wording in the mock is the wording the client actually returns"],
)

mut(
    "M32", "A22", "an in-flight authorization on the servers response is modelled, not dropped",
    SRC / "Models.swift",
    "    public var pendingAuth: PendingAuth?\n    public var servers: [MCPServer]\n}",
    "    public var pendingAuth: PendingAuth?\n    public var servers: [MCPServer]\n\n"
    "    private enum CodingKeys: String, CodingKey {\n"
    "        case port, idleMs, since, servers\n"
    "        case pendingAuth = \"pendingAuthorization\"\n"
    "    }\n}",
    ["every fixture round-trips without losing or inventing a field",
     "an authorization already in flight is recorded"],
)

mut(
    "M33", "A21", "approve returns a count, not a server — F1's protocol assumed wrong",
    SRC / "Models.swift",
    "public struct ApprovalResult: Codable, Hashable, Sendable {\n"
    "    public var server: String\n"
    "    public var approved: Int\n"
    "}",
    "public struct ApprovalResult: Codable, Hashable, Sendable {\n"
    "    public var server: String\n"
    "    public var approved: Int { 0 }\n"
    "}",
    ["every fixture round-trips without losing or inventing a field",
     "the approval response is a count, not a server"],
)

# ---------------------------------------------------------------- typed failure bodies (A15)

mut(
    "M34", "A15", "a failed re-index returns its structured outcome, not a collapsed error",
    SRC / "LiveControlAPIClient.swift",
    "            typedFailureStatuses: [422],\n",
    "",
    "a failed re-index returns its structured outcome",
)

mut(
    "M35", "A16", "the typed-failure allowlist is per call site, so add's 422 stays a refusal",
    SRC / "LiveControlAPIClient.swift",
    "        if !typedFailureStatuses.contains(http.statusCode) {",
    "        if false {",
    "a router error carries its status, its message, and the hint",
)

# ---------------------------------------------------------------- concurrency and DELETE

mut(
    "M36", "A6", "rotation compares against the token that was SENT, not the cached copy",
    SRC / "LiveControlAPIClient.swift",
    "        guard let fresh = tokenFile.read(), fresh != sent else { return nil }",
    "        guard let fresh = tokenFile.read(), fresh != cachedToken else { return nil }",
    "two calls racing a rotation each retry once",
)

mut(
    "M37", "A8", "a bodyless DELETE announces no body — the router exempts it by name",
    SRC / "LiveControlAPIClient.swift",
    "        if method.isMutating, body != nil || method != .delete {",
    "        if method.isMutating {",
    "a bodyless DELETE carries the token and announces no body",
)

# ---------------------------------------------------------------- the second critic round

mut(
    "M38", "A9", "the usage filters the endpoint offers are reachable through the client",
    SRC / "LiveControlAPIClient.swift",
    '        if let server { query.append(.init(name: "server", value: server)) }\n',
    "",
    "the usage filters reach the wire",
)

mut(
    "M39", "A11", "a router that greets and drops is bounded rather than retried forever",
    SRC / "ControlEventStream.swift",
    "        return delivered && ContinuousClock.now - opened >= policy.minimumHealthyDuration",
    "        return delivered",
    "a router that greets and immediately drops is bounded",
)

mut(
    "M40", "A11", "the stated health threshold is the one you get by default",
    SRC / "ControlEventStream.swift",
    "        minimumHealthyDuration: Duration = .seconds(5)",
    "        minimumHealthyDuration: Duration = .seconds(500)",
    "the stated policy is the one you get without asking",
)

mut(
    "M41", "A4", "an unreadable record is skipped, but leaves a trace",
    SRC / "ControlEventStream.swift",
    '                log.warning("skipped a call record this version could not decode (\\(payload.count) bytes)")\n',
    "",
    "an unreadable record is skipped, but not silently",
)

mut(
    "M42", "A20", "a cleared placard reaches the wire as an explicit null",
    SRC / "ServerPatch.swift",
    "        case .clear: try container.encodeNil(forKey: .placard)",
    "        case .clear: break",
    "a placard can be set, cleared, or left alone",
)

# ---------------------------------------------------------------- M29: declared and not served
#
# Ids are DIS-*, not M29-*, deliberately: this table's ids are a mutation index in their own
# namespace, and it already carries an "M20" that means a mutation rather than a ledger item. Two
# things spelled the same in one file is how the earlier confusion started.
#
# Every arm targets the SWIFT implementation, because the suite this harness runs is the Swift one.
# The TypeScript reference is held to the same behaviour by the vector corpus, which is generated
# from it — so an arm that mutated the reference would change the expectation and the port together
# and prove nothing.

ROUTER_CORE = APP / "Sources" / "RouterCore"
KIT_SERVERS = APP / "Sources" / "MCPRouterKit" / "Servers"

mut(
    "DIS-1", "M29", "unionTools asks whether the server is served, not only whether it is in scope",
    ROUTER_CORE / "Manifest" / "ToolUnion.swift",
    "        upstream.disabled != true && visibleTo(upstream, cwd: cwd)",
    "        visibleTo(upstream, cwd: cwd)",
    "the served union matches the reference",
)

mut(
    "DIS-2", "M29", "a warm upstream that is disabled is still armed for reaping",
    ROUTER_CORE / "Pool" / "UpstreamPoolReaping.swift",
    "        if config.warm == true, config.disabled != true { return }",
    "        if config.warm == true { return }",
    "a warm upstream that is disabled IS armed for reaping",
)

mut(
    "DIS-3", "M29", "the switch stays outside the hash material, so the digest does not move",
    ROUTER_CORE / "Config" / "UpstreamHash.swift",
    "    public static func hash(_ upstream: UpstreamConfig) -> String {",
    "    public static func hash(_ upstream: UpstreamConfig) -> String {\n"
    "        if upstream.disabled == true { return \"0000000000000000\" }",
    # NOT "fields outside the hash material do not change the hash": that test reads the hashes
    # RECORDED in the vector file and compares them to each other, so it pins the reference's
    # exclusion rule and cannot see a mutation of the Swift port at all. The corpus comparison is
    # the test that actually computes a hash here. Found by this arm reporting WRONG-TEST.
    "the config hash matches the reference over the whole adversarial corpus",
)

mut(
    "DIS-4", "M29", "the disabled subtitle outranks the held change rather than sitting below it",
    KIT_SERVERS / "ServerPresentation.swift",
    "        if server.disabled {\n"
    "            return ServerSubtitle(text: \"disabled by you\", tint: .t3)\n"
    "        }\n"
    "        if server.inFlight > 0 {",
    "        if server.inFlight > 0 {",
    "a disabled server reads 'disabled by you' whichever else is true of it",
)

mut(
    "DIS-5", "M29", "the PATCH allow-list still refuses a command line",
    SRC / "ServerPatch.swift",
    '        "projects", "warm", "idleMs", "placard", "disabled"',
    '        "projects", "warm", "idleMs", "placard", "disabled", "command"',
    "a fully-populated patch encodes exactly the keys the router reads",
)

mut(
    "DIS-6", "M29", "a disabled server summons nobody, at the shared seam rather than in the board",
    SRC / "Models.swift",
    "        guard !disabled else { return false }\n",
    "",
    # One test, not two. The plan expected this single mutation to redden the board filter as well,
    # and it does not: `ServerFilter.needsYou` carries its own `!server.disabled` term because the
    # `placard` limb sits outside `needsAttention`. The two guards are independent, so proving both
    # takes two arms — which is what DIS-7 below is for. Found by this arm reporting PARTIAL.
    "a disabled server contributes zero to needsAttention",
)

mut(
    "DIS-7", "M29", "the board filter carries its own guard, since the placard limb sits outside",
    KIT_SERVERS / "ServerPresentation.swift",
    "        case .needsYou: !server.disabled && (server.needsAttention || server.placard != nil)",
    "        case .needsYou: server.needsAttention || server.placard != nil",
    "each route into Needs you is closed by the switch on its own",
)


# ---------------------------------------------------------------- M29 gap-fix: eight arms for the
# eight assertions the verifier found had no oracle.
#
# DIS-1..7 above proved the *implementation* of the switch. These prove the assertions added after
# the verdict, and the shape of each is taken from what the verdict actually measured: DIS-9, DIS-10,
# DIS-11 and DIS-15 are the exact deletions that left all 1960 tests passing, so an arm that reports
# SURVIVED here means the gap-fix restated a clause without giving it a witness.

KIT_SHELL = APP / "Sources" / "MCPRouterKit" / "Shell"
UI_BOARDS = APP / "Sources" / "MCPRouterUI" / "Boards"

mut(
    "DIS-8", "M29", "the band consults the switch, not only the three fields under it",
    KIT_SHELL / "MenuBarPresentation.swift",
    "            guard !server.disabled else { return [] }\n",
    "",
    # Three suites, because the defect was one term missing from one of two expressions that are
    # supposed to be the same condition, and the call site maps the unfiltered list.
    [
        "a disabled server holding a change draws no band row and lights no dot",
        "the band and the dot never disagree about one server, over the cross product",
        "a disabled server holding a change contributes no band row to the popover",
    ],
)

mut(
    "DIS-9", "M29", "the in-flight mark is SET during a write, not merely absent after one",
    UI_BOARDS / "ServersBoardWrites.swift",
    "            writesInFlight.insert(name)\n"
    "            rowErrors[name] = nil\n"
    "            defer { writesInFlight.remove(name) }\n",
    "            rowErrors[name] = nil\n",
    # The verdict's own probe: this deletion removed the whole mechanism and left 1960 tests green.
    "the in-flight mark is set while the write runs, and it dims the row's action",
)

mut(
    "DIS-10", "M29", "the serving process's stale warning does not name a disabled server",
    ROUTER_CORE / "Service" / "RouterService.swift",
    "        let stale = upstreams.filter { $0.disabled != true && ToolUnion.isStale(manifest, $0) }",
    "        let stale = upstreams.filter { ToolUnion.isStale(manifest, $0) }",
    [
        "the startup warning names a stale server and never a disabled one",
        "a router whose only stale servers are disabled warns about nothing",
    ],
)

mut(
    "DIS-11", "M29", "the watcher's sweep spawns no child for a server that serves nobody",
    ROUTER_CORE / "Watch" / "WatchRun.swift",
    "            if candidate.upstream.disabled != true,\n"
    "               ToolUnion.isStale(manifest, candidate.upstream)\n"
    "            {\n"
    "                toIndex.append(candidate.upstream)\n"
    "            }\n",
    "            if ToolUnion.isStale(manifest, candidate.upstream) {\n"
    "                toIndex.append(candidate.upstream)\n"
    "            }\n",
    "a disabled staged entry is never spawned to be indexed",
)

mut(
    "DIS-12", "M29", "reindex is the user asking, so the switch does not stop it",
    ROUTER_CORE / "Control" / "ControlHandler.swift",
    '        case ("/reindex", "POST"):\n'
    "            let outcome = await deps.indexer.index(upstream)",
    '        case ("/reindex", "POST"):\n'
    "            if upstream.disabled == true { return .json(200, .object([])) }\n"
    "            let outcome = await deps.indexer.index(upstream)",
    # An ADDED guard rather than a removed one: this is the tidy-up the route is exposed to, and
    # the half of oracle 5 that a sweep-only test would have let through.
    "a disabled server can still be reindexed, by the user asking for it",
)

mut(
    "DIS-13", "M29", "the withheld count reaches a screen reader as words",
    UI_BOARDS / "ServersBoardRow.swift",
    '            row.tools == nil ? "\\(subtitleText), tools withheld" : subtitleText',
    "            subtitleText",
    "a disabled row speaks 'disabled by you' and 'tools withheld'",
)

mut(
    "DIS-14", "M29", "the sheet's destructive button is Disable, not the Remove it shipped as",
    UI_BOARDS / "ServerSheets.swift",
    '        static func disableLabel(_ serverName: String) -> String { "Disable \\(serverName)" }',
    '        static func disableLabel(_ serverName: String) -> String { "Remove \\(serverName)" }',
    "the sheet's destructive button names the action and the server",
)

mut(
    "DIS-15", "M29", "a refused write reaches the row in the router's own words",
    UI_BOARDS / "ServersBoardWrites.swift",
    "            } catch {\n"
    "                rowErrors[name] = error\n"
    "            }\n",
    "            } catch {\n"
    '                rowErrors[name] = .malformedResponse(detail: "the write did not complete")\n'
    "            }\n",
    # The assertion this kills used to compare a payload-free case to itself and could not fail.
    "a refused enable renders ControlAPIError's own wording, not a new sentence",
)


RESULTS = []


# A mutation can make the suite *hang* rather than fail — a deferred registration leaves a
# subscriber waiting on a value that will never arrive, and `for await` has no deadline of its
# own. Without a bound here that is indistinguishable from a slow run, and the gate simply never
# returns. Found the hard way: an unbounded run took a session with it.
#
# A timeout is a KILL, not an error. The mutant changed observable behaviour — a test stopped
# terminating — and recording it as anything else would let a hang read as a survivor.
SUITE_TIMEOUT_S = 300


def run_suite() -> tuple[bool, str]:
    try:
        proc = subprocess.run(
            ["swift", "test", "--no-parallel"],
            cwd=APP, capture_output=True, text=True, timeout=SUITE_TIMEOUT_S,
        )
        ok, output = proc.returncode == 0, proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as expired:
        captured = (expired.stdout or b"") + (expired.stderr or b"")
        if isinstance(captured, bytes):
            captured = captured.decode("utf-8", "replace")
        ok = False
        output = captured + (
            f'\nTest "«suite did not terminate»" failed: '
            f"no result within {SUITE_TIMEOUT_S}s — the mutation deadlocked a test\n"
        )
    scrub_residue()
    return ok, output


def scrub_residue() -> None:
    """Undo anything a mutation wrote to a store that outlives the process.

    The UserDefaults mutation is the one that leaves a mark: it writes the token under the test
    host's own domain, where it survives the restore and then fails the *next* run for a reason
    that has nothing to do with that run's mutation. Found the hard way.
    """
    subprocess.run(
        ["defaults", "delete", "swiftpm-testing-helper", "control-token"],
        capture_output=True, text=True,
    )


FAIL_RE = re.compile(r'Test "([^"]+)" (?:recorded an issue|failed)')
COMPILE_RE = re.compile(r'\.swift:\d+:\d+: error:')


def failed_tests(output: str) -> set[str]:
    return set(FAIL_RE.findall(output))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--json")
    args = ap.parse_args()

    todo = [m for m in M if not args.only or m.id == args.only]

    print(f"red-green: {len(todo)} mutations\n")
    for m in todo:
        # A mutation that ADDS a file rather than editing one: the anchor is unused.
        if m.extra_file:
            extra_path, extra_body = m.extra_file
            extra_path.write_text(extra_body)
            started = time.time()
            try:
                green, output = run_suite()
            finally:
                extra_path.unlink(missing_ok=True)
            reds = failed_tests(output)
            hits = [e for e in m.expect if any(e in r for r in reds)]
            outcome = "SURVIVED" if green else ("KILLED" if len(hits) == len(m.expect) else "WRONG-TEST")
            took = time.time() - started
            print(f"{m.id}  {outcome:12s} {m.clause:4s} {m.guard[:58]:58s} {took:5.1f}s")
            if outcome != "KILLED":
                for r in sorted(reds)[:6]:
                    print(f"        red: {r}")
            RESULTS.append({
                "id": m.id, "clause": m.clause, "guard": m.guard,
                "file": extra_path.name, "outcome": outcome,
                "expected": m.expect, "reds": sorted(reds)[:12],
                "seconds": round(took, 1),
            })
            continue

        original = m.path.read_text()
        text = original
        paired = getattr(m, "paired", None)
        if paired:
            if paired[0] not in text:
                print(f"{m.id}  ERROR  paired anchor not found")
                RESULTS.append({"id": m.id, "outcome": "ANCHOR-MISSING"})
                continue
            text = text.replace(paired[0], paired[1], 1)
        if m.find not in text:
            print(f"{m.id}  ERROR  anchor not found in {m.path.name}")
            RESULTS.append({"id": m.id, "outcome": "ANCHOR-MISSING"})
            continue
        text = text.replace(m.find, m.replace, 1)

        started = time.time()
        m.path.write_text(text)
        try:
            green, output = run_suite()
        finally:
            m.path.write_text(original)

        reds = failed_tests(output)
        compiled = not COMPILE_RE.search(output)
        hits = [e for e in m.expect if any(e in r for r in reds)]
        took = time.time() - started

        if green:
            outcome = "SURVIVED"
        elif not compiled:
            outcome = "COMPILE-FAIL"
        elif len(hits) == len(m.expect):
            outcome = "KILLED"
        elif hits:
            outcome = "PARTIAL"
        else:
            outcome = "WRONG-TEST"

        print(f"{m.id}  {outcome:12s} {m.clause:4s} {m.guard[:58]:58s} {took:5.1f}s")
        if outcome not in ("KILLED",):
            for r in sorted(reds)[:6]:
                print(f"        red: {r}")
        RESULTS.append({
            "id": m.id, "clause": m.clause, "guard": m.guard,
            "file": m.path.name, "outcome": outcome,
            "expected": m.expect, "reds": sorted(reds)[:12],
            "seconds": round(took, 1),
        })

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(RESULTS, indent=2))

    bad = [r for r in RESULTS if r["outcome"] != "KILLED"]
    print(f"\nkilled {len(RESULTS) - len(bad)}/{len(RESULTS)}")
    for r in bad:
        print(f"  {r['id']}: {r['outcome']}")
    return 1 if bad else 0


# ---------------------------------------------------------------- M20's drift guards (A3 A4 B2 C1 D1)
#
# `plan-M20.md` §6 promised that each of these five is broken deliberately and seen red before it is
# trusted, and the promise was not kept: no evidence ledger existed, and none of the 53 mutations
# above names a menu command, a band control or a notification family. Worse, this file's own `"M20"`
# reads like the item id and is not — it is the twentieth mutation in the M01…M59 namespace, on
# `ServerStateTracker.swift`, present unchanged at M20's branch point. A grep for the item id would
# have reported these guards armed.
#
# So they are armed here, with ids outside that namespace so the collision cannot recur. The paths
# reach outside `SRC` (which is Control/) because M20's decisions live in Shell/ and Inbox/ —
# `Mutation.path` is absolute, so the constant was a convenience rather than a boundary.

SHELL = APP / "Sources" / "MCPRouterKit" / "Shell"
INBOX = APP / "Sources" / "MCPRouterKit" / "Inbox"
UI_SHELL = APP / "Sources" / "MCPRouterUI" / "Shell"

mut(
    "M20-A3", "A3", "every unbuilt command says what is unbuilt, in words of its own",
    SHELL / "MenuCommandAvailability.swift",
    'case .runAllChecks: "Running every check at once"',
    'case .runAllChecks: "Updating every skill at once"',
    "every unbuilt command says what is unbuilt, in words of its own",
)

mut(
    "M20-A4", "A4", "a command that can never fire claims no shortcut",
    SHELL / "MenuCommand.swift",
    "        case .wakeServer: KeyChord(\"W\", [.control])",
    "        case .wakeServer: KeyChord(\"W\", [.control])\n"
    "        case .stopRouter: KeyChord(\"K\", [.control, .option])",
    "a command that can never fire claims no shortcut",
)

# B2's three conditions collapse to two, which is the shape a later edit would actually take: the
# requirement check is the one with no precedent in this file, so it is the one worth arming.
mut(
    "M20-B2", "B2", "a row asking for a value it cannot be given is not approvable",
    INBOX / "InboxBand.swift",
    "        guard let entry = item.resolved else { return false }\n"
    "        return RegistryCapability.missingRequirements(for: entry, values: [:]).isEmpty",
    "        return item.resolved != nil",
    [
        "a row is approvable only when the entry resolved, the preference is on and nothing is blank",
        "canApprove refuses an unread entry and one with a value still blank",
    ],
)

mut(
    "M20-C1", "C1", "no route of either notification family installs anything",
    INBOX / "FindingArrival.swift",
    "        case .reviewCapability, .explainFinding, .dismiss, .openInbox: false",
    "        case .reviewCapability: true\n"
    "        case .explainFinding, .dismiss, .openInbox: false",
    [
        "no route of either notification family installs anything, over every case",
        "every registered category offers nothing that installs, across both families",
    ],
)

# D1's exception, mutated at the gate rather than at the button: dropping the preference check is the
# edit that ships an install path nobody asked for, and the band's own `isApprovable` would still
# hide the control — so a clause reading only the view would stay green.
mut(
    "M20-D1", "D1", "the popover's install path re-checks every condition rather than trusting the view",
    UI_SHELL / "ShellModelInbox.swift",
    "            guard isApproveFromPopoverEnabled,\n"
    "                  let item = inboxBoard.rows.first(where: { $0.id == itemID }),\n"
    "                  InboxBand.canApprove(item),",
    "            guard let item = inboxBoard.rows.first(where: { $0.id == itemID }),",
    "approving from the popover installs exactly once, and only under all three conditions",
)


if __name__ == "__main__":
    sys.exit(main())
