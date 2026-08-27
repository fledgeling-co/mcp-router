#!/usr/bin/env python3
"""Every figure the Insights board draws, traced to something the router OBSERVES.

WHY THIS EXISTS
---------------
`DESIGN.md` §6 forbids displaying a number the router does not observe, and Insights is the one
board made entirely of numbers — the surface where a fabricated figure is hardest to spot,
because a plausible number reads as a real one. Nothing had ever checked that rule here against
a live router.

It cannot be checked on the glass lane. `ShellClientFactory` makes a Debug build ALWAYS take a
fixture, so asserting `214 MB` in a rendered window would prove the fixture and say nothing
about the product. So the trace runs against the Swift router itself, over `GET /insights`.

WHAT A TRACE IS, AND WHAT FAILS ONE
-----------------------------------
Each figure the board draws is resolved to one of three classes, and only the first two pass:

  observed    the route serves it, and RouterCore takes the reading from something outside its
              own memory — the process table, the config file, the usage log, the pool.
  derived     the board computes it from members that are themselves observed. The derivation
              and BOTH its terms are stated. A derivation whose terms are not drawn beside it
              is still a derivation, but it is recorded as one rather than passing as a reading.
  untraceable no member of the response carries it. THIS FAILS THE CASE. It does not pass
              because the number looks reasonable — that is the whole point of this file.

THE CHECK THAT KEEPS THE MAP FROM GOING STALE
---------------------------------------------
A hand-written figure map is exactly the artefact that produced the finding this item came
from: the campaign's surface list stopped growing while the product did, and a completeness
gate reported clean over it. So the map is not trusted to be complete. `InsightsBoard.swift` is
parsed for every `identifier:` it draws a figure under, and a drawn identifier absent from the
map FAILS — a figure added to the board cannot escape the trace by not being written down here.

    python3 insights-live-probe.py --port 8976          # trace
    python3 insights-live-probe.py --port 8976 --arm    # + the two planted faults
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import subprocess
import sys
import urllib.request
import datetime

D = pathlib.Path(__file__).resolve().parent.parent
REPO = D.parent.parent
BOARD = REPO / "app" / "Sources" / "MCPRouterUI" / "Boards" / "InsightsBoard.swift"
OUT = D / "evidence" / "runs"

# identifier -> what the board draws there, and where the number comes from.
#
# `member` is a dotted path into the /insights response. `None` means the figure is not a
# reading at all — a label or an empty panel — and carries `class: "no-figure"`.
FIGURES = {
    "children": {
        "draws": "Child processes running: <alive>, with 'of <declared> declared' beneath",
        "member": "children.alive", "second": "children.declared", "class": "observed",
        "observedBy": "ControlInsights.insightsResponse: deps.pool.status() counted where "
                      "state == 'running' (the pool's live child table), and "
                      "deps.config.upstreams.count (the server list on disk)",
    },
    "resident": {
        "draws": "Resident, all children: '<megabytes> MB' or '—' when absent",
        "member": "resident.megabytes", "class": "observed",
        "observedBy": "ControlInsights.residentValue: sum over InsightsSource.resident(), which "
                      "UpstreamPool.residentMb() takes from the process table via ps(1). An "
                      "upstream with no local process is OMITTED rather than reported as zero, "
                      "so the member is null and the board draws '—'.",
        "absentIsNotZero": True,
    },
    "calls": {
        "draws": "Tool calls, last 24 hours: <total>",
        "member": "calls.total", "class": "observed",
        "observedBy": "ControlInsights: deps.usage.insights(...).totalCalls — records the "
                      "router wrote to its own usage log as it served them",
    },
    "failures": {
        "draws": "Failed calls: '<failed/total*100 to 2dp>%', with '<failed> of <total>' beneath",
        "member": "calls.failed", "second": "calls.total", "class": "derived",
        "derivation": "InsightsBoardCopy.failureRate = failed / total * 100, formatted %.2f%%; "
                      "'—' when total == 0. BOTH TERMS ARE DRAWN BESIDE IT by "
                      "failureProvenance, so the percentage is readable as the ratio it is "
                      "rather than as a reading of its own.",
        "observedBy": "the same usage-log window as `calls`",
    },
    "other": {
        "draws": "Other callers: <otherCalls>, drawn only when > 0",
        "member": "otherCalls", "class": "observed",
        "observedBy": "ControlInsights.harnessCallMembers: calls whose peer process no harness "
                      "claims. Present so the bars and the headline total reconcile rather "
                      "than quietly disagreeing.",
    },
}
# Bars are drawn per row from a list member; their identifiers are composed at render time
# (`duty-<server>`, and the harness's own id), so they are matched by prefix rather than named.
BAR_FAMILIES = {
    "duty-": {
        "draws": "Duty cycle, per server: one bar per server at "
                 "round(aliveSeconds / uptimeSeconds * 100)",
        "member": "dutyCycle.servers", "second": "dutyCycle.uptimeSeconds", "class": "derived",
        "derivation": "InsightsBoardCopy.share = min(1, aliveSeconds / uptimeSeconds). The "
                      "router reports BOTH numbers rather than a pre-divided share, precisely "
                      "so a surface holding both can decline to draw it: a share computed "
                      "against four seconds of uptime is arithmetically fine and means nothing.",
        "observedBy": "InsightsSource.dutyCycle() — the pool's own per-child alive time and "
                      "the router's uptime",
    },
}


def dig(payload, path):
    cur = payload
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None, False
        cur = cur[part]
    return cur, True


def drawn_identifiers() -> set[str]:
    """Every `identifier:` InsightsBoard.swift draws a figure under."""
    if not BOARD.exists():
        return set()
    text = BOARD.read_text()
    found = set(re.findall(r'identifier:\s*"([^"]+)"', text))
    # Composed identifiers: `identifier: "duty-\(server.server)"` and `identifier: row.harness`.
    found |= {m for m in re.findall(r'identifier:\s*"([a-z-]+)\\\(', text)}
    if re.search(r"identifier:\s*row\.harness", text):
        found.add("<row.harness>")
    return found


def check(results, label, ok, detail=""):
    results.append({"label": label, "pass": bool(ok), "detail": detail})
    print(f"  {'ok  ' if ok else 'FAIL'} {label}" + (f"\n         {detail}" if detail else ""))
    return ok


def trace(payload, figures, families, results):
    print("\n-- the trace: every figure, to something observed --")
    untraceable, observed, derived, absent = [], [], [], []
    for ident, spec in sorted(figures.items()):
        member = spec.get("member")
        value, present = dig(payload, member) if member else (None, False)
        # AN ABSENCE THE ROUTER DECLARED IS NOT AN UNTRACEABLE FIGURE, and reading it as one is
        # the mistake this branch exists to stop. Measured 2026-08-27: with no child holding a
        # process the route serves `resident: null`, `resident.megabytes` does not resolve, and
        # the first version of this script called that untraceable. It is the opposite — the
        # router reporting that there is nothing to report, which is precisely what §6 asks for,
        # and the board draws an em dash rather than a zero. The failing class is a member the
        # response does not carry AT ALL; a member carried and null is `absent`.
        if not present and spec.get("absentIsNotZero"):
            parent = member.rsplit(".", 1)[0]
            pval, ppresent = dig(payload, parent)
            if ppresent and pval is None:
                absent.append(ident)
                print(f"  absent    {ident:<10} {parent} = null — declared absent, so the "
                      f"board draws '—' rather than a 0")
                continue
        if not present:
            untraceable.append(f"{ident} (no member `{member}` in the response)")
            print(f"  UNTRACEABLE  {ident}: the board draws {spec['draws']!r} and the route "
                  f"carries no `{member}`")
            continue
        (observed if spec["class"] == "observed" else derived).append(ident)
        shown = "null (absent, not zero)" if value is None else value
        print(f"  {spec['class']:<9} {ident:<10} {member} = {shown}")
        if spec["class"] == "derived":
            second, ok2 = dig(payload, spec["second"])
            print(f"                       + {spec['second']} = {second}   "
                  f"[{'both terms present' if ok2 else 'SECOND TERM MISSING'}]")
            if not ok2:
                untraceable.append(f"{ident} (derivation term `{spec['second']}` absent)")

    for prefix, spec in sorted(families.items()):
        value, present = dig(payload, spec["member"])
        if not present:
            untraceable.append(f"{prefix}* (no member `{spec['member']}`)")
            print(f"  UNTRACEABLE  {prefix}*: no `{spec['member']}` in the response")
            continue
        n = len(value) if isinstance(value, list) else 0
        derived.append(prefix + "*")
        second, _ = dig(payload, spec["second"])
        print(f"  {spec['class']:<9} {prefix + '*':<10} {spec['member']} = {n} row(s), "
              f"{spec['second']} = {second}")

    check(results, "every figure the board draws resolves to a member of the response",
          not untraceable,
          "all traced" if not untraceable
          else "UNTRACEABLE: " + "; ".join(untraceable))
    return observed, derived, untraceable, absent


def completeness(figures, families, results):
    drawn = drawn_identifiers()
    known = set(figures) | {"<row.harness>"}
    prefixes = tuple(families)
    unmapped = sorted(
        d for d in drawn
        if d not in known and not d.startswith(prefixes)
        and not d.startswith("section-") and not d.startswith("caption-")
    )
    check(results, "every identifier InsightsBoard.swift draws a figure under is in this map",
          not unmapped,
          f"{len(drawn)} identifier(s) read out of the board's own source; mapped"
          if not unmapped else
          f"NOT IN THE MAP: {unmapped} — a figure was added to the board and this trace did "
          f"not know about it, which is how a surface list stops growing while a product does")
    return drawn, unmapped


def independent(payload, results, home: pathlib.Path):
    """The numbers this script can take for itself, without the router's code."""
    print("\n-- independent readings, taken by this script rather than trusted --")
    declared, _ = dig(payload, "children.declared")
    servers = home / "servers.json"
    mine = None
    if servers.is_file():
        try:
            doc = json.loads(servers.read_text())
            for key in ("mcpServers", "servers"):
                if isinstance(doc.get(key), dict):
                    mine = len(doc[key])
                    break
        except json.JSONDecodeError:
            mine = None
    check(results, "children.declared equals the server list this script counted itself",
          mine is not None and mine == declared,
          f"router says {declared}, {servers} holds {mine}")

    alive, _ = dig(payload, "children.alive")
    resident, has_res = dig(payload, "resident")
    # THE M32 CELL. `Resident, all children` is the figure the census caught; the rule it must
    # obey is that an absent reading is ABSENT, never a zero.
    if resident is None:
        check(results,
              "with no child holding a process, `resident` is null rather than 0 "
              "(absent is not zero)",
              alive == 0 and has_res,
              f"children.alive={alive}, resident=null — the board draws '—' and "
              f"'No child is running, so there is nothing to measure'")
    else:
        rss = subprocess.run(["ps", "-A", "-o", "rss="], capture_output=True, text=True).stdout
        total_mb = sum(int(x) for x in rss.split()) // 1024
        check(results, "resident.megabytes is within this machine's total RSS",
              0 < resident.get("megabytes", -1) <= total_mb,
              f"router says {resident.get('megabytes')} MB across "
              f"{resident.get('children')} child(ren); this machine's whole RSS is {total_mb} MB")

    window, _ = dig(payload, "windowHours")
    horizon, _ = dig(payload, "logHorizon")
    unreadable, _ = dig(payload, "calls.unreadableLines")
    check(results, "the window states its own bounds and what it could not read",
          window == 24 and unreadable is not None,
          f"windowHours={window}, logHorizon={horizon!r}, "
          f"calls.unreadableLines={unreadable} — a count of what parsed is not a count of "
          f"what was there, and the route carries both")

    total, _ = dig(payload, "calls.total")
    failed, _ = dig(payload, "calls.failed")
    check(results, "the failure rate's two terms are both served, so the board need not invent one",
          total is not None and failed is not None and failed <= total,
          f"failed={failed} of total={total}")

    analyst, present = dig(payload, "analyst")
    check(results, "the analyst member is present and null rather than absent",
          present and analyst is None,
          "the board draws its empty state from a fact the router STATED, not from a key it "
          "failed to find")


def main() -> int:
    port = sys.argv[sys.argv.index("--port") + 1] if "--port" in sys.argv else "8976"
    home = pathlib.Path(
        sys.argv[sys.argv.index("--home") + 1] if "--home" in sys.argv else "/tmp/g16-probe-home")
    url = f"http://127.0.0.1:{port}/insights"
    try:
        with urllib.request.urlopen(url, timeout=10) as fh:
            raw = fh.read()
    except Exception as exc:  # noqa: BLE001
        print(f"BLOCKED: no router answered {url} ({exc})")
        return 2

    sha = hashlib.sha256(raw).hexdigest()
    payload = json.loads(raw)
    print(f"live router  {url}")
    print(f"payload      {len(raw)} bytes  sha256 {sha}")
    print(f"generatedAt  {payload.get('generatedAt')}   windowHours "
          f"{payload.get('windowHours')}")

    try:
        taken = datetime.datetime.fromisoformat(
            payload.get("generatedAt", "").replace("Z", "+00:00"))
        age = (datetime.datetime.now(datetime.timezone.utc) - taken).total_seconds()
    except ValueError:
        age = 1e9

    results = []
    check(results, "generatedAt is a reading taken now, not a recording replayed",
          0 <= age < 120, f"{age:.0f}s old")
    drawn, unmapped = completeness(FIGURES, BAR_FAMILIES, results)
    observed, derived, untraceable, absent = trace(
        payload, FIGURES, BAR_FAMILIES, results)
    independent(payload, results, home)

    if "--arm" in sys.argv:
        print("\n-- ARM 1: a figure whose member is removed must go UNTRACEABLE --")
        wounded = json.loads(raw)
        wounded.get("calls", {}).pop("total", None)
        armed1 = []
        trace(wounded, FIGURES, BAR_FAMILIES, armed1)
        red1 = [c for c in armed1 if not c["pass"]]
        print(f"  {'ARMED' if red1 else 'ARM FAILED'}: {len(red1)} check(s) red with "
              f"`calls.total` removed")

        print("\n-- ARM 2: a figure drawn by the board but MISSING FROM THE MAP must go red --")
        shrunk = {k: v for k, v in FIGURES.items() if k != "resident"}
        armed2 = []
        completeness(shrunk, BAR_FAMILIES, armed2)
        red2 = [c for c in armed2 if not c["pass"]]
        print(f"  {'ARMED' if red2 else 'ARM FAILED'}: {len(red2)} check(s) red with "
              f"`resident` dropped from the map")

        again = hashlib.sha256(raw).hexdigest()
        print(f"\n  restored: sha256 {sha}\n            re-read {again}   "
              f"identical={again == sha}")
        if not red1 or not red2:
            return 1

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "insights-live-probe.json").write_text(json.dumps({
        "url": url, "sha256": sha, "generatedAt": payload.get("generatedAt"),
        "identifiersDrawn": sorted(drawn), "unmapped": unmapped,
        "observed": observed, "derived": derived, "untraceable": untraceable,
        "absentByDeclaration": absent,
        "figureMap": {k: {kk: vv for kk, vv in v.items()} for k, v in FIGURES.items()},
        "barFamilies": BAR_FAMILIES,
        "checks": results, "pass": all(c["pass"] for c in results),
    }, indent=1) + "\n")
    (OUT / "insights-live-payload.json").write_bytes(raw)

    failures = [c["label"] for c in results if not c["pass"]]
    print(f"\nchecked={len(results)} failures={len(failures)}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
