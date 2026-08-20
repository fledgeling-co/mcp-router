#!/usr/bin/env python3
"""Arm the headless cases: break the behaviour each one guards, require RED, restore.

A passing assertion nobody has watched fail is not known to bite. This applies one
mutation per case — the plausible wrong implementation rather than arbitrary damage —
runs only that case's suite, and requires the suite to go red.

Three outcomes, deliberately distinguished, following scripts/parity/mutation-gate.sh:

  RED    the suite failed under the mutation. The case is armed.
  GREEN  the suite passed under the mutation. The assertion is a DECORATION and the
         case stays unarmed; that is a finding about the suite, not a pass.
  UNRUN  the edit did not apply, or the filter executed zero tests. A failure, never a
         pass: a mutation whose pattern has drifted leaves the tree unmutated and the
         suite green, which would otherwise be reported as a decoration.

Restores from an in-memory copy rather than `git checkout -- app`: this tree carries
uncommitted campaign work in app/, and the wider revert would take it too.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "app"
KIT = "app/Sources/MCPRouterKit"
UI = "app/Sources/MCPRouterUI"
CORE = "app/Sources/RouterCore"
LOGS = ROOT / "planning/test-campaign/evidence/arming"

# case @@ suite filter @@ edits @@ what the mutation breaks
#
# Each `find` must appear exactly once in its file. The replacement expresses the wrong
# implementation a careful port would plausibly reach for.
ROWS: list[dict] = [
    {
        "case": "CASE-0005",
        "filter": "InboxAnnouncementTests",
        "breaks": "the many-item banner offers a decline, so the action set stops being pinned",
        # Aimed at `make`, which states the set the announcement carries. Measured 2026-08-19:
        # mutating `InboxNotificationCategory.many` — the *second* statement, the one the notifier
        # registers with macOS — left this suite green over all ten clauses. That hole is now closed
        # by `actionSetsRoundTripThroughACategory`, so either statement drifting is red.
        "edits": [(f"{KIT}/Inbox/InboxArrival.swift",
                   "                actions: [.review],\n                itemIDs: arrivals.map(\\.id)",
                   "                actions: [.review, .decline],\n"
                   "                itemIDs: arrivals.map(\\.id)")],
    },
    {
        "case": "CASE-0007",
        "filter": "InboxArrivalTests",
        "breaks": "a disposition stops withdrawing its own banner, leaving it up until the next poll",
        "edits": [(f"{UI}/Boards/InboxBoardModel.swift",
                   "            withdrawBanner(for: disposition.item.id)\n",
                   "")],
    },
    {
        "case": "CASE-0008",
        "filter": "CleanupPresentationTests",
        "breaks": "the cleanup footer claims a memory saving",
        "edits": [(f"{KIT}/Cleanup/CleanupPresentation.swift",
                   "Nothing here claims a ",
                   "Removing these reclaims a ")],
    },
    {
        "case": "CASE-0009",
        "filter": "ControlContractTests",
        "breaks": "a patch carries a command line onto the wire",
        "edits": [
            (f"{KIT}/Control/ServerPatch.swift",
             "        case projects, warm, idleMs, placard\n",
             "        case projects, warm, idleMs, placard, command\n"),
            (f"{KIT}/Control/ServerPatch.swift",
             "        var container = encoder.container(keyedBy: CodingKeys.self)\n",
             "        var container = encoder.container(keyedBy: CodingKeys.self)\n"
             "        try container.encode(\"sh\", forKey: .command)\n"),
        ],
    },
    {
        "case": "CASE-0017",
        "filter": "InboxBoardTests",
        "breaks": "the undo leaves the declined item declined",
        "edits": [(f"{UI}/Boards/InboxBoardModel.swift",
                   "            dispositioned[item.id] = nil\n            lastDisposition = nil",
                   "            lastDisposition = nil")],
    },
    {
        "case": "CASE-0018",
        "filter": "DiscoverCommitTests",
        "breaks": "a refused write is swallowed and reports success",
        "edits": [(f"{KIT}/Discover/CapabilityQueue.swift",
                   "    public func enqueue(_ item: QueuedCapability) async throws {\n"
                   "        if let failure { throw failure }\n"
                   "        guard !items.contains(where: { $0.id == item.id }) else { return }",
                   "    public func enqueue(_ item: QueuedCapability) async throws {\n"
                   "        if let failure { _ = failure }\n"
                   "        guard !items.contains(where: { $0.id == item.id }) else { return }")],
    },
    {
        "case": "CASE-0023",
        "filter": "DiscoverCopyTests",
        "breaks": "the popularity unit reports installs instead of sessions",
        "edits": [(f"{KIT}/Discover/DiscoverCopyControls.swift",
                   "DiscoverCopy.Entry(body: \"{count} sessions on Smithery\")",
                   "DiscoverCopy.Entry(body: \"{count} installs on Smithery\")")],
    },
    {
        "case": "CASE-0030",
        "filter": "RealProcessTests",
        "breaks": "an idle child is never reaped, so the pool leaks the process it spawned",
        "edits": [(f"{CORE}/Pool/UpstreamPoolReaping.swift",
                   "        else { return }\n        await reap(name: name, force: false)",
                   "        else { return }\n        if Bool(true) { return }\n"
                   "        await reap(name: name, force: false)")],
    },
    {
        "case": "CASE-0031",
        "filter": "ToolUnionParityTests",
        "breaks": "a namespaced tool name splits at the LAST separator instead of the first",
        "edits": [(f"{CORE}/Manifest/ToolUnion.swift",
                   "                index = start\n                break\n",
                   "                index = start\n")],
    },
    {
        "case": "CASE-0032",
        "filter": "PoolTests",
        "breaks": "the reaper stops considering work in flight, so a call outliving the idle window "
                  "has its own child closed underneath it",
        # P4 — "an upstream with a call outstanding is never reaped" — lives in PoolTests, not
        # PoolReapingTests. Measured 2026-08-19, and the reason it took three attempts is the finding:
        # this invariant is TRIPLE-guarded, and no single-point mutation can break it.
        #   1. `cancelReap` at lease time            — the timer armed at acquisition is torn down
        #   2. `entry.inFlight == 0` in the timer     — a cancelled task that still wakes is refused
        #   3. `if !force, entry.inFlight > 0` in reap — and refused again on arrival
        # Aimed at (2) alone: GREEN. At (2)+(3): GREEN. With `cancelReap` gone too: still GREEN —
        # because in P4's cold-start scenario no idle timer is ever armed during the call at all.
        # `armReapIfIdle` runs inside the start with `pendingWaiters == 1`, so arming is refused, and
        # the invariant rests on WHEN the timer is armed rather than on any of the three guards.
        # So the wrong implementation is the one `release`'s comment names: arm from call *start*.
        "edits": [
            (f"{CORE}/Pool/UpstreamPoolReaping.swift",
             "        guard entry.inFlight == 0, entry.pendingWaiters == 0, let handle = entry.handle "
             "else { return }\n",
             "        guard let handle = entry.handle else { return }\n"),
            ("app/Sources/RouterCore/Pool/UpstreamPool.swift",
             "        entry.inFlight += 1\n        cancelReap(&entry)\n",
             "        entry.inFlight += 1\n        armReap(name: name, entry: &entry)\n"),
            (f"{CORE}/Pool/UpstreamPoolReaping.swift",
             "              entry.inFlight == 0, // nothing outstanding\n",
             ""),
            (f"{CORE}/Pool/UpstreamPoolReaping.swift",
             "        if !force, entry.inFlight > 0 { return }\n",
             ""),
        ],
    },
    {
        "case": "CASE-0033",
        "filter": "ListenerFailureTests",
        "breaks": "the control listener binds every interface instead of IPv4 loopback",
        "edits": [(f"{CORE}/HTTP/LoopbackHTTPServer.swift",
                   "host: .ipv4(.loopback), port: endpointPort",
                   "host: .ipv4(.any), port: endpointPort")],
    },
    {
        "case": "CASE-0034",
        "filter": "ImportConfigWriterLockTests",
        "breaks": "the read moves outside the lock, so a concurrent write is clobbered from a stale snapshot",
        "edits": [
            (f"{CORE}/Config/ImportConfigWriter.swift",
             "        let path = destination.path\n        try ConfigMutationLock.withExclusiveLock(",
             "        let path = destination.path\n"
             "        let preRead = existingMembers(at: path, fileSystem: fileSystem)\n"
             "        try ConfigMutationLock.withExclusiveLock("),
            (f"{CORE}/Config/ImportConfigWriter.swift",
             "                into: existingMembers(at: path, fileSystem: fileSystem),",
             "                into: preRead,"),
        ],
    },
    {
        "case": "CASE-0035",
        "filter": "ControlAuthStartDispatchTests",
        "breaks": "the token gate runs after route ownership, so an untokened call answers 404 before 401",
        "edits": [(f"{CORE}/Control/ControlHandler.swift",
                   "            return .error(401, \"unauthorized; the token is in \\(tokenPath)\")",
                   "            return .error(404, \"not found\")")],
    },
    {
        "case": "CASE-0037",
        "filter": "CallbackListenerTests",
        "breaks": "the callback serves its page without exchanging the code",
        "edits": [(f"{CORE}/Auth/CallbackResponder.swift",
                   "            try await exchange(authorizationCode)\n",
                   "")],
    },
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def run_suite(filt: str) -> tuple[int, str]:
    proc = subprocess.run(
        ["swift", "test", "--filter", filt],
        cwd=APP, capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def executed(out: str) -> int:
    """Tests actually run. A filter naming nothing exits 0 having run none."""
    total = 0
    for m in re.finditer(r"Test run with (\d+) test", out):
        total += int(m.group(1))
    if total == 0:
        m = re.search(r"Executed (\d+) test", out)
        if m:
            total = int(m.group(1))
    return total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cases", nargs="*", help="case ids; default every row")
    ap.add_argument("--baseline", action="store_true",
                    help="run each suite unmutated and report the executed count")
    args = ap.parse_args()

    rows = [r for r in ROWS if not args.cases or r["case"] in args.cases]
    if not rows:
        print(f"no rows matched {args.cases}", file=sys.stderr)
        return 2

    dirty = subprocess.run(["git", "status", "--porcelain", "--", "app/Sources"],
                           cwd=ROOT, capture_output=True, text=True).stdout.strip()
    if dirty:
        print("refusing to start: app/Sources has uncommitted edits a restore would clobber:")
        print(dirty)
        return 2

    LOGS.mkdir(parents=True, exist_ok=True)
    results = []

    for row in rows:
        cid, filt = row["case"], row["filter"]

        if args.baseline:
            code, out = run_suite(filt)
            n = executed(out)
            verdict = "GREEN" if code == 0 and n > 0 else ("UNRUN" if n == 0 else "RED")
            print(f"{cid:10} baseline {verdict:6} executed={n} exit={code} filter={filt}")
            results.append({"case": cid, "phase": "baseline", "verdict": verdict,
                            "executed": n, "exit": code, "filter": filt})
            continue

        # Back up every file this row touches, in memory and on disk.
        touched = sorted({e[0] for e in row["edits"]})
        backup = {f: (ROOT / f).read_bytes() for f in touched}
        applied: list[str] = []
        verdict, note, n, code, out = "UNRUN", "", 0, -1, ""

        try:
            for rel, find, repl in row["edits"]:
                path = ROOT / rel
                text = path.read_text()
                hits = text.count(find)
                if hits != 1:
                    note = (f"pattern occurs {hits}× in {rel} — a mutation that does not apply "
                            f"leaves the tree unmutated and the suite green")
                    break
                path.write_text(text.replace(find, repl))
                applied.append(rel)
            else:
                code, out = run_suite(filt)
                n = executed(out)
                if "error:" in out and "Compiling" in out and code != 0 and n == 0:
                    verdict, note = "UNRUN", "the mutation did not compile, so nothing was measured"
                elif n == 0:
                    verdict, note = "UNRUN", f"--filter {filt} executed zero tests"
                elif code == 0:
                    verdict, note = "GREEN", (f"the suite passed with the behaviour broken — "
                                              f"{row['breaks']} is not what it measures")
                else:
                    verdict, note = "RED", f"{n} tests ran; the suite failed as required"
        finally:
            for f, raw in backup.items():
                (ROOT / f).write_bytes(raw)

        fails = [l.strip() for l in out.splitlines()
                 if re.search(r"(recorded an issue|✘|failed after|error:)", l)][:12]
        log = LOGS / f"{cid}.arming.log"
        log.write_text(
            f"case: {cid}\nfilter: {filt}\nverdict: {verdict}\nexecuted: {n}\nexit: {code}\n"
            f"breaks: {row['breaks']}\nnote: {note}\n"
            f"mutation:\n" + "".join(
                f"  {rel}\n    - {find.strip()[:160]}\n    + {repl.strip()[:160]}\n"
                for rel, find, repl in row["edits"]) +
            f"restored: {', '.join(f'{f}@{sha(ROOT / f)}' for f in touched)}\n"
            f"first failures:\n" + "\n".join(f"  {l[:200]}" for l in fails) + "\n"
        )
        print(f"{cid:10} {verdict:6} executed={n:4} exit={code:3} {filt:32} {note[:70]}")
        results.append({"case": cid, "verdict": verdict, "executed": n, "exit": code,
                        "filter": filt, "log": str(log.relative_to(ROOT)),
                        "breaks": row["breaks"], "note": note})

    out_json = LOGS / ("baseline.json" if args.baseline else "arming.json")
    prior = {}
    if out_json.exists():
        prior = {r["case"]: r for r in json.loads(out_json.read_text())}
    for r in results:
        prior[r["case"]] = r
    out_json.write_text(json.dumps(list(prior.values()), indent=1, sort_keys=True) + "\n")

    red = sum(1 for r in results if r["verdict"] == "RED")
    green = sum(1 for r in results if r["verdict"] == "GREEN")
    unrun = sum(1 for r in results if r["verdict"] == "UNRUN")
    print(f"\narmed {red}/{len(results)} · decorations {green} · did not run {unrun}")
    print(f"wrote {out_json.relative_to(ROOT)}")
    return 0 if unrun == 0 and green == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
