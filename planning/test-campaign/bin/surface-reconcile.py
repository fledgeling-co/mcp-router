"""Refuse a campaign whose surface list disagrees with the product's own list of surfaces.

WHAT WENT WRONG, AND WHY THE GATE THAT EXISTED COULD NOT SEE IT
---------------------------------------------------------------
`campaign.py check` asks which ENUMERATED surface has no case. Every enumerated surface has one,
so it reports clean — and it reported clean while the app shipped three surfaces the campaign had
never heard of. M22 added the Harnesses and Insights boards and M30 added the capability-document
viewer; the campaign's surface list is written by hand and none of the three followed. A surface
that was never enumerated is invisible to a check keyed on enumeration. This is the shape M32
closed for mock elements by making the census total: an element outside every rule could not be
reported by a gate that reports by rule.

So the denominator has to come from somewhere other than the list being checked. It comes from the
app: `bin/surface-oracle.swift` is COMPILED against the shipped `Destination.swift` and
`RouterSheet.swift` and prints what the app itself says it ships.

WHY COMPILED AND NOT PARSED
---------------------------
Two facts decide rows here and neither is legible in the source text.

  * `Destination.title` is a `switch` that does not follow the case names — `.evals` reads
    `Checks`. A `case`-line scraper prints `Evals`. M35 measured this exact trap one directory over
    in `scripts/acceptance/mac-shell.sh`, where the scraped label was the one string that lane
    asserts is gone.
  * `RouterSheet.Kind.isHosted` is computed from `owner`, another `switch`. All sixteen kinds look
    identical as `case` lines, and three of them (`analyzer`, `recommendation`, `reconcile`) are
    drawn in the mock with no board able to present them. A parser cannot tell a shipped sheet from
    an owed one, so it would demand campaign coverage of three sheets that do not exist.

WHAT IS DERIVED AND WHAT IS WRITTEN BY HAND
-------------------------------------------
Address is derived; expectation is written. The oracle says WHERE a surface lives and WHAT IT IS
CALLED; `surface-bindings.json` says WHICH CAMPAIGN SURFACE covers it. That split is M35's and it
is load-bearing: a fully derived binding would invent a campaign surface for every address the app
grows, so the denominator would move with the app and stop catching the one thing this exists to
catch — a surface shipped with nobody having decided how to test it. A human still writes the row.
What a human no longer has to do is NOTICE that the row is missing.

THE CLASSES ARE SEPARATE BECAUSE THE REMEDIES ARE
--------------------------------------------------
Conflating them is how this stayed invisible for two milestones.

  SHIPPED-UNENUMERATED   the app presents it; the campaign has no surface for it.
                         Remedy: enumerate a surface and write cases. Nobody has decided how to
                         test this yet. THIS is the class that was unreportable before today.
  ENUMERATED-UNCOVERED   a surface exists for it and no case cites that surface.
                         Remedy: write a case. Somebody decided how to test it and did not.
  BOUND-TO-UNKNOWN       a binding names a surface id `inventory.json` does not hold.
                         Remedy: fix the binding, or restore the surface.
  STALE-BINDING          a binding names an address the app no longer ships.
                         Remedy: retire the binding — and check the surface is not now testing a
                         thing that is gone.
  BOUND-BUT-UNSHIPPED    a binding claims a sheet kind no board can present.
                         Remedy: retire the binding. A campaign surface for an unpresentable sheet
                         is a paper surface, which is the failure this repository has shipped once.
  UNEXPLAINED-ADDRESSLESS
                         a Mac campaign surface no binding names and `addressless` does not
                         explain. Remedy: bind it, or record why it has no product address. This is
                         the reverse direction, and without it the campaign could grow surfaces the
                         product does not have and nothing would say so.

THE SEED FILES, AND WHY EQUALITY IS THE WRONG CHECK FOR THEM
-------------------------------------------------------------
The brief that ordered this work notes that `requirements.in.json` holds 20 rows and
`inventory.json` holds 25, and reads the five as having been added to one side with nothing
reconciling the two. Measured across all six pairs, that is the general shape rather than a
requirement-specific slip, and it is not drift:

    requirements.in.json  20 -> 25     cases.in.json      47 -> 85
    surfaces.in.json      17 -> 24     defects.in.json    18 -> 57
    components.in.json     8 ->  8     flows.in.json       5 ->  5

Nothing in the vendored campaign machinery reads a `*.in.json` file at all — `campaign.py` ingests
one once via `add --file` and everything afterwards is `inventory.json` and `cases.json`. The
seeds are the campaign's opening enumeration, and the live set is meant to grow past them; 47 cases
becoming 85 is the campaign working. Demanding equality would force an input file to be rewritten
on every added case, which is a second hand-maintained list and the exact illness this file is
about.

The invariant that IS meaningful, and that this gate enforces, is the other direction: nothing the
campaign opened with may vanish from the live set. That is silent narrowing, and it is what the
requirement list would actually be guilty of if a requirement it started with stopped being
tracked. All six pairs satisfy it today, and `SEED-ORPHAN` is the class that fires if one stops.

EXITS
-----
    0  the campaign's surface set and the product's agree, in every direction
    1  they disagree — every disagreeing address is named, in its class
    2  the presence control failed; no verdict is printed, because a count from an instrument that
       cannot see the defect is not evidence
    3  the oracle could not be built or did not run — which is not a clean campaign
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
D = ROOT / "planning" / "test-campaign"
ORACLE_SRC = D / "bin" / "surface-oracle.swift"
APP = ROOT / "app" / "Sources" / "MCPRouterKit" / "Shell"
PRODUCT_SOURCES = [APP / "Destination.swift", APP / "RouterSheet.swift"]

# The lanes whose surfaces the Mac app's own types can address. A router-daemon or ios-glass
# surface has no row in `Destination` or `RouterSheet`, so the reverse check below would demand an
# explanation for all thirteen of them and teach everyone to write one.
MAC_LANE = "macos-glass"


def run_oracle():
    """Compile the oracle against the shipped sources and return its rows.

    Returns (rows, None) or (None, reason). A build failure is a reason, never an empty list: an
    empty list would flow through every loop below and print a clean verdict over an app nobody
    read.
    """
    with tempfile.TemporaryDirectory() as tmp:
        binary = Path(tmp) / "surface-oracle"
        cmd = ["swiftc", "-O", "-o", str(binary)] + [str(p) for p in PRODUCT_SOURCES] + [str(ORACLE_SRC)]
        build = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if build.returncode != 0:
            return None, "the surface oracle did not build:\n" + build.stderr[-2000:]
        got = subprocess.run([str(binary)], capture_output=True, text=True, timeout=120)
        if got.returncode != 0:
            return None, f"the surface oracle exited {got.returncode}: {got.stderr.strip()}"
    rows = []
    for line in got.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            return None, f"the oracle printed a {len(parts)}-column row: {line!r}"
        rows.append({"axis": parts[0], "address": parts[1], "label": parts[2],
                     "state": parts[3], "detail": parts[4]})
    if not rows:
        return None, "the oracle printed nothing"
    for axis in ("destination", "sheet"):
        if not [r for r in rows if r["axis"] == axis]:
            return None, f"the oracle printed no {axis} rows — the oracle is wrong, not the app"
    return rows, None


def classify(rows, bindings, addressless, inventory_surface_ids, covered_surface_ids,
             campaign_mac_surfaces):
    """The whole verdict, as lists of (address, label, detail) per class.

    Pure, so the presence control below can run it over a doctored world and watch each class fire
    without touching the repository.
    """
    shipped = {r["address"]: r for r in rows if r["state"] == "shipped"}
    unshipped = {r["address"]: r for r in rows if r["state"] != "shipped"}

    out = {k: [] for k in ("shipped_unenumerated", "enumerated_uncovered", "bound_to_unknown",
                           "stale_binding", "bound_but_unshipped", "unexplained_addressless",
                           "covered")}

    for address, row in shipped.items():
        bound = bindings.get(address)
        if not bound:
            out["shipped_unenumerated"].append((address, row["label"], row["detail"]))
            continue
        missing = [s for s in bound if s not in inventory_surface_ids]
        if missing:
            out["bound_to_unknown"].append((address, row["label"], ", ".join(missing)))
            continue
        if not any(s in covered_surface_ids for s in bound):
            out["enumerated_uncovered"].append((address, row["label"], ", ".join(bound)))
            continue
        out["covered"].append((address, row["label"], ", ".join(bound)))

    for address, bound in bindings.items():
        if address in unshipped:
            out["bound_but_unshipped"].append(
                (address, unshipped[address]["label"], unshipped[address]["state"]))
        elif address not in shipped:
            out["stale_binding"].append((address, "-", ", ".join(bound)))

    named = {s for bound in bindings.values() for s in bound}
    for sid in sorted(campaign_mac_surfaces):
        if sid not in named and sid not in addressless:
            out["unexplained_addressless"].append((sid, campaign_mac_surfaces[sid], ""))

    return out


def presence_control(rows, bindings, inventory_surface_ids, covered_surface_ids, mac_surfaces):
    """Plant one defect of each class into a COPY of the world and require it to be reported.

    A gate whose classes have never been watched to fire is a gate that reports clean for two
    reasons and can only tell you one of them. Every arm here is a doctored dict — nothing on disk
    is written, and the real verdict is computed separately from the untouched inputs.
    """
    fails = []

    # SHIPPED-UNENUMERATED: an address the app ships that nobody bound.
    doctored = list(rows) + [{"axis": "destination", "address": "destination:__control",
                              "label": "Control", "state": "shipped", "detail": "Running"}]
    got = classify(doctored, bindings, {}, inventory_surface_ids, covered_surface_ids, {})
    if "destination:__control" not in [a for a, _, _ in got["shipped_unenumerated"]]:
        fails.append("a planted shipped-and-unbound destination was not reported")

    # ENUMERATED-UNCOVERED: bound to a real surface that carries no case.
    b2 = dict(bindings)
    b2["destination:__control2"] = ["SURF-CTRL"]
    doctored = list(rows) + [{"axis": "destination", "address": "destination:__control2",
                              "label": "Control2", "state": "shipped", "detail": "Running"}]
    got = classify(doctored, b2, {}, inventory_surface_ids | {"SURF-CTRL"}, covered_surface_ids, {})
    if "destination:__control2" not in [a for a, _, _ in got["enumerated_uncovered"]]:
        fails.append("a planted bound-but-caseless destination was not reported as uncovered")

    # BOUND-TO-UNKNOWN: bound to a surface id the inventory does not hold.
    b3 = dict(bindings)
    b3["destination:__control3"] = ["SURF-NOPE"]
    doctored = list(rows) + [{"axis": "destination", "address": "destination:__control3",
                              "label": "Control3", "state": "shipped", "detail": "Running"}]
    got = classify(doctored, b3, {}, inventory_surface_ids, covered_surface_ids, {})
    if "destination:__control3" not in [a for a, _, _ in got["bound_to_unknown"]]:
        fails.append("a planted binding to a non-existent surface was not reported")

    # STALE-BINDING: a binding for an address the app does not ship.
    b4 = dict(bindings)
    b4["destination:__gone"] = ["SURF-001"]
    got = classify(rows, b4, {}, inventory_surface_ids, covered_surface_ids, {})
    if "destination:__gone" not in [a for a, _, _ in got["stale_binding"]]:
        fails.append("a planted binding to an unshipped address was not reported as stale")

    # BOUND-BUT-UNSHIPPED: a binding onto a sheet kind no board can present.
    owed = [r["address"] for r in rows if r["state"] != "shipped"]
    if not owed:
        fails.append("the oracle reported no unshipped kind, so the bound-but-unshipped arm could "
                     "not be exercised")
    else:
        b5 = dict(bindings)
        b5[owed[0]] = ["SURF-001"]
        got = classify(rows, b5, {}, inventory_surface_ids, covered_surface_ids, {})
        if owed[0] not in [a for a, _, _ in got["bound_but_unshipped"]]:
            fails.append("a planted binding onto an unhosted sheet kind was not reported")

    # UNEXPLAINED-ADDRESSLESS: a Mac surface nothing binds and nothing explains.
    got = classify(rows, bindings, {}, inventory_surface_ids, covered_surface_ids,
                   {"SURF-CTRL4": "a control surface"})
    if "SURF-CTRL4" not in [a for a, _, _ in got["unexplained_addressless"]]:
        fails.append("a planted addressless Mac surface was not reported")

    # And the negative arm: the untouched world must NOT invent any of these six.
    got = classify(rows, bindings, {"SURF-CTRL4": "x"}, inventory_surface_ids,
                   covered_surface_ids, {"SURF-CTRL4": "a control surface"})
    if got["unexplained_addressless"]:
        fails.append("an explained addressless surface was still reported")

    return fails


def seed_reconcile():
    """The other half: nothing the campaign opened with may have left the live set.

    Reports growth per pair and returns the orphans. See the module docstring for why this is a
    subset check rather than an equality one.
    """
    inventory = json.loads((D / "inventory.json").read_text())
    cases = json.loads((D / "cases.json").read_text())
    pairs = [("requirements.in.json", "requirement", inventory.get("requirement", [])),
             ("surfaces.in.json", "surface", inventory.get("surface", [])),
             ("cases.in.json", "case", cases),
             ("components.in.json", "component", inventory.get("component", [])),
             ("flows.in.json", "flow", inventory.get("flow", [])),
             ("defects.in.json", "defect", inventory.get("defect", []))]
    report, orphans = [], []
    for filename, kind, live in pairs:
        path = D / filename
        if not path.exists():
            orphans.append((filename, kind, ["the seed file is missing"]))
            continue
        seed_ids = {row["id"] for row in json.loads(path.read_text())}
        live_ids = {row["id"] for row in live}
        gone = sorted(seed_ids - live_ids)
        report.append((filename, len(seed_ids), len(live_ids), len(live_ids - seed_ids)))
        if gone:
            orphans.append((filename, kind, gone))
    return report, orphans


def main() -> int:
    rows, reason = run_oracle()
    if rows is None:
        print(f"BLOCKED — {reason}")
        return 3

    bindings_doc = json.loads((D / "surface-bindings.json").read_text())
    bindings = {k: list(v) for k, v in bindings_doc["bindings"].items()}
    addressless = bindings_doc.get("addressless", {})

    inventory = json.loads((D / "inventory.json").read_text())
    cases = json.loads((D / "cases.json").read_text())
    surfaces = inventory.get("surface", [])
    inventory_surface_ids = {s["id"] for s in surfaces}
    # A case that names no surface cannot cover one, and it used to leave the reader silently. The
    # count is the honest denominator behind `covered_surface_ids`: "N surfaces are covered" is a
    # claim about the cases that named a surface, and the ones that named none are the population
    # that claim says nothing about.
    covered_surface_ids = set()
    surfaceless_cases = []
    for c in cases:
        sid = c.get("surface")
        if not sid:
            surfaceless_cases.append(str(c.get("id") or "<case with no id>"))
            continue
        covered_surface_ids.add(sid)
    print(f"cases read: {len(cases)}; {len(cases) - len(surfaceless_cases)} name a surface and "
          f"reach {len(covered_surface_ids)} of them; {len(surfaceless_cases)} name none and "
          f"cover nothing here")
    mac_surfaces = {s["id"]: s.get("name") or s.get("title") or ""
                    for s in surfaces if s.get("lane") == MAC_LANE}

    fails = presence_control(rows, bindings, inventory_surface_ids, covered_surface_ids,
                             mac_surfaces)
    if fails:
        print("CONTROL FAILED — no verdict printed, because a count from an instrument that "
              "cannot see the defect is not evidence.")
        for f in fails:
            print(f"  · {f}")
        return 2
    print(f"presence control: all 6 classes watched to fire on planted defects, and the "
          f"explained-addressless negative arm stayed quiet")

    verdict = classify(rows, bindings, addressless, inventory_surface_ids, covered_surface_ids,
                       mac_surfaces)

    shipped = [r for r in rows if r["state"] == "shipped"]
    owed = [r for r in rows if r["state"] != "shipped"]
    print(f"\nthe app declares {len(shipped)} shipped addresses "
          f"({len([r for r in shipped if r['axis'] == 'destination'])} destinations, "
          f"{len([r for r in shipped if r['axis'] == 'sheet'])} sheet kinds) "
          f"and {len(owed)} declared-but-unhosted sheet kinds, compiled from "
          f"{', '.join(p.name for p in PRODUCT_SOURCES)}")
    for r in owed:
        print(f"    not yet hosted, so not required to be enumerated: {r['address']} ({r['state']})")
    print(f"the campaign enumerates {len(inventory_surface_ids)} surfaces, "
          f"{len(mac_surfaces)} of them on the {MAC_LANE} lane")

    red = 0
    titles = [
        ("shipped_unenumerated",
         "SHIPPED AND UNENUMERATED — the app presents it and the campaign has no surface for it",
         "enumerate a surface and write cases; nobody has decided how to test this yet"),
        ("enumerated_uncovered",
         "ENUMERATED AND UNCOVERED — a surface exists and no case cites it",
         "write a case; somebody decided how to test this and did not"),
        ("bound_to_unknown",
         "BOUND TO AN UNKNOWN SURFACE — the binding names a surface the inventory does not hold",
         "fix the binding, or restore the surface"),
        ("stale_binding",
         "STALE BINDING — bound to an address the app no longer ships",
         "retire the binding, and check the surface is not testing something that is gone"),
        ("bound_but_unshipped",
         "BOUND BUT UNSHIPPED — bound to a sheet kind no board can present",
         "retire the binding; a surface for an unpresentable sheet is a paper surface"),
        ("unexplained_addressless",
         "UNEXPLAINED ADDRESSLESS SURFACE — a Mac surface nothing binds and nothing explains",
         "bind it to a product address, or record in `addressless` why it has none"),
    ]
    for key, title, remedy in titles:
        items = verdict[key]
        if not items:
            continue
        red += len(items)
        print(f"\n  {title}")
        print(f"  remedy: {remedy}")
        for address, label, detail in items:
            print(f"    FAIL {address}" + (f"  ({label})" if label and label != "-" else "")
                  + (f"  [{detail}]" if detail else ""))

    print(f"\n  covered: {len(verdict['covered'])} shipped addresses bound to a surface that "
          f"carries at least one case")

    growth, orphans = seed_reconcile()
    print("\nseed files against the live set — a subset check, not an equality one "
          "(see this file's docstring):")
    for filename, seeded, live, added in growth:
        print(f"    {filename:<24} seeded {seeded:>3}   live {live:>3}   "
              f"grown by {added:>3}   orphaned 0")
    for filename, kind, gone in orphans:
        red += len(gone)
        print(f"\n  SEED-ORPHAN — {filename} opened the campaign with rows the live set no longer "
              f"holds. Remedy: restore the row, or record its retirement.")
        for g in gone:
            print(f"    FAIL {g}")

    if red:
        print(f"\n{red} disagreement(s) between the product and the campaign.")
        return 1
    print("\nthe campaign's surface set and the product's agree in every direction.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
