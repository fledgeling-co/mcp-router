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
    "M40", "F4-A1", "the poll loop reports a typed error instead of discarding it",
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
    "M41", "F4-A3", "a stale snapshot is not collapsed into a plain failure",
    SRC / "ServerStateTracker.swift",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)",
    "        loadKind = .failed(error)",
    "a failure after a success is stale",
)

mut(
    "M42", "F4-A3", "a failed poll does not delete the servers it already had",
    SRC / "ServerStateTracker.swift",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)\n        publish()",
    "        loadKind = hasLoaded ? .stale(error) : .failed(error)\n"
    "        servers = [:]\n        order = []\n        publish()",
    "a failure after a success is stale",
)

mut(
    "M43", "F4-A6", "a tracker with no stream is not born claiming a dropped one",
    SRC / "ServerStateTracker.swift",
    "        self.streamCondition = stream == nil ? .notConfigured : .phase(.disconnected)",
    "        self.streamCondition = .phase(.disconnected)",
    "is not-configured, never a dropped stream",
)

mut(
    "M44", "F4-A8", "a phase cannot be fabricated for a tracker that has no stream",
    SRC / "ServerStateTracker.swift",
    "        guard case let .phase(current) = streamCondition else { return }",
    "        let current = if case let .phase(p) = streamCondition { p } "
    "else { StreamPhase.disconnected }",
    "a phase cannot be fabricated",
)

mut(
    "M45", "F4-A11", "subscribing registers before updates() returns, losing nothing",
    SRC / "ServerStateTracker.swift",
    "        register(id, continuation)",
    "        Task { self.register(id, continuation) }",
    "published immediately after subscribing is delivered",
)

mut(
    "M46", "F4-A11", "an unchanged state is not republished",
    SRC / "ServerStateTracker.swift",
    "        guard snapshot != lastPublished else { return }",
    "        if false { return }",
    "an identical state is not published twice",
)

mut(
    "M47", "F4-A4", "run() twice does not start a second poll loop",
    SRC / "ServerStateTracker.swift",
    "        guard !isRunning else { return }",
    "        if false { return }",
    "running twice does not start a second poll loop",
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

RESULTS = []


def run_suite() -> tuple[bool, str]:
    proc = subprocess.run(
        ["swift", "test", "--no-parallel"],
        cwd=APP, capture_output=True, text=True,
    )
    scrub_residue()
    return proc.returncode == 0, proc.stdout + proc.stderr


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


if __name__ == "__main__":
    sys.exit(main())
