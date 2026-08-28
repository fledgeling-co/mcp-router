#!/usr/bin/env python3
"""Arm the suite-backed cases: revert the behaviour, watch the test go red, restore.

An assertion nobody has watched fail is indistinguishable from one that cannot fail.
For each case this applies a named mutation to the PRODUCTION source the case's own
test guards, runs that test alone, and records whether it went red.

Two traps this defends against, both measured in this repo:

  * `swift test --filter X` exits 0 having run ZERO tests when the filter matches
    nothing. The legacy XCTest bundle prints "Executed 0 tests" on every run, so the
    only trustworthy count is swift-testing's own "Test run with N test(s)" line.
    A red that ran 0 tests is not a red.

  * A mutation that fails to COMPILE also makes the run non-zero, which reads exactly
    like a caught defect. Build failure is classified separately and is not an arm.

Restore is unconditional: the original bytes are held in memory and rewritten in a
finally, and the driver re-runs the test after restoring to prove the tree is green
again before moving to the next arm.

    python3 arm-suites.py            # every arm -> evidence/runs/arm-suites.log
    python3 arm-suites.py CASE-0031  # one arm   -> evidence/runs/arm-suites.0031.log
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[3] / "app"
RUNS = Path(__file__).resolve().parent.parent / "evidence" / "runs"


def out_path(selected: list[str]) -> Path:
    """Where this invocation's log goes — and why a subset does not write the full run's file.

    Until J2 every invocation wrote `arm-suites.log`, so `arm-suites.py CASE-0031` REPLACED the
    record of all thirteen arms with a record of one. Measured 2026-08-29: a nine-case run took the
    file from `denominator: 13, armed: 13` to `denominator: 9, armed: 9`, and CASE-0008's evidence
    list still cited it. The loss is silent, the file is still well-formed, and every case citing it
    now points at a run that never examined its arm.

    A subset therefore writes its own file, named for what it selected. The canonical name belongs
    to the run that attempted every arm, which is the only run whose denominator means what the
    filename implies.
    """
    if not selected:
        return RUNS / "arm-suites.log"
    lo, hi = selected[0].removeprefix("CASE-"), selected[-1].removeprefix("CASE-")
    span = lo if lo == hi else f"{lo}-{hi}"
    return RUNS / f"arm-suites.{span}.log"

# (case, filter, [(relative source, old, new)], what reverting proves
ARMS = [
    (
        "CASE-0007", "withdrawalIsCommandedAtTheDisposition",
        [("Sources/MCPRouterUI/Boards/InboxBoardModel+Arrivals.swift",
          "            pendingWithdrawal = Task { [notifier] in\n"
          "                await notifier.withdraw(itemIDs: [itemID, InboxAnnouncement.manyIdentifier])\n"
          "            }",
          "            _ = itemID")],
        "a disposition withdrawing its own banner at the moment it happens. Reverting "
        "leaves the notification standing for an item the user has already dealt with, "
        "so the banner invites a second decision on a settled thing.",
    ),
    (
        "CASE-0008", "footerRefusesTheFabrication",
        [("Sources/MCPRouterKit/Cleanup/CleanupPresentation.swift",
          '"memory saving: MCP Router never runs',
          '"memory reclaimed (MB): MCP Router never runs')],
        "the cleanup footer's refusal to claim a memory saving — the honesty guardrail "
        "REQ-007 names. Reverting it turns the disclaimer into the fabrication.",
    ),
    (
        "CASE-0009", "loopbackPinned",
        [("Sources/RouterCore/HTTP/LoopbackHTTPServer.swift",
          "        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(\n"
          "            host: .ipv4(.loopback), port: endpointPort\n"
          "        )",
          "        _ = endpointPort")],
        "the IPv4-loopback pin on the control listener. Without it NWListener binds every "
        "interface and puts an endpoint that runs the user's MCP servers on the LAN.",
    ),
    (
        "CASE-0017", "declineIsUndoable",
        [("Sources/MCPRouterUI/Boards/InboxBoardModel.swift",
          "            dispositioned[item.id] = nil\n            lastDisposition = nil",
          "            _ = item\n            lastDisposition = nil")],
        "undo actually restoring the declined row. Reverting leaves a control labelled "
        "Undo that reports success and restores nothing.",
    ),
    (
        "CASE-0018", "refusedWriteThrows",
        [("Sources/MCPRouterKit/Discover/CapabilityQueue.swift",
          "    public func enqueue(_ item: QueuedCapability) async throws {\n"
          "        if let failure { throw failure }\n"
          "        guard !items.contains(where: { $0.id == item.id }) else { return }\n"
          "        items.append(item)",
          "    public func enqueue(_ item: QueuedCapability) async throws {\n"
          "        _ = failure\n"
          "        guard !items.contains(where: { $0.id == item.id }) else { return }\n"
          "        items.append(item)")],
        "a refused write throwing rather than reporting success. Reverting makes a failed "
        "enqueue silently succeed, which is REQ-019's guardrail exactly.",
    ),
    (
        "CASE-0023", "popularityUnitIsPinned",
        [("Sources/MCPRouterKit/Discover/DiscoverCopyControls.swift",
          '"{count} sessions on Smithery"', '"{count} installs on Smithery"')],
        "the popularity unit saying sessions, which is what Smithery publishes. Reverting "
        "it claims installs, a number nobody measured.",
    ),
    (
        "CASE-0030", "singleFlight",
        [("Sources/RouterCore/Pool/UpstreamPool.swift",
          "        if let flight = entry.starting {",
          "        if false, let flight = entry.starting {")],
        "single-flight on a cold upstream. Reverting spawns one child per concurrent "
        "caller, so three leases start three real processes.",
    ),
    (
        "CASE-0031", "splitMatches",
        [("Sources/RouterCore/Manifest/ToolUnion.swift",
          "                index = start\n                break", "                index = start")],
        "splitting a namespaced tool name at the FIRST separator. Reverting splits at the "
        "last, which routes a__b__c to a server that does not exist.",
    ),
    (
        "CASE-0032", "warmIsNeverReaped",
        [("Sources/RouterCore/Pool/UpstreamPoolReaping.swift",
          "        if config.warm == true { return }",
          "        if config.warm == false { return }")],
        "a warm upstream never being reaped. Reverting reaps exactly the servers the user "
        "committed to paying to keep resident.",
    ),
    (
        "CASE-0033", "patchCannotRewriteACommandLine",
        [("Sources/MCPRouterKit/Control/ServerPatch.swift",
          "        case projects, warm, idleMs, placard",
          "        case projects, warm, idleMs, placard, command"),
         ("Sources/MCPRouterKit/Control/ServerPatch.swift",
          "        try container.encodeIfPresent(projects, forKey: .projects)",
          "        try container.encodeIfPresent(projects, forKey: .projects)\n"
          '        try container.encode("bash", forKey: .command)')],
        "the control API being unable to put a command line on the wire. Reverting lets a "
        "PATCH rewrite what binary a server runs.",
    ),
    (
        "CASE-0034", "lockSerialises",
        [("Sources/RouterCore/Config/ConfigMutationLock.swift",
          "            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { break }",
          "            if true { break }")],
        "the exclusive flock that serialises config mutation. Reverting lets two holders "
        "overlap, so one writer's servers.json clobbers the other's.",
    ),
    (
        "CASE-0035", "untokenedAuthIs401",
        [("Sources/RouterCore/Control/ControlHandler.swift",
          "        guard request.isMutating else { return nil }",
          "        guard false, request.isMutating else { return nil }")],
        "the token gate running ahead of routing, so an untokened mutation is 401 rather "
        "than 404. Reverting makes an unauthorized call indistinguishable from a typo.",
    ),
    (
        "CASE-0037", "codeIsExchangedOverTheWire",
        [("Sources/RouterCore/Auth/CallbackResponder.swift",
          "            try await exchange(authorizationCode)",
          "            if authorizationCode.isEmpty { try await exchange(authorizationCode) }")],
        "the callback actually exchanging the authorization code it received. Reverting "
        "serves the success page for a code that was never redeemed.",
    ),
    # ---------------------------------------------------------------------------------------
    # J2 · the control census's numerator. Each of these five seeds the inert-UI defect itself —
    # a handler that runs and changes nothing — behind a control the registry now claims is
    # actuated, and requires the case that claims it to go red. Without them the census is a count
    # nobody should believe: `references/inert-ui.md` is one campaign reporting 32 of 32 over an
    # app whose every button was `Button("…") {}`, and every check it ran passed on that build.
    #
    # The mutations are deliberately the EMPTY-CLOSURE shape rather than an inverted comparison.
    # An inverted filter still draws a different row set, so a case reading "the rows changed"
    # survives it; a handler that does nothing is the thing the census is a denominator for.
    (
        "CASE-0195", "eachSelectionReachesTheStore",
        [("Sources/MCPRouterUI/Shell/ShellModel.swift",
          "        public func select(_ destination: Destination) {\n"
          "            selection = destination\n"
          "        }",
          "        public func select(_ destination: Destination) {\n"
          "            _ = destination\n"
          "        }")],
        "the sidebar's selection reaching the model at all. Reverting it is the destination-"
        "collapse defect in one line: seven rows that render, carry their accessible names, "
        "accept a press and take you nowhere. The restoration store goes silent, which is the "
        "channel the case reads.",
    ),
    (
        "CASE-0196", "eachServersSegmentFiltersTheTable",
        [("Sources/MCPRouterUI/Boards/ServersBoardModel.swift",
          "                .filter { filter.matches($0) && ServerSearch.matches($0, query: searchQuery) }",
          "                .filter { ServerSearch.matches($0, query: searchQuery) }")],
        "the Servers filter bar reaching the table. Reverting leaves four segments that select, "
        "highlight and draw the same four rows — a control whose only proof of working would be "
        "that it now looks pressed.",
    ),
    (
        "CASE-0197", "eachSkillsSegmentFiltersTheTable",
        [("Sources/MCPRouterUI/Boards/SkillsBoardModel.swift",
          "            return SkillPresentation.rows(response.skills, filter: filter, search: search)",
          "            return SkillPresentation.rows(response.skills, filter: .all, search: search)")],
        "the Skills filter bar reaching the list. Reverting makes `Held` draw the whole board "
        "while still reporting itself selected.",
    ),
    (
        "CASE-0198", "eachChecksSegmentFiltersTheTable",
        [("Sources/MCPRouterUI/Boards/EvalsBoardModel.swift",
          "            CheckPresentation.rows(subjects, filter: filter, search: search)",
          "            CheckPresentation.rows(subjects, filter: .all, search: search)")],
        "the Checks filter bar reaching the list, in the same shape as the two above.",
    ),
    (
        "CASE-0199", "warmSendsOnlyWarm",
        [("Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
          "        func setWarm(_ name: String, to warm: Bool) async {\n"
          "            await write(name) { [client, tracker] () async throws(ControlAPIError) in\n"
          "                let updated = try await client.patch(server: name, ServerPatch(warm: warm))\n"
          "                await tracker.apply(updated: updated)\n"
          "            }\n"
          "        }",
          "        func setWarm(_ name: String, to warm: Bool) async {\n"
          "            _ = (name, warm)\n"
          "        }")],
        "`Keep warm` putting anything on the wire. This is the empty closure verbatim — the "
        "switch moves, the row redraws from the model it already had, and the router is never "
        "told. The case reads the request the client recorded, which is the channel that goes "
        "quiet.",
    ),
    (
        "CASE-0200", "projectsSendsAnExplicitArray",
        [("Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
          "        func setProjects(_ name: String, to projects: [String]) async {\n"
          "            await write(name) { [client, tracker] () async throws(ControlAPIError) in\n"
          "                let updated = try await client.patch(server: name, ServerPatch(projects: projects))\n"
          "                await tracker.apply(updated: updated)\n"
          "            }\n"
          "        }",
          "        func setProjects(_ name: String, to projects: [String]) async {\n"
          "            _ = (name, projects)\n"
          "        }")],
        "`Only load in named projects` reaching the router. Reverting leaves a directory picker "
        "that opens, returns a path and scopes nothing.",
    ),
    (
        "CASE-0201", "resetReindexesAnIndexFailure",
        [("Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
          "                    let result = try await client.reindex(server.name)\n"
          "                    if let error = result.error {\n"
          "                        throw ControlAPIError.server(status: 422, message: error, hint: nil)\n"
          "                    }",
          "                    _ = server")],
        "`Reset` re-indexing a server tripped by a failed index. Reverting clears the in-flight "
        "mark and the row settles looking fixed, having asked the router nothing.",
    ),
    (
        "CASE-0202", "removeSendsKeepHistory",
        [("Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
          "            await write(name) { [client] () async throws(ControlAPIError) in\n"
          "                _ = try await client.remove(name, keepHistory: keepHistory)\n"
          "            }",
          "            _ = (name, keepHistory)")],
        "`Remove` issuing the deletion, and carrying the history checkbox with it. Reverting "
        "closes the sheet and drops the selection — the acknowledgement-only shape exactly, since "
        "both of those are the app's own report that it worked.",
    ),
    (
        "CASE-0203", "approveWritesAndKeepingDoesNot",
        [("Sources/MCPRouterUI/Boards/ServersBoardWrites.swift",
          "            await write(name) { [client] () async throws(ControlAPIError) in\n"
          "                _ = try await client.approvePendingChange(server: name)\n"
          "            }",
          "            _ = name")],
        "`Accept the new text` approving the held change. Reverting dismisses the sheet and "
        "clears the held diff from the model, so the user sees the change accepted and the router "
        "goes on serving the old text.",
    ),
]

RUN_LINE = re.compile(r"Test run with (\d+) test", re.I)


def run(test_filter: str) -> dict:
    """Run one filtered test. Distinguish red, green, ran-nothing and build failure."""
    p = subprocess.run(["swift", "test", "--filter", test_filter],
                       cwd=APP, capture_output=True, text=True, timeout=1800)
    out = p.stdout + p.stderr
    if "error:" in out and "Build complete" not in out:
        return {"verdict": "build-failed", "tests": 0, "exit": p.returncode,
                "detail": next((ln.strip() for ln in out.splitlines() if "error:" in ln), "")}
    m = RUN_LINE.search(out)
    tests = int(m.group(1)) if m else 0
    if tests == 0:
        return {"verdict": "ran-nothing", "tests": 0, "exit": p.returncode,
                "detail": "the filter matched no swift-testing test; exit code is meaningless"}
    failed = "Test run with" in out and "failed after" in out
    return {"verdict": "red" if failed else "green", "tests": tests, "exit": p.returncode,
            "detail": next((ln.strip()[:200] for ln in out.splitlines()
                            if "✘" in ln and "Test " in ln), "")}


def main() -> int:
    only = [a for a in sys.argv[1:] if a.startswith("CASE-")]
    arms = [a for a in ARMS if not only or a[0] in only]
    out = out_path(sorted(only))
    log, armed, refused = [], [], []

    print(f"arming {len(arms)} of {len(ARMS)} suite-backed cases\n")
    for case, filt, edits, proves in arms:
        originals = {}
        try:
            for rel, old, new in edits:
                path = APP / rel
                text = originals.setdefault(path, path.read_text())
                current = path.read_text()
                if current.count(old) != 1:
                    raise AssertionError(
                        f"{rel}: mutation anchor appears {current.count(old)} times, need 1")
                path.write_text(current.replace(old, new, 1))
            r = run(filt)
        except AssertionError as e:
            r = {"verdict": "anchor-missing", "tests": 0, "exit": -1, "detail": str(e)}
        finally:
            for path, text in originals.items():
                path.write_text(text)

        back = run(filt) if r["verdict"] in {"red", "green"} else None
        ok = r["verdict"] == "red" and back and back["verdict"] == "green"
        (armed if ok else refused).append(case)
        row = {"case": case, "filter": filt, "mutated": r, "restored": back,
               "reverts": proves, "armed": ok,
               "files": [e[0] for e in edits]}
        log.append(row)
        mark = "ARMED " if ok else "REFUSED"
        print(f"  {mark} {case}  {filt}  mutated={r['verdict']}({r['tests']} test(s))"
              + (f" restored={back['verdict']}({back['tests']})" if back else "")
              + ("" if ok else f"  <- {r['detail'][:120]}"))

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"arms": log, "armed": armed, "refused": refused,
                               "denominator": len(arms)}, indent=1) + "\n")
    print(f"\narmed {len(armed)} of {len(arms)} attempted · refused {len(refused)}"
          + (f" ({', '.join(refused)})" if refused else ""))
    print(f"wrote {out}")
    return 0 if not refused else 1


if __name__ == "__main__":
    raise SystemExit(main())
