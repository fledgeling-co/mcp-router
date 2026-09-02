#!/usr/bin/env python3
"""Refuse a defect row whose status the reckoning cannot partition.

## The defect this exists for

`reckon` classes a defect by reading its `status`. Four tuples in `reckon.py` are a partition
over the words it has a rule for, and a word outside all four is NOT resolved by a default: it
lands `broken`, because guessing done is the error that cannot be recovered from. That
fail-closed direction is right and this gate does not touch it.

What this gate is for is the drift that keeps putting rows there. Measured twice now:

  * 2026-08-26, `defect-vocabulary-blocks-the-reckoning-gate.md`. The register used twelve words
    for a state, the reckoning classified three, and the nine it could not read covered THIRTY
    rows. The gate exited 4 on every run for long enough that its redness stopped carrying
    information.
  * 2026-08-29, `a-status-word-nobody-taught-the-gate-lands-pessimistic.md`. The remap that
    closed the above HELD — every other row still leads with a verb the tool classifies — and
    two new words had been minted since: `DEF-011` at `partially-fixed - in-campaign` and
    `DEF-048` at `superseded - by-DEF-055`. Both were placed by the default rather than by
    anything the register said.

So the reconciliation worked twice and neither time became a property. A row placed by a default
reads exactly like a row placed by a measurement, and both of those rows were ones where somebody
already knew more than the class said. This gate is the property: a word the reckoning cannot
partition is refused WHERE IT IS WRITTEN rather than absorbed at reckoning time.

## What "cannot partition" means precisely, because the tool's rule is not the obvious one

`reckon.py` reads a status in three steps, and only the first two are what a reader expects:

  1. `state_of` splits on `:` and keeps the left side, so `blocked: no credential` is `blocked`.
  2. `defect_status_parts` splits the remainder on the compound separators `.  |  ,  ;` and
     returns BOTH the leading token and the whole string.
  3. The classifier then compares **the leading token** against the fixed and open sets, and
     **the whole string** against the partial, waived and not-owing sets.

Step 3 is the trap and it is why this gate models the rule rather than the word list. `fixed -
in-campaign` classifies, because `fixed` leads and the fixed branch reads the lead. `superseded -
by-DEF-055` does NOT, because `superseded` is a not-owing word and that branch reads the whole
string, which is not `superseded`. The two rows this gate was written for were both minted in
good faith by somebody who had seen `fixed - in-campaign` pass.

A gate that checked only "is the leading token a word reckon knows" would have said yes to both
and reddened for neither. That is the shape this repository keeps recording as an instrument that
cannot fail, so the rule is modelled in full and the compound arm of `--selftest` is the proof.

## Where the vocabulary comes from, and how it is kept from becoming a third one

The five tuples below are copied from `reckon.py`, which is the drift this gate exists to stop
arriving through its own back door. So they are not the authority: `--agree` is. It imports the
`reckon.py` that would actually run, off `RECKON_PY` or the plugin cache, and compares tuple for
tuple. Drift between this file and the tool is a finding.

`--agree` is a SEPARATE arm and not part of the blocking run, because the plugin cache is a
machine's and not a repository's: a gate whose verdict depends on what is installed on the host
is a gate that reds for the wrong reason on a clean checkout. When the copy cannot be found it
says NOT COMPARED and exits 2, because a comparison that did not happen is not a comparison that
agreed - the standing rule this repository already applies to `registry-drop-gate`.

## What it reads

`planning/test-campaign/inventory.json`'s `defect` array is the population that matters, because
`reckon.read_campaign` reads its defects from there and from nowhere else. Every
`planning/test-campaign/defects*.json` is read too - those are the hand-edited sources that feed
the inventory, and catching a word in the source is catching it one edit earlier than catching it
in the file the tool reads.

## What it does NOT do, stated rather than implied

It has no opinion on whether a status is TRUE. `fixed` on a defect nobody re-measured passes this
gate and is `reckon`'s own `FIX_UNMEASURED_QUALIFIERS` problem, not this one. It has no opinion on
case statuses, which are a different vocabulary with a different partition. And it cannot stop a
word being minted in prose - only in the `status` field of a registry row.

Exit codes: 0 every row classifies - 1 a row does not - 2 the gate could not run, or `--agree`
found no reckon to compare against - 3 `--selftest` failed.
"""
import io
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN = ROOT / "planning" / "test-campaign"

# --------------------------------------------------------------------------
# reckon's vocabulary, mirrored. `--agree` is what keeps this honest.
# --------------------------------------------------------------------------
DEFECT_FIXED = ("fixed", "resolved", "closed", "done", "verified", "answered")
DEFECT_OPEN = ("open", "new", "confirmed", "reopened", "regressed", "in progress",
               "recorded", "standing")
DEFECT_WAIVED = ("wontfix", "won't fix", "will not fix", "deferred", "declined",
                 "duplicate", "n/a", "not a bug")
DEFECT_NOT_OWING = ("by design", "by-design", "invalid", "obsolete", "superseded",
                    "cannot reproduce", "cannot-reproduce", "not-a-defect",
                    "not a defect", "vacuous")
DEFECT_PARTIAL = ("partially-fixed", "partially fixed", "part-fixed")

# Which class each branch produces, for the report. A reader who is told a word is legal should
# be told what it will be counted as, or the gate has moved the guess rather than removed it.
CLASS_OF = {}
for _w in DEFECT_FIXED:
    CLASS_OF[_w] = "verified-done"
for _w in DEFECT_OPEN:
    CLASS_OF[_w] = "broken"
for _w in DEFECT_PARTIAL:
    CLASS_OF[_w] = "broken"
for _w in DEFECT_WAIVED:
    CLASS_OF[_w] = "waived"
for _w in DEFECT_NOT_OWING:
    CLASS_OF[_w] = "waived"

LEAD_READ = set(DEFECT_FIXED) | set(DEFECT_OPEN)
WHOLE_READ = set(DEFECT_PARTIAL) | set(DEFECT_WAIVED) | set(DEFECT_NOT_OWING)

SEPARATORS = re.compile(r"\s*[·|,;]\s*")


def classify(raw):
    """Return (ok, class_or_None, lead, whole), modelling reckon.py's own three steps."""
    if raw is None or not str(raw).strip():
        return False, None, "", ""
    whole = str(raw).split(":", 1)[0].strip().lower()
    lead = SEPARATORS.split(whole)[0].strip() if whole else ""
    if lead in LEAD_READ:
        return True, CLASS_OF[lead], lead, whole
    if whole in WHOLE_READ:
        return True, CLASS_OF[whole], lead, whole
    return False, None, lead, whole


# --------------------------------------------------------------------------
# The population
# --------------------------------------------------------------------------
def _rows(blob):
    if isinstance(blob, dict):
        for key in ("defect", "defects", "rows", "items"):
            if isinstance(blob.get(key), list):
                return blob[key]
        return []
    return blob if isinstance(blob, list) else []


def sources():
    """The file reckon reads, then every hand-edited source that feeds it."""
    found = []
    inv = CAMPAIGN / "inventory.json"
    if inv.exists():
        found.append(inv)
    for path in sorted(CAMPAIGN.glob("defects*.json")):
        found.append(path)
    return found


def read(path):
    try:
        return _rows(json.load(io.open(path, encoding="utf-8-sig")))
    except Exception as exc:  # noqa: BLE001 - the message is the verdict
        print("  UNREADABLE %s - %s" % (path.relative_to(ROOT), exc))
        return None


def run(paths=None):
    paths = paths or sources()
    if not paths:
        print("no defect registry found under %s" % CAMPAIGN.relative_to(ROOT))
        print("exit: 2  (nothing was read, so nothing was checked)")
        return 2

    examined = 0
    findings = []
    unreadable = 0
    per_word = {}

    for path in paths:
        rows = read(path)
        if rows is None:
            unreadable += 1
            continue
        for row in rows:
            if not isinstance(row, dict) or "id" not in row:
                continue
            examined += 1
            ok, cls, lead, whole = classify(row.get("status"))
            key = whole or "(no status)"
            entry = per_word.setdefault(key, {"n": 0, "class": cls, "ok": ok})
            entry["n"] += 1
            if not ok:
                findings.append((str(path.relative_to(ROOT)).replace("\\", "/"),
                                 row.get("id"), row.get("status"), lead))

    print("defect status vocabulary - the words reckon can partition, checked where they are written")
    print("  read %d file(s), %d defect row(s)%s"
          % (len(paths) - unreadable, examined,
             ", %d unreadable" % unreadable if unreadable else ""))
    print()
    print("  HOW EACH WORD IN USE WILL BE COUNTED")
    for word in sorted(per_word):
        e = per_word[word]
        print("    %-42s %3d  %s" % (word, e["n"],
                                     e["class"] if e["ok"] else "NOT CLASSIFIED - fail-closed to broken"))

    if unreadable:
        print()
        print("exit: 2  (%d file(s) could not be read; a file not read is not a file that passed)" % unreadable)
        return 2

    print()
    cross = cross_file(paths)

    if findings:
        print("  %d row(s) carry a status the reckoning cannot partition:" % len(findings))
        for rel, rid, status, lead in findings:
            print("    %s  %s  status %r" % (rel, rid, status))
            if lead in LEAD_READ:
                print("        its leading token %r IS a word reckon knows, but that word is read as a"
                      % lead)
                print("        WHOLE status rather than as a lead, so the compound does not reach it.")
                print("        Write it bare and put the qualifier in `resolution`.")
            elif lead in WHOLE_READ:
                print("        %r is read as a whole status, not as a lead. Write it bare and put the"
                      % lead)
                print("        qualifier in `resolution`.")
            elif not str(status or "").strip():
                print("        the row carries no status at all; reckon reads that as a repair nobody")
                print("        recorded, which is not a repair it can read.")
            else:
                print("        no branch of reckon's partition holds this word.")
        print()
        print("  the words that classify, printed once rather than per row:")
        print("    read as a lead, so a compound like `open - measured` reaches them:")
        print("      %s" % " / ".join(sorted(LEAD_READ)))
        print("    read as a whole status, so they must stand alone:")
        print("      %s" % " / ".join(sorted(WHOLE_READ)))
        print()
        print("  A refused word is not a lost distinction. Both rows this gate was written for kept")
        print("  theirs by moving it into `resolution`, which is a field a reader reads and the")
        print("  classifier does not.")
        print()
        report_cross_file(cross)
        print()
        print("exit: 1")
        return 1

    print("  every status classifies. No row in the register is placed by this tool's default.")
    print()
    if report_cross_file(cross):
        print()
        print("exit: 1  (every status classifies; the registers do not agree about what they say)")
        return 1
    print()
    blind_spots()
    print("exit: 0")
    return 0


READ_BY_RECKON = "inventory.json"


def cross_file(paths):
    """Two files that both classify may still disagree about the same defect. Now they cannot.

    THE DEFECT THIS ARM IS FOR — DEF-091, and it was written as a limit on this gate's own clean
    run before it was written as a check. `reckon.read_campaign` reads defects from
    `inventory.json` and from nowhere else, so every other `defects*.json` is a hand-edited source
    that no reckoning opens. Three of `defects.in.json`'s 24 rows said something different from
    the file that is read, and nothing compared them: a reader who opened the source got a
    different answer about DEF-002, DEF-040 and DEF-063 than the ledger gave.

    ADJUDICATED 2026-09-02 by reading each defect rather than by preferring a file, and two of the
    three were not what the finding said they were:

      · DEF-002 and DEF-040 were genuine status disagreements, and `inventory.json` was right on
        both. Its DEF-002 row carries a dated closure naming the two branches that landed it and
        `parity-gate.sh` at e5755d0 reading 82 of 83, which CASE-0036 passes on; its DEF-040 row
        carries a corrected cause and the fix, and `campaign.json` does carry the
        `blindVocabulary` that fix installed. `defects.in.json` held the pre-closure text of each.
      · DEF-063 WAS NOT A STATUS DISAGREEMENT AT ALL. It was an ID COLLISION: `inventory.json`'s
        DEF-063 is a stdio child that starts and exits unnoticed, and `defects.in.json`'s DEF-063
        was an entirely different K3 measurement about the Discover board's two scoping controls.
        Comparing statuses reported one difference and hid the other, which is why this arm
        compares TITLE as well and reports the two separately.

    And the arm found what the finding had missed entirely: `DEF-064` and `DEF-065`, two more K3
    measurements from 2026-08-29, existed in the source file and had NEVER reached the file the
    reckoning reads. Three defects, measured and written down, that no ledger has ever counted.
    That is the same shape `registry-drop-gate.py` exists for, one file upstream, so the second
    half of this arm is a presence check rather than a comparison.

    Both halves are exit 1. A source row that disagrees with the read file is a reader being given
    a different answer depending on which file they open; a source row missing from the read file
    is a defect nobody will ever be told about.
    """
    read_path = next((p for p in paths if p.name == READ_BY_RECKON), None)
    if read_path is None:
        print("  NOT COMPARED — %s is not among the files read, so there is no authority to "
              "compare the sources against" % READ_BY_RECKON)
        return None

    authority = {}
    for row in read(read_path) or []:
        if isinstance(row, dict) and "id" in row:
            authority[row["id"]] = row

    disagreements, absences, compared = [], [], 0
    for path in paths:
        if path == read_path:
            continue
        for row in read(path) or []:
            if not isinstance(row, dict) or "id" not in row:
                continue
            rel = str(path.relative_to(ROOT)).replace("\\", "/")
            other = authority.get(row["id"])
            if other is None:
                absences.append((rel, row["id"], row.get("title")))
                continue
            compared += 1
            fields = [f for f in ("status", "title")
                      if (other.get(f) or "") != (row.get(f) or "")]
            if fields:
                disagreements.append((rel, row["id"], fields,
                                      row.get("status"), other.get("status"),
                                      "title" in fields))
    return compared, disagreements, absences


def report_cross_file(result):
    """Print one cross-file result. Returns True when it found something."""
    if result is None:
        return False
    compared, disagreements, absences = result
    print("  cross-file: %d source row(s) compared against %s" % (compared, READ_BY_RECKON))

    if not disagreements and not absences:
        return False

    if disagreements:
        print()
        print("  %d source row(s) say something different from the file the reckoning reads:"
              % len(disagreements))
        for rel, rid, fields, mine, theirs, title_too in disagreements:
            print("    %s  %s  disagrees on %s" % (rel, rid, ", ".join(fields)))
            print("        source says %r, %s says %r" % (mine, READ_BY_RECKON, theirs))
            if title_too:
                print("        THE TITLES ALSO DIFFER, so this is very likely two different")
                print("        defects sharing one id rather than one defect with two verdicts.")
                print("        Give the source's row a free id in BOTH inventory.json and")
                print("        defects-windows.json, and carry it into the file that is read.")
            else:
                print("        Read the defect and decide which is right, then make them agree.")
                print("        Preferring a file is not an adjudication.")

    if absences:
        print()
        print("  %d source row(s) are absent from %s, so no reckoning has ever counted them:"
              % (len(absences), READ_BY_RECKON))
        for rel, rid, title in absences:
            print("    %s  %s  %s" % (rel, rid, (title or "")[:90]))
        print("        A defect measured, written down, and never carried into the file the tool")
        print("        opens is a defect that does not exist as far as any ledger is concerned.")
    return True


def blind_spots():
    """Printed on every clean run rather than kept in a progress record, because a limit a
    reader has to go and find is a limit the next reader will not know about."""
    print("  WHAT THIS GREEN DOES NOT COVER")
    print("    * `--agree` compares the five WORD LISTS against reckon's own. It does NOT compare")
    print("      the branch STRUCTURE - which sets are matched against the leading token and which")
    print("      against the whole status. That asymmetry is the whole of DEF-011's and DEF-048's")
    print("      defect, it is modelled by hand in `classify`, and reckon changing it would leave")
    print("      `--agree` saying no drift while this gate refused the wrong words. Re-read")
    print("      reckon's defect branch when its version moves. (Held across 1.9.3 and 1.9.4.)")
    print("    * A status that classifies is not a status that is TRUE. `fixed` on a defect nobody")
    print("      re-measured passes here and is reckon's FIX_UNMEASURED_QUALIFIERS problem.")
    print("    * The cross-file arm compares `status`, `title` and presence. Two files agreeing on")
    print("      all three can still hold different TEXT for the same defect, and this says")
    print("      nothing about that - a source row whose narrative is a wave behind the read")
    print("      file's passes here. DEF-002 and DEF-040 were carried across in full for that")
    print("      reason rather than having their one field patched.")
    print("    * Case statuses are a different vocabulary with a different partition, and are not")
    print("      read here at all.")


# --------------------------------------------------------------------------
# --agree: the recorder is not the writer
# --------------------------------------------------------------------------
def find_reckon():
    env = os.environ.get("RECKON_PY")
    if env and Path(env).exists():
        return Path(env)
    home = Path(os.path.expanduser("~"))
    cache = home / ".claude" / "plugins" / "cache"
    hits = sorted(cache.glob("*/reckon/*/skills/reckon/scripts/reckon.py"))
    return hits[-1] if hits else None


def agree():
    path = find_reckon()
    print("agreement arm - this gate's vocabulary against the reckon that would actually run")
    if path is None:
        print("  NOT COMPARED: no reckon.py found. Set RECKON_PY, or accept that this arm did")
        print("  not run - a comparison that did not happen is not a comparison that agreed.")
        print("exit: 2")
        return 2
    print("  reading %s" % path)
    import importlib.util
    spec = importlib.util.spec_from_file_location("_reckon_vocab", str(path))
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001
        print("  NOT COMPARED: %s would not import - %s" % (path.name, exc))
        print("exit: 2")
        return 2

    drift = []
    for name, mine in (("DEFECT_FIXED", DEFECT_FIXED), ("DEFECT_OPEN", DEFECT_OPEN),
                       ("DEFECT_WAIVED", DEFECT_WAIVED), ("DEFECT_NOT_OWING", DEFECT_NOT_OWING),
                       ("DEFECT_PARTIAL", DEFECT_PARTIAL)):
        theirs = getattr(mod, name, None)
        if theirs is None:
            drift.append("%s is absent from %s" % (name, path.name))
        elif set(theirs) != set(mine):
            drift.append("%s: mine-only %s / theirs-only %s"
                         % (name, sorted(set(mine) - set(theirs)), sorted(set(theirs) - set(mine))))
        else:
            print("  %-18s agrees, %d word(s)" % (name, len(mine)))

    if drift:
        print()
        for line in drift:
            print("  DRIFT  %s" % line)
        print("exit: 1")
        return 1
    print()
    print("  no drift. This file mirrors the tool rather than competing with it.")
    print("exit: 0")
    return 0


# --------------------------------------------------------------------------
# --selftest: prove it reddens, including on the compound shape
# --------------------------------------------------------------------------
SELFTEST = [
    ("fixed", True, "verified-done", "the plainest legal word"),
    ("open", True, "broken", "the plainest owing word"),
    ("fixed · in-campaign", True, "verified-done", "a compound whose lead is read as a lead"),
    ("open · measured · partially fixed", True, "broken", "three parts, lead still read"),
    ("blocked: no credential", False, None, "a colon-qualified word outside the partition"),
    ("partially-fixed", True, "broken", "the bare partial word"),
    ("superseded", True, "waived", "the bare not-owing word"),
    ("partially-fixed · in-campaign", False, None,
     "DEF-011's word: a partial branch reads the WHOLE status, so the compound misses"),
    ("superseded · by-DEF-055", False, None,
     "DEF-048's word: same shape through the not-owing branch"),
    ("partly-done", False, None, "a word nobody taught it"),
    ("", False, None, "no status at all"),
    (None, False, None, "the field absent"),
]


def selftest():
    print("selftest - %d case(s) over the classifier" % len(SELFTEST))
    bad = 0
    for raw, want_ok, want_cls, why in SELFTEST:
        ok, cls, _lead, _whole = classify(raw)
        good = (ok == want_ok) and (cls == want_cls)
        if not good:
            bad += 1
        print("  %-4s %-38r want %-14s got %-14s  %s"
              % ("ok" if good else "FAIL", raw,
                 want_cls or "REFUSED", cls or "REFUSED", why))
    print()
    if bad:
        print("exit: 3  (%d case(s) failed)" % bad)
        return 3
    print("  the two compound cases are the arm that matters: a gate reading only the leading")
    print("  token would pass both, and both are the rows this gate was written for.")
    print("exit: 0")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    if "--agree" in argv:
        return agree()
    return run()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
