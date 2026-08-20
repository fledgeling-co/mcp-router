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

    python3 arm-suites.py            # every arm
    python3 arm-suites.py CASE-0031  # one arm
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[3] / "app"
OUT = Path(__file__).resolve().parent.parent / "evidence" / "runs" / "arm-suites.log"

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

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"arms": log, "armed": armed, "refused": refused,
                               "denominator": len(arms)}, indent=1) + "\n")
    print(f"\narmed {len(armed)} of {len(arms)} attempted · refused {len(refused)}"
          + (f" ({', '.join(refused)})" if refused else ""))
    print(f"wrote {OUT}")
    return 0 if not refused else 1


if __name__ == "__main__":
    raise SystemExit(main())
