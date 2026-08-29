#!/usr/bin/env python3
"""Arm the declared blind-mutation vocabulary, both ways, and state its recall against the defaults.

## Why this exists

`vacuity-check.py`'s blind pass asks whether any reader appears after the last mutating call in a
test body. Both halves are matched BY NAME, so the pass measures the verb list at least as much as
it measures the suite — and a list that does not fit produces MORE findings, not fewer, which reads
as thoroughness rather than as a misconfigured instrument. That is the failure the upstream script's
own header records, and DEF-055 is this repository's instance of it.

Until 2026-08-29 `campaign.json` declared no `blindVocabulary`, so the pass ran on nine snake_case
mutators and seven snake_case readers over a camelCase Swift corpus. Measured here: the defaults
find 3 mutating call sites in 2282 test bodies where the declared vocabulary finds 481. A pass with
that recall cannot adjudicate anything, and `blind=3` was a statement about 3 of 481 rather than
about the suite. Declaring a vocabulary without measuring what it can see would move the number and
leave the same hole, so the vocabulary and this arm land together.

## The two arms, and why one of them is not enough

**Sensitivity.** A planted test that mutates and never reads must be FOUND. Without this the pass
can be blind to everything and still print a reassuring small number.

**Specificity.** A planted test that mutates and then reads must NOT be found. Without this arm a
detector that flags every mutating body passes the sensitivity arm perfectly while saying nothing:
that is a dead predicate, and it is the shape that produced 32 findings over a tree that was not
the campaign's.

Both plants are identical except for the one line under test, so a failure names the predicate
rather than the fixture.

## Two populations, because they answer different questions

The isolated arm runs each plant alone and asserts the exact triple `examined/mutating/blind`. It
is cheap and it pins the predicate. The corpus arm copies the tree to a temporary directory, plants
the same file inside it, and requires the real counts to move by exactly one — which the isolated
arm cannot show, because the corpus carries suppressors the plant has to survive: the file-scoped
helper exclusion, and the arrow-style/declaration block split.

## It never writes into the working tree

Rule: a gate must not mutate what it is checking. The corpus arm works on `shutil.copytree` output
under `tempfile`, and the copy is removed whether or not the arm passes. Nothing here writes to
`app/`, to `campaign.json`, or to the registry.

## What it does not settle

A moved count proves the pass can see a planted test. It says nothing about PRECISION on the 111
findings the declared vocabulary reports — DEF-055 measured 0 of 3 on the previous population by
reading every finding, and that reading is the only instrument for it. This arm is why the number
is a worklist; it is not a reason to publish the number as a verdict.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
CAMPAIGN = REPO / "planning/test-campaign"
CACHE = Path.home() / ".claude/plugins/cache/fledgeling-plugins/test-campaign"
VENDOR = REPO / "vendor/test-campaign/skills/test-campaign/scripts"

# The two plants, identical but for the one line under test. The `@Test` attribute sits on its own
# line because the instrument's `DECL_RE` anchors `func` to the start of a line — which is how this
# corpus writes swift-testing cases anyway, so the plant matches the population it is planted in.
BLIND_PLANT = """import Testing

@Suite("Arm")
struct ArmPlantTests {
    @Test
    func armBlindMutatesAndNeverReads() async throws {
        let box = ArmBox()
        box.write("one")
    }
}
"""

READING_PLANT = """import Testing

@Suite("Arm")
struct ArmPlantTests {
    @Test
    func armMutatesThenReads() async throws {
        let box = ArmBox()
        box.write("one")
        #expect(box.contents == ["one"])
    }
}
"""


def load_instrument(explicit=None):
    """The newest copy carrying `pass_blind`, vendored first.

    The vendored pin is 0.9.2 and does carry `pass_blind`, so a clone can run this arm. The cache
    is preferred only when it is newer, and which one answered is printed, because a number
    produced by an unnamed version is the claim this repository's own guard refuses.
    """
    if explicit:
        return _import(Path(explicit).expanduser().resolve(), "explicit " + str(explicit))
    cands = [("vendor", VENDOR / "vacuity-check.py")]
    if CACHE.is_dir():
        vers = sorted((d.name for d in CACHE.iterdir() if d.is_dir()),
                      key=lambda v: tuple((int(x) if x.isdigit() else 0) for x in v.split("."))[:3],
                      reverse=True)
        cands = [("cache " + v, CACHE / v / "skills/test-campaign/scripts/vacuity-check.py")
                 for v in vers] + cands
    for origin, path in cands:
        mod, got = _import(path, origin)
        if mod is not None:
            return mod, got
    return None, ""


def _import(path: Path, origin: str):
    if not path.exists():
        return None, ""
    spec = importlib.util.spec_from_file_location("_tc_blind_" + str(abs(hash(origin))), str(path))
    if spec is None or spec.loader is None:
        return None, ""
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception:
        return None, ""
    if hasattr(mod, "pass_blind") and hasattr(mod, "DEFAULT_MUTATORS"):
        return mod, origin
    return None, ""


def counts(vc, root: Path, muts, rds):
    """`examined, mutating, reread, blind`, normalised across two return shapes.

    0.9.2 — the version `vendor/` pins — returns a bare 4-tuple; 0.9.3 and later return a dict
    carrying the same four plus the block split and the verbs it saw. Normalising here is what
    lets this arm run from a clone with no plugin cache, which is the whole point of the pin.
    """
    r = vc.pass_blind(root, tuple(muts), tuple(rds))
    if isinstance(r, dict):
        return r["examined"], r["mutating"], r["reread"], len(r["findings"])
    examined, mutating, reread, findings = r
    return examined, mutating, reread, len(findings)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--instrument", metavar="PATH",
                    help="Run against this copy of vacuity-check.py rather than the newest one "
                         "found. Use it to check that the pinned copy under vendor/ still "
                         "reproduces the arm from a clone.")
    args = ap.parse_args()

    vc, origin = load_instrument(args.instrument)
    if vc is None:
        print("blind arm: NOT RUN — no copy of vacuity-check.py carrying `pass_blind` was found. "
              "A pass that could not run is not a pass that found nothing.")
        return 1

    campaign = json.loads((CAMPAIGN / "campaign.json").read_text())
    vocab = campaign.get("blindVocabulary") or {}
    muts = list(vocab.get("mutators") or ())
    rds = list(vocab.get("readers") or ())
    if not muts or not rds:
        print("blind arm: FAILED — campaign.json declares no blindVocabulary. The pass then runs "
              "on defaults written for another language's idiom, and its recall is unmeasured.")
        return 1

    raw_root = campaign.get("testRoot") or ""
    root = vc.find_root(CAMPAIGN, str(raw_root)) if (raw_root and hasattr(vc, "find_root")) else None
    if root is None:
        root = REPO / str(raw_root) if raw_root else None
    if root is None or not root.exists():
        print("blind arm: NOT RUN — campaign.json testRoot %r does not resolve." % raw_root)
        return 1

    if not args.quiet:
        print("instrument: %s · corpus %s · vocabulary %d mutator(s) %d reader(s) (only=%s)"
              % (origin, root, len(muts), len(rds), bool(vocab.get("only"))))

    failures = []

    # ── recall against the defaults, which is the finding that justified the vocabulary ──
    d_ex, d_mu, _, d_bl = counts(vc, root, vc.DEFAULT_MUTATORS, vc.DEFAULT_READERS)
    f_ex, f_mu, f_rr, f_bl = counts(vc, root, muts, rds)
    print("recall:     defaults find %d mutating call site(s) in %d test bodies; the declared "
          "vocabulary finds %d." % (d_mu, d_ex, f_mu))
    print("            defaults blind=%d · declared examined=%d mutating=%d re-read=%d blind=%d"
          % (d_bl, f_ex, f_mu, f_rr, f_bl))
    if d_mu >= f_mu:
        failures.append("the declared vocabulary finds no more mutating call sites than the "
                        "defaults (%d vs %d), so declaring it bought nothing" % (f_mu, d_mu))

    # ── isolated arm: each plant alone, exact triple ──
    for label, body, want_blind in (("blind plant", BLIND_PLANT, 1),
                                    ("reading plant", READING_PLANT, 0)):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "ArmTests.swift"
            p.write_text(body)
            ex, mu, rr, bl = counts(vc, Path(td), muts, rds)
            ok = (ex, mu, bl) == (1, 1, want_blind)
            print("isolated:   %-14s examined=%d mutating=%d blind=%d — %s"
                  % (label, ex, mu, bl, "ok" if ok else "FAILED"))
            if not ok:
                failures.append("isolated %s expected examined=1 mutating=1 blind=%d, got "
                                "%d/%d/%d" % (label, want_blind, ex, mu, bl))

    # ── corpus arm: the same plants inside a copy of the real tree ──
    with tempfile.TemporaryDirectory() as td:
        copy = Path(td) / root.name
        shutil.copytree(root, copy, symlinks=True)
        base = counts(vc, copy, muts, rds)
        if base != (f_ex, f_mu, f_rr, f_bl):
            failures.append("the copied corpus does not reproduce the real one (%s vs %s), so a "
                            "delta measured on it is a delta on a different tree"
                            % (base, (f_ex, f_mu, f_rr, f_bl)))
        target = copy / "Tests" / "ArmPlantTests.swift"
        target.parent.mkdir(parents=True, exist_ok=True)
        for label, body, d_blind in (("blind plant", BLIND_PLANT, 1),
                                     ("reading plant", READING_PLANT, 0)):
            target.write_text(body)
            ex, mu, rr, bl = counts(vc, copy, muts, rds)
            ok = (ex - base[0], mu - base[1], bl - base[3]) == (1, 1, d_blind)
            print("corpus:     %-14s examined %+d mutating %+d blind %+d — %s"
                  % (label, ex - base[0], mu - base[1], bl - base[3], "ok" if ok else "FAILED"))
            if not ok:
                failures.append("corpus %s expected examined+1 mutating+1 blind+%d, got %+d/%+d/%+d"
                                % (label, d_blind, ex - base[0], mu - base[1], bl - base[3]))
            target.unlink()

    if failures:
        print("blind arm:  %d FAILURE(S), so no recall figure above is evidence:" % len(failures))
        for f in failures:
            print("  · %s" % f)
        return 1
    print("blind arm:  6 of 6 checks as expected — the pass finds a planted blind test, does not "
          "flag a planted reading one, and the declared vocabulary sees %dx the mutating call "
          "sites the defaults do." % (f_mu // max(d_mu, 1)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
