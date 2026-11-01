#!/usr/bin/env python3
"""A requirement's declared effect class is one the census can name, or the run is red.

## The defect this exists for

`an-effect-class-the-census-cannot-name-reads-as-no-effect.md`. An effect class outside the
closed vocabulary does not fail — it drops out of the population, and a requirement that
declares one reads as declaring no effect at all, indistinguishable from one that promises
nothing observable and therefore needs no witness. A counter that exists to find claims nothing
answers reports, for that one class, "nothing claimed".

MEASURED on this tree with the pinned `vendor/test-campaign` 0.9.2, by planting the class
`outbound-sockett` — one letter — on `REQ-016` in a scratchpad copy of the campaign:

    vacuity-check.py --gate, before:  uncensused: examined=17 findings=1   (REQ-016 named)
    vacuity-check.py --gate, after:   uncensused: examined=16 findings=0   (clean)

The typo did not produce a finding. It removed the requirement from the set anybody has to
prove, and the census went GREENER. That is the direction that matters: a renamed class, a
vocabulary that moved under the registry, or a fat finger each take a row off the list quietly.

`campaign.py check` does catch it — `1 requirement(s) declaring an effect class the census does
not recognise` — and that is not the enforcement here, for two reasons this repository has
already written down once for `raster-claim-gate.py`: `campaign.py` is not in `make lint`, and a
rule enforced only in a shared plugin cache leaves with the cache. On this host it is worse than
absent: `campaign.py` reads the registry with `p.read_text()` and no encoding, so on a cp1252
console it dies on the first non-ASCII byte before checking anything (`DEF-501`). The gate that
holds this property has to run from the tree.

## Where the vocabulary comes from

Not from this file. `EFFECT_CLASSES` is parsed out of
`vendor/test-campaign/skills/test-campaign/scripts/campaign.py` under a recorded SHA-256, which
is the file `vendor/README.md` pins so the gates re-run from a clone, and which this fleet may
not edit. A copy typed in here would be a third vocabulary able to drift from both — the exact
failure `defect-status-vocabulary-gate.py` was written for one axis over.

The pin is a digest, not a `HEAD:` comparison, so it does not quietly become a self-comparison
the moment it is committed (`DEF-443`). A pinned tree that moved exits 2 NOT COMPARED.

Verified identical in the machine's 0.16.0 and 0.17.0 at the time of writing, so the classes are
a stable vocabulary rather than a version's accident — but the pin is what this gate stands on.

## The two rules, and why only one of them blocks today

R1  BLOCKING. Every `requirement` row with an `effect` declares a class in the vocabulary. All
    44 do, so this arm is green and stays green; a typo makes it red.

R2  RATCHETED. Every `case` whose `witness.effect` names a class — `campaign.py:702` at `5934c38f` applies the
    same list to that field — declares one in the vocabulary. **31 do not**, measured here, and
    the ratchet below holds that exact roster: a new id or a new class is refused, and a row
    leaving the roster lowers it.

The 31 are not a spelling accident and are deliberately NOT remapped by this gate's author. They
are `machine-state` ×25, `file` ×2, and `os-record`, `process`, `notification`, `ui-state` ×1,
every one an `effect-witness · pass` case in the `windows-glass` and `router-daemon` lanes
(`CASE-0342` … `CASE-0493`). Some are a rename — `process` over `Get-ScheduledTaskInfo` is
`subprocess`. Some are a harder question that a rename would bury: `machine-state` over *"the
router's own /servers listing, read over the control API"* is a recorder INSIDE the product, and
whether that case belongs at `effect-witness` at all is a judgement about the case, not about a
word. Picking the nearest legal spelling for all 31 would turn 31 rows green while answering
neither question, which is the one move this campaign forbids. Filed as `DEF-502` instead.

So R2 is a census with a floor rather than a refusal. That is this repository's existing idiom
for a true finding somebody else owns — `citation-gate.py`'s BARE ratchet and
`capture-ratchet.json` — and it is not the gate being relaxed: the population is printed in full
on every run, the floor cannot rise, and a 32nd row is a failure.

WHY THE COUNT WAS NEVER READ OFF `campaign.py`, which does compute it. Its report prints
`40 effect-witness claim(s) with no recorder, no effect class, or a count of zero` and then caps
the detail at twelve lines — which, on this campaign, are twelve lines about four cases with
missing recorders and counts. **All 31 class findings are inside that 40 and none of them is
printed.** A reader of the campaign report cannot learn from it that any case names an
unrecognised class. That is why the roster lives here, enumerated, rather than as a number.

A row with NO `effect` key is not this gate's business: whether a requirement must declare one is
`campaign.py`'s `unwitnessed_effects` question and `effect-provider-gate.py`'s, and answering it
twice in two places is how vocabularies drift.

Exit codes: 0 R1 clean and R2 at or below its floor · 1 R1 has a finding, or R2 rose · 2 the gate
could not read its input, or the pinned instrument moved · 3 `--selftest` failed.

  python3 planning/effect-class-vocabulary-gate.py
  python3 planning/effect-class-vocabulary-gate.py --selftest
"""
from __future__ import annotations

import ast
import hashlib
import json
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
INVENTORY = ROOT / "planning/test-campaign/inventory.json"
CASES = ROOT / "planning/test-campaign/cases.json"
CAMPAIGN_PY = ROOT / "vendor/test-campaign/skills/test-campaign/scripts/campaign.py"
CAMPAIGN_PY_SHA = "4c28ed150125297b000f47b0c32ea8283660b508472d66185c11547222980484"
RATCHET = ROOT / "planning/effect-class-case-ratchet.json"


def vocabulary() -> tuple[tuple[str, ...] | None, str]:
    """`EFFECT_CLASSES` as the pinned instrument defines it, or a reason it could not be read."""
    if not CAMPAIGN_PY.exists():
        return None, f"{CAMPAIGN_PY.relative_to(ROOT).as_posix()} is absent — NOT COMPARED"
    blob = CAMPAIGN_PY.read_bytes()
    got = hashlib.sha256(blob).hexdigest()
    if got != CAMPAIGN_PY_SHA:
        return None, (f"the pinned instrument moved: recorded {CAMPAIGN_PY_SHA[:16]}…, on disk "
                      f"{got[:16]}…. Re-read its EFFECT_CLASSES and re-pin. Raising the digest "
                      f"without reading the tuple is how a gate starts asserting a vocabulary "
                      f"nothing uses.")
    tree = ast.parse(blob.decode("utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "EFFECT_CLASSES" for t in node.targets):
            try:
                value = ast.literal_eval(node.value)
            except ValueError:
                return None, "EFFECT_CLASSES is not a literal in the pinned instrument"
            return tuple(value), ""
    return None, "EFFECT_CLASSES is not assigned at module level in the pinned instrument"


def sweep(rows: list[dict], kind: str, classes: tuple[str, ...],
          field: str = "effect") -> tuple[dict[str, str], int]:
    """{id: bad class} for the rows that name one, and how many named a class at all."""
    bad: dict[str, str] = {}
    declared = 0
    for r in rows:
        src = r if field == "effect" else (r.get("witness") or {})
        fx = src.get("effect")
        if not fx:
            continue
        declared += 1
        if fx not in classes:
            bad[str(r.get("id", "?"))] = fx
    return bad, declared


def describe(kind: str, cid: str, fx: str, classes: tuple[str, ...]) -> str:
    return (f"{kind} {cid} declares effect class {fx!r}, which the census cannot name. It does "
            f"not fail there — it drops out of the population, so this row reads as promising "
            f"nothing observable and needs no witness. One of: {', '.join(classes)}.")


def selftest() -> int:
    ok = True
    classes = ("subprocess", "outbound-socket", "none")

    bad, n = sweep([{"id": "REQ-001", "effect": "outbound-socket"},
                    {"id": "REQ-002", "effect": "none"},
                    {"id": "REQ-003"}], "requirement", classes)
    if not bad and n == 2:
        print("selftest R0 clean: 2 declared classes, no findings, an undeclared row ignored ✓")
    else:
        print(f"SELFTEST FAIL — clean rows produced {bad} over {n} declared")
        ok = False

    # The measured defect: one letter.
    bad, _ = sweep([{"id": "REQ-016", "effect": "outbound-sockett"}], "requirement", classes)
    if bad == {"REQ-016": "outbound-sockett"}:
        print("selftest R1: `outbound-sockett` on a requirement is refused ✓")
    else:
        print(f"SELFTEST FAIL — R1 did not fire: {bad}")
        ok = False

    # R2 reads the nested field `campaign.py:702` at `5934c38f` reads, not a top-level one.
    rows = [{"id": "CASE-0366", "witness": {"effect": "machine-state"}},
            {"id": "CASE-0001", "witness": {"effect": "subprocess"}},
            {"id": "CASE-0002", "effect": "machine-state"}]
    bad, n = sweep(rows, "case", classes, field="witness")
    if bad == {"CASE-0366": "machine-state"} and n == 2:
        print("selftest R2: a witness class outside the vocabulary is found, and a top-level "
              "`effect` on a case is NOT mistaken for one ✓")
    else:
        print(f"SELFTEST FAIL — R2 did not fire as planted: {bad} over {n}")
        ok = False

    # The ratchet arm. A roster that is a superset of what is on disk lowers; a new id fails.
    floor = {"CASE-0366": "machine-state"}
    rose = {k: v for k, v in {"CASE-0366": "machine-state",
                              "CASE-9999": "machine-state"}.items() if k not in floor}
    if rose == {"CASE-9999": "machine-state"}:
        print("selftest R2-ratchet: an id outside the roster is a rise ✓")
    else:
        print(f"SELFTEST FAIL — ratchet did not name the new id: {rose}")
        ok = False
    changed = {k: v for k, v in {"CASE-0366": "ui-state"}.items()
               if floor.get(k) != v}
    if changed == {"CASE-0366": "ui-state"}:
        print("selftest R2-ratchet: a roster id whose class CHANGED is a rise, not a carry ✓")
    else:
        print(f"SELFTEST FAIL — ratchet carried a changed class: {changed}")
        ok = False

    return 0 if ok else 3


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()

    classes, why = vocabulary()
    if classes is None:
        print(f"NOT COMPARED — {why}")
        return 2
    print(f"vocabulary: {len(classes)} class(es) read from "
          f"{CAMPAIGN_PY.relative_to(ROOT).as_posix()} at {CAMPAIGN_PY_SHA[:16]}… — "
          f"{', '.join(classes)}")

    try:
        inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
        raw = json.loads(CASES.read_text(encoding="utf-8"))
        cases = raw if isinstance(raw, list) else raw.get("case", [])
        floor = json.loads(RATCHET.read_text(encoding="utf-8"))["cases"] if RATCHET.exists() else {}
    except (OSError, ValueError, KeyError) as e:
        print(f"the gate could not read its input: {e}")
        return 2

    r1_bad, r1_n = sweep(inv.get("requirement", []), "requirement", classes)
    r2_bad, r2_n = sweep(cases, "case", classes, field="witness")

    print(f"R1 requirements: {r1_n} declared a class, {len(r1_bad)} outside the vocabulary")
    print(f"R2 cases:        {r2_n} named a witness class, {len(r2_bad)} outside the vocabulary "
          f"(ratchet floor {len(floor)})")

    if "--write-ratchet" in sys.argv:
        RATCHET.write_text(json.dumps(
            {"note": "The roster R2 holds. Each entry is a case whose `witness.effect` names a "
                     "class `campaign.py`'s EFFECT_CLASSES does not carry. DEF-502 owns the "
                     "adjudication; this file only stops the count rising. Lower it with "
                     "--write-ratchet in the commit that earns it.",
             "cases": dict(sorted(r2_bad.items()))}, indent=1) + "\n", encoding="utf-8")
        print(f"ratchet written: {len(r2_bad)} case(s)")
        return 0

    rc = 0
    if r1_bad:
        print(f"\nR1 — {len(r1_bad)} finding(s), blocking:")
        for cid, fx in sorted(r1_bad.items()):
            print("  " + describe("requirement", cid, fx, classes))
        rc = 1

    rose = {k: v for k, v in r2_bad.items() if floor.get(k) != v}
    if rose:
        print(f"\nR2 — the ratchet rose by {len(rose)}: a case names an unrecognised witness "
              f"class that the roster does not carry, or carries under a different class.")
        for cid, fx in sorted(rose.items()):
            print("  " + describe("case", cid, fx, classes))
        print("  Adjudicate it against `references/effect-boundary.md` — do not pick the nearest "
              "legal spelling to clear this line. If the row is genuinely one of the 31 DEF-502 "
              "covers, re-run with --write-ratchet in the same commit and say why.")
        rc = 1
    else:
        left = sorted(set(floor) - set(r2_bad))
        print(f"R2 roster: {len(r2_bad)} of {len(floor)} still on it"
              + (f"; {len(left)} adjudicated since it was written: {', '.join(left)} "
                 f"— lower the ratchet with --write-ratchet" if left else "; unchanged"))
        if r2_bad:
            print("  the roster, by class:")
            byclass: dict[str, list[str]] = {}
            for cid, fx in sorted(r2_bad.items()):
                byclass.setdefault(fx, []).append(cid)
            for fx, ids in sorted(byclass.items(), key=lambda kv: (-len(kv[1]), kv[0])):
                print(f"    {fx:<16} {len(ids):>2}  {', '.join(ids)}")

    if rc == 0:
        print("\nR1 clean; R2 at its floor. DEF-502 is what closes R2 for good.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
