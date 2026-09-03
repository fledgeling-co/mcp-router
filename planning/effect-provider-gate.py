#!/usr/bin/env python3
"""An effect claim names production code that can perform it, or says in the register why nothing can.

## The defect this exists for

REQ-016 declares an `outbound-socket` effect and records no `provider`. `vacuity-check.py --gate`
(test-campaign 0.14.1) found it on 2026-08-29: providers were 8 of 9 named, the 8 resolved over 492
production files, and the ninth named nothing at all. A requirement in that state asserts a
behaviour with no candidate implementation behind the assertion, and it passes quietly in both the
directions that matter — if the socket really is opened the requirement cannot say by what, so a
change that removes the call has nothing pointing at it; if it is not opened at all the requirement
is a promise the product does not keep, and the campaign records it as observed anyway.

`vacuity-check.py` **reports** that state. It lives under `vendor/`, pinned by checksum, and this
repository may not edit it. So the finding it produces is carried forward run after run rather than
refused, which is the shape this repository keeps recording as an instrument whose redness stops
carrying information. This gate is the refusal, written where the repository is allowed to write it.

## What it will not do, because the honest answer to REQ-016 is not a count

The acceptance sketch for REQ-016 asks for "9 of 9 named and 9 resolved". A gate written to that
number would be satisfied by somebody typing a plausible file into the `provider` field, which is
the release-by-typing this campaign refuses everywhere else. So the rule is a DISJUNCTION and the
second half is a real exit:

  * name a provider that resolves in the production tree, or
  * record the claim as `vacuous` AND say in `providerNote` what is missing.

REQ-016 takes the second branch today and passes here, deliberately. It is a product gap somebody
wrote down, not a hole in the register — and which remedy it gets (build the transport, or withdraw
the requirement) is the owner's call, filed as `DEF-440` rather than settled by a gate.

## The three rules

R1  a row declaring an effect with no `provider` and an `evidence` word other than `vacuous` is
    refused. This is REQ-016's shape before K4 re-classed it, and the state the sketch names.
R2  a row declaring an effect with no `provider`, `evidence: vacuous` and no `providerNote` is
    refused. A vacuity word with no reason attached is a status word doing a measurement's job.
R3  a `provider` naming a file that does not resolve under the production roots is refused. This is
    the sketch's fourth bullet: a provider that stops resolving — renamed, deleted, moved out of the
    production tree — must fail rather than reverting to unbound.

## What R3 does NOT check, printed on every clean run rather than left to be discovered

The `provider` field is prose with paths in it. This gate extracts only tokens that look like a
source path — no whitespace, a known source extension, at least one `/` — and it says how many
tokens in each row it could not read. A row whose entire provider is prose therefore passes R3 while
being checked by nothing, and the census line is where a reader sees that. It also checks that the
FILE exists and never that the SYMBOL inside it does: a line number is not followed and a renamed
function inside a surviving file passes here.

Exit codes: 0 clean · 1 findings · 2 the gate could not read its input · 3 `--selftest` failed.

  python3 planning/effect-provider-gate.py
  python3 planning/effect-provider-gate.py --selftest
"""
import io
import json
import re
import sys
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
INVENTORY = ROOT / "planning" / "test-campaign" / "inventory.json"

FINDINGS = 1
COULD_NOT_RUN = 2
SELFTEST_FAILED = 3

# `effect: "none"` is a positive declaration that the requirement performs no effect of its own, and
# it is what 22 of this register's rows carry. It is not an absent field and must not be read as one.
NO_EFFECT = ("none", "", None)

# The one evidence word that means "the product does not do this at all", so there is nothing for a
# provider to be. Mirrored from `reckon.py`'s requirement vocabulary and from
# `references/effect-boundary.md` §2, which is where the contradicted/vacuous distinction is drawn.
VACUOUS = "vacuous"

# Where a provider may resolve. A provider is allowed to name a path relative to the repository root
# or relative to one of these, because the register already carries both forms — REQ-001 writes
# `RouterCore/Pool/StdioUpstreamTransport.swift` while REQ-021 writes the full
# `app/Sources/RouterCore/AuthServer/AuthServerRoutes.swift`.
PREFIXES = ("", "app/Sources/", "app/", "src/", "planning/", "planning/test-campaign/", "scripts/")

SOURCE_SUFFIXES = (".swift", ".ts", ".tsx", ".js", ".mjs", ".cs", ".py", ".sh", ".xml", ".json",
                   ".yaml", ".yml", ".plist", ".md")

# A token that could be a path: no whitespace, at least one separator, a known source extension, and
# optionally a `:line` this gate deliberately does not follow.
PATH_TOKEN = re.compile(r"[A-Za-z0-9_./\-*]+(?:%s)(?::\d+)?" % "|".join(
    re.escape(s) for s in SOURCE_SUFFIXES))


def declares_effect(row):
    effect = row.get("effect")
    return not (effect is None or str(effect).strip().lower() in NO_EFFECT)


def path_tokens(provider):
    """Every token in a provider string this gate is willing to call a path."""
    return [m.group(0) for m in PATH_TOKEN.finditer(str(provider or ""))]


def resolves(token):
    """True when some prefix makes the token an existing file. A `*` is a glob and is matched as one."""
    bare = token.split(":", 1)[0]
    for prefix in PREFIXES:
        candidate = prefix + bare
        if "*" in candidate:
            try:
                if any(ROOT.glob(candidate)):
                    return True
            except (ValueError, OSError):
                continue
        elif (ROOT / candidate).exists():
            return True
    return False


def check(rows):
    """Return (findings, census). A finding is (rule, id, sentence)."""
    findings = []
    census = {"declaring": 0, "bound": 0, "vacuous": 0, "tokens": 0, "unreadable_tokens": 0}

    for row in rows:
        if not isinstance(row, dict) or "id" not in row:
            continue
        if not declares_effect(row):
            continue
        census["declaring"] += 1
        rid = row["id"]
        provider = str(row.get("provider") or "").strip()
        evidence = str(row.get("evidence") or "").strip().lower()

        if not provider:
            if evidence != VACUOUS:
                findings.append((
                    "R1", rid,
                    "declares a %r effect, names no provider, and its evidence is %r. Either name "
                    "production code that can perform it, or re-class the row `vacuous` and say in "
                    "`providerNote` what is missing." % (row.get("effect"), evidence or "(absent)")))
            elif not str(row.get("providerNote") or "").strip():
                findings.append((
                    "R2", rid,
                    "is `vacuous` with no provider and no `providerNote`. The word says the product "
                    "does not do this; nothing says what would have to exist for it to."))
            else:
                census["vacuous"] += 1
            continue

        census["bound"] += 1
        tokens = path_tokens(provider)
        census["tokens"] += len(tokens)
        if not tokens:
            census["unreadable_tokens"] += 1
            continue
        for token in tokens:
            if not resolves(token):
                findings.append((
                    "R3", rid,
                    "names provider %r, which resolves to no file under the production roots. A "
                    "provider that stops resolving is an unbound effect claim wearing a name."
                    % token))
    return findings, census


def read_rows():
    try:
        blob = json.load(io.open(INVENTORY, encoding="utf-8-sig"))
    except Exception as exc:  # noqa: BLE001 - the message is the verdict
        print("could not read %s - %s" % (INVENTORY, exc))
        return None
    rows = blob.get("requirement") if isinstance(blob, dict) else None
    if not isinstance(rows, list):
        print("%s carries no `requirement` array" % INVENTORY)
        return None
    return rows


def run():
    rows = read_rows()
    if rows is None:
        print("exit: 2  (nothing was read, so nothing was checked)")
        return COULD_NOT_RUN

    findings, census = check(rows)
    print("effect providers - an effect claim names code that can perform it, or says why none can")
    print("  %d requirement row(s) read; %d declare an effect"
          % (len(rows), census["declaring"]))
    print("    %d name a provider, %d are declared vacuous with a reason"
          % (census["bound"], census["vacuous"]))
    print("    %d provider path token(s) checked for resolution; %d row(s) carried a provider this "
          "gate could read no path out of and therefore checked nothing in"
          % (census["tokens"], census["unreadable_tokens"]))
    print()

    if findings:
        print("  %d row(s) refused:" % len(findings))
        for rule, rid, sentence in findings:
            print("    %s  %s %s" % (rule, rid, sentence))
        print()
        print("exit: 1")
        return FINDINGS

    print("  WHAT THIS GREEN DOES NOT COVER")
    print("    * R3 checks that the FILE exists, never that the symbol inside it does. A renamed")
    print("      function in a surviving file passes, and a `:line` is not followed.")
    print("    * A provider this gate could read no path out of is counted above and checked by")
    print("      nothing. Prose in that field buys a pass on R3.")
    print("    * `vacuous` with a reason is a PASS here and is still a product gap. It is a claim")
    print("      the register admits it cannot keep, not a claim it has kept.")
    print()
    print("exit: 0")
    return 0


# --------------------------------------------------------------------------
# --selftest: watch each rule redden on a plant
# --------------------------------------------------------------------------
REAL_PROVIDER = "app/Sources/MCPRouterKit/Pairing/PairingService.swift"

SELFTEST = [
    ({"id": "T-1", "effect": "none", "evidence": "reported"}, [],
     "no effect declared - not this gate's population at all"),
    ({"id": "T-2", "effect": "outbound-socket", "provider": REAL_PROVIDER, "evidence": "observed"}, [],
     "a bound effect whose provider resolves"),
    ({"id": "T-3", "effect": "outbound-socket", "evidence": "observed"}, ["R1"],
     "REQ-016's shape BEFORE the re-class: an effect, no provider, and an evidence word that "
     "claims the product does it"),
    ({"id": "T-4", "effect": "outbound-socket", "evidence": "reported"}, ["R1"],
     "the same with the commonest evidence word in this register"),
    ({"id": "T-5", "effect": "outbound-socket", "evidence": "vacuous"}, ["R2"],
     "vacuity typed with no reason attached"),
    ({"id": "T-6", "effect": "outbound-socket", "evidence": "vacuous",
      "providerNote": "no symbol under app/Sources opens a connection to a paired device"}, [],
     "REQ-016 as it actually stands: vacuity with the absence written down"),
    ({"id": "T-7", "effect": "ipc", "provider": "app/Sources/RouterCore/Gone/Vanished.swift",
      "evidence": "observed"}, ["R3"],
     "a provider that no longer resolves - the sketch's fourth bullet"),
    ({"id": "T-8", "effect": "ipc",
      "provider": "%s and app/Sources/RouterCore/Gone/Vanished.swift" % REAL_PROVIDER,
      "evidence": "observed"}, ["R3"],
     "one resolving and one not: a row is not excused by its good half"),
    ({"id": "T-9", "effect": "filesystem-write", "provider": "the storage layer", "evidence": "observed"},
     [], "prose with no path in it - passes R3 and is counted as unchecked, stated rather than hidden"),
]


def selftest():
    print("selftest - %d planted row(s), one per rule and one per way of not being one" % len(SELFTEST))
    bad = 0
    for row, want, why in SELFTEST:
        findings, _ = check([row])
        got = [f[0] for f in findings]
        ok = got == want
        if not ok:
            bad += 1
        print("  %-4s %-5s want %-6s got %-6s  %s"
              % ("ok" if ok else "FAIL", row["id"], want or "clean", got or "clean", why))
    print()
    if bad:
        print("exit: 3  (%d planted row(s) did not behave)" % bad)
        return SELFTEST_FAILED
    print("  T-3 and T-6 are the pair that matters. They differ only in the evidence word and the")
    print("  note, and the gate refuses one and passes the other - so the exit it offers is a")
    print("  recorded absence, not a typed one.")
    print("exit: 0")
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else run())
