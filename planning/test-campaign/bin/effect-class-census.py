#!/usr/bin/env python3
"""Fail closed on an effect class the census cannot name, and publish the set it can.

## The defect

`campaign.json`'s requirement registry gives each requirement an `effect` class from a CLOSED list
the instrument owns. The list is the census's whole vocabulary: `vacuity-check.py` selects on
`effect in EXTERNAL` and `campaign.py` on `effect in EXTERNAL_EFFECTS`, both by membership. A class
that is not a member fails the test and DROPS OUT — it is not counted, not censused, and not
reported. The requirement then reads as one declaring no effect outside the process, which is
indistinguishable from a requirement that promises nothing observable and therefore owes no witness.

The direction is what makes it worth a gate. A counter built to find claims nothing answers is, for
an unrecognised class, answering "nothing claimed". A typo, a renamed class, or a vocabulary that
moved under the registry all land in the same silent bucket, and each one removes a requirement from
the population anybody has to prove.

`campaign.py check` 0.14.1 blocks on this (`bad_effect_class`, campaign.py:1074). `vacuity-check.py`
0.14.1 does NOT: `pass_unclassed` skips any requirement with a truthy `effect`, and `pass_uncensused`
selects on membership, so REQ-027's `filesystem-read` was invisible to both of its passes while its
`--gate` exit code reported on the other two. This gate closes that half, in the repository, at the
version the repository pins.

## Where the vocabulary comes from, and why it is not written here

A copy of the list in this file would be a twin that drifts. The set is PARSED, with `ast`, out of
the instrument's own source — every copy of it this repository can see — and a disagreement between
two copies is itself a finding, because a repository pinned to one vocabulary while its runs use
another is DEF-055's shape one level up. Measured 2026-08-29: `vendor/` 0.9.2 and the machine cache
0.14.1 carry identical tuples in both `campaign.py` and `vacuity-check.py`, 4 of 4 copies agreeing.

## The narrowing this gate polices

The list has no class for a filesystem READ. REQ-027 is a real read — the router serves a document
route that reads a package directory the upstream declared — and the vocabulary cannot spell it.
A requirement in that position declares `effect: "none"` so the closed list stays closed, and
records the class the list cannot hold in `effectUnrepresentable`. That is a narrowing, not a
statement that the product touches nothing, and left alone it would be the very silence this gate
exists for: `none` leaves the external-effect census, so nothing would check that the read has a
provider at all.

So a row carrying `effectUnrepresentable` owes MORE than an ordinary one, not less:

  1. `effect` must be exactly `"none"` — the narrowing is explicit rather than implied;
  2. the named class must be OUTSIDE the instrument's set, since a class the list holds should
     simply be declared;
  3. `provider` must be present AND RESOLVE against `campaign.json`'s `sourceRoot`, checked by
     importing `vacuity-check.py`'s own `resolve_provider` rather than by a second implementation.

Rule 3 is the reason the reach is stated: this proves a symbol or path exists in production source,
which is the census's floor and not a witness. What ships no witness is said so, here and on the row.

## The control

`--control` runs both arms on parsed dictionaries and touches no file. An invented class must be
found; the registry as it stands must not be. A gate whose blindness and whose clean run print the
same thing has measured nothing, so a failed arm exits 2 and prints no count.
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import json
import sys
from pathlib import Path

# The verdict below is UTF-8, and the console's codepage does not get a vote in it: on a
# non-UTF-8 terminal an unencodable rule character would raise UnicodeEncodeError and this
# gate would exit on its terminal rather than on its findings.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parents[3]
CAMPAIGN = REPO / "planning/test-campaign"
VENDOR = REPO / "vendor/test-campaign/skills/test-campaign/scripts"
CACHE = Path.home() / ".claude/plugins/cache/fledgeling-plugins/test-campaign"


def instrument_copies() -> list:
    """Every copy of the instrument this repository can see, vendored first.

    The vendored pin is what a clone gets and is therefore the authority; the machine cache is
    what the campaign's recorded runs actually executed. Both are read so the two can be compared.
    """
    found = []
    for name in ("campaign.py", "vacuity-check.py"):
        p = VENDOR / name
        if p.exists():
            found.append(("vendor", p))
    if CACHE.is_dir():
        for ver in sorted(d.name for d in CACHE.iterdir() if d.is_dir()):
            for name in ("campaign.py", "vacuity-check.py"):
                p = CACHE / ver / "skills/test-campaign/scripts" / name
                if p.exists():
                    found.append(("cache " + ver, p))
    return found


def parse_classes(path: Path):
    """`EFFECT_CLASSES` as the interpreter would build it, not as a regex would read it.

    A regex over source is the reader this repository files defects about: it cannot tell a
    definition from a mention in a docstring, and both appear in these files.
    """
    tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        for t in node.targets:
            if isinstance(t, ast.Name) and t.id == "EFFECT_CLASSES":
                try:
                    return tuple(ast.literal_eval(node.value))
                except (ValueError, SyntaxError):
                    return None
    return None


RESOLVER_API = ("resolve_provider", "SourceIndex", "find_root")


def load_resolver():
    """`resolve_provider`, `SourceIndex` and `find_root` from the instrument, by path import.

    Imported rather than reimplemented: a second resolver would answer a slightly different
    question, and the difference would read as a product finding.

    THE PINNED COPY CANNOT DO THIS, measured 2026-08-29. `vendor/` is 0.9.2, whose
    `vacuity-check.py` declares ten functions and none of the three named above — provider
    resolution arrived in 0.9.5, three releases after the pin. So the vendored copy is tried
    first and the newest cache copy carrying the whole API is the fallback, with which one
    answered printed on every run. A clone with no cache gets `NOT CHECKED` and says so, which
    is the honest reading of a pin that predates the check.
    """
    for origin, path in [("vendor", VENDOR / "vacuity-check.py")] + _cache_vacuity_newest_first():
        if not path.exists():
            continue
        spec = importlib.util.spec_from_file_location("_tc_vacuity_" + origin.replace(" ", "_"),
                                                      str(path))
        if spec is None or spec.loader is None:
            continue
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
        except Exception:
            continue
        if all(hasattr(mod, a) for a in RESOLVER_API):
            return mod, origin
    return None, ""


def _cache_vacuity_newest_first():
    if not CACHE.is_dir():
        return []
    out = []
    for ver in sorted((d.name for d in CACHE.iterdir() if d.is_dir()), key=_verkey, reverse=True):
        out.append(("cache " + ver, CACHE / ver / "skills/test-campaign/scripts/vacuity-check.py"))
    return out


def _verkey(v):
    parts = []
    for p in str(v).split("."):
        parts.append(int(p) if p.isdigit() else 0)
    return tuple(parts + [0, 0, 0])[:3]


def examine(reqs, recognised, resolver=None, index=None):
    """Every finding the registry carries, given a recognised set. Pure — no I/O, no mutation."""
    findings = []
    declared = extended = 0
    for r in reqs:
        rid = r.get("id", "<no id>")
        eff = r.get("effect")
        if eff:
            declared += 1
            if eff not in recognised:
                findings.append(
                    "%s declares effect %r, which the census does not recognise — an "
                    "unrecognised class drops out of the count rather than failing, so it "
                    "reads as no effect at all. One of: %s"
                    % (rid, eff, ", ".join(recognised)))
        unrep = r.get("effectUnrepresentable")
        if not unrep:
            continue
        extended += 1
        if unrep in recognised:
            findings.append(
                "%s records effectUnrepresentable %r, which the census DOES recognise — "
                "declare it as the effect instead of narrowing to none" % (rid, unrep))
        if eff != "none":
            findings.append(
                "%s records effectUnrepresentable %r and declares effect %r — a narrowing is "
                "spelled `none`, so the row says outright that the census counts nothing here"
                % (rid, unrep, eff))
        prov = str(r.get("provider") or "").strip()
        if not prov:
            findings.append(
                "%s records effectUnrepresentable %r and names no provider — the row left the "
                "external-effect census and nothing replaced the obligation" % (rid, unrep))
        elif resolver is not None and index is not None:
            ok, why = resolver.resolve_provider(prov, index)
            if not ok:
                findings.append(
                    "%s records effectUnrepresentable %r and its provider resolves to nothing "
                    "— %s" % (rid, unrep, why))
    return findings, declared, extended


def control(recognised, resolver=None, index=None) -> int:
    """One arm per predicate, in memory, each reddening ALONE.

    A single arm proving "the gate fires on something" is the shape that lets four other
    predicates rot into no-ops behind it. So every rule this gate enforces gets its own planted
    row, and every planted row differs from the clean one in exactly the thing it is testing.
    """
    good = recognised[0]
    arms = [
        ("an unrecognised effect class",
         [{"id": "CTRL-001", "effect": "a-class-nobody-declared"}], 1),
        ("a narrowing naming a class the census DOES hold",
         [{"id": "CTRL-003", "effect": "none", "effectUnrepresentable": good,
           "provider": "planning/test-campaign/bin/effect-class-census.py"}], 1),
        ("a narrowing that does not spell itself `none`",
         [{"id": "CTRL-004", "effect": good, "effectUnrepresentable": "a-class-nobody-declared",
           "provider": "planning/test-campaign/bin/effect-class-census.py"}], 1),
        ("a narrowing with no provider",
         [{"id": "CTRL-005", "effect": "none",
           "effectUnrepresentable": "a-class-nobody-declared"}], 1),
        ("a clean row",
         [{"id": "CTRL-002", "effect": good}], 0),
        ("a clean narrowing",
         [{"id": "CTRL-006", "effect": "none", "effectUnrepresentable": "a-class-nobody-declared",
           "provider": "planning/test-campaign/bin/effect-class-census.py"}], 0),
    ]
    if resolver is not None and index is not None:
        arms.insert(4, ("a narrowing whose provider resolves to nothing",
                        [{"id": "CTRL-007", "effect": "none",
                          "effectUnrepresentable": "a-class-nobody-declared",
                          "provider": "no/such/file/anywhere.swift"}], 1))
    else:
        print("control: provider-resolution arm NOT RUN — no resolver. A pass that could not "
              "run is not a pass that found nothing.")
    bad = 0
    for label, rows, want in arms:
        got, _, _ = examine(rows, recognised, resolver, index)
        mark = "ok" if len(got) == want else "FAILED"
        if len(got) != want:
            bad += 1
        print("control: %-6s %-52s expected %d finding(s), got %d" % (mark, label, want, len(got)))
    if bad:
        print("control: %d arm(s) FAILED. A count from an instrument that cannot see the defect "
              "is not evidence, so no census figure is printed." % bad)
        return 2
    print("control: %d of %d arms as expected." % (len(arms), len(arms)))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--control", action="store_true",
                    help="Run the two-way presence control and exit.")
    ap.add_argument("--quiet", action="store_true", help="Print only findings and the verdict.")
    args = ap.parse_args()

    copies = instrument_copies()
    if not copies:
        print("effect-class census: NOT RUN — no copy of the instrument found under "
              "%s and no machine cache. A vocabulary nobody could read is not an empty "
              "vocabulary." % VENDOR)
        return 1
    sets = {}
    for origin, path in copies:
        cls = parse_classes(path)
        if cls is None:
            print("effect-class census: NOT RUN — %s (%s) declares no EFFECT_CLASSES this "
                  "parser could read." % (path, origin))
            return 1
        sets.setdefault(cls, []).append("%s %s" % (origin, path.name))

    recognised = sorted(sets, key=lambda c: len(sets[c]), reverse=True)[0]
    divergence = []
    if len(sets) > 1:
        for cls, where in sets.items():
            divergence.append("%s: %s" % (", ".join(where), ", ".join(cls)))

    campaign = json.loads((CAMPAIGN / "campaign.json").read_text(encoding="utf-8"))
    inv = json.loads((CAMPAIGN / "inventory.json").read_text(encoding="utf-8"))
    reqs = inv.get("requirement", [])

    if not args.quiet:
        print("recognised: %s" % ", ".join(recognised))
        origins = sorted({v[0] for v in copies}, key=lambda o: (o != "vendor", o))
        print("  agreed by %d copy/copies of the instrument across %d origin(s): %s"
              % (len(copies), len(origins), ", ".join(origins)))

    resolver, resolver_origin = load_resolver()
    index = None
    root_note = ""
    if resolver is not None:
        raw = campaign.get("sourceRoot") or ""
        root = resolver.find_root(CAMPAIGN, str(raw)) if raw else None
        if root is not None:
            index = resolver.SourceIndex(root, "campaign.json sourceRoot")
            root_note = "%s (%d production file(s))" % (root, len(index.production))
        else:
            root_note = "NOT RESOLVED — campaign.json sourceRoot %r does not exist" % raw
        root_note += " · resolver from %s" % resolver_origin
    else:
        root_note = ("NOT CHECKED — no copy of the instrument carries %s; the pin at %s is "
                     "0.9.2, three releases before provider resolution"
                     % (", ".join(RESOLVER_API), VENDOR))

    if args.control:
        return control(recognised, resolver, index)

    findings, declared, extended = examine(reqs, recognised, resolver, index)
    findings.extend("two copies of the instrument disagree about the vocabulary — %s" % d
                    for d in divergence)

    if not reqs:
        print("effect-class census: NOT RUN — the registry holds no requirements, so a clean "
              "result is a statement about nothing.")
        return 1

    print("examined:   %d requirement(s), %d declaring an effect, %d narrowed with "
          "effectUnrepresentable" % (len(reqs), declared, extended))
    if extended:
        print("  providers resolved against %s" % (root_note or "NOT CHECKED — no resolver"))
    print("findings:   %d" % len(findings))
    for line in findings:
        print("  · %s" % line)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
