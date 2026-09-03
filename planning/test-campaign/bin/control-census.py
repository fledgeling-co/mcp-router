#!/usr/bin/env python3
"""The control census, printed from this repository's pinned registry (G28).

WHY THIS EXISTS BESIDE `campaign.py check` RATHER THAN INSTEAD OF IT
-------------------------------------------------------------------
`campaign.py check` has counted actuated controls since **test-campaign 0.11.0**, and it is where
the census belongs. `vendor/test-campaign/` pins **0.9.2**, which has no census at all — not
`NOT DECLARED`, no line. So on the version this repository re-runs its gates from, declaring
`controls` and `actuates` correctly produces exactly no visible change, and the number the brief
asks for is readable only on a machine that happens to hold a newer plugin. Measured 2026-08-27:

    vendor 0.9.2   `check` prints no Controls line, before or after G28's registry edit
    cache  0.14.1  `Controls:   6 of 141 declared control(s) actuated by a passing effect-rung
                   case, across 14 surface(s) that declare any`

Re-vendoring the instrument to read one new line is a change to every gate this campaign quotes,
and `vendor/README.md` is explicit that the pin is the fixed point. So the pin stays and this
prints the same census from the same registry, by the same rules, until the pin moves past 0.11.0
— at which point this file should be deleted and `campaign.py check` read instead.

WHAT IT ADDS THAT THE INSTRUMENT DOES NOT HAVE AT ALL
-----------------------------------------------------
The message-only class. A control whose whole promised effect is something appearing on screen — a
sheet, a panel, a notification — is not the same measurement problem as one that promises a state
change, and upstream's census has no notion of the difference: it counts both as unactuated. That
reads as 135 dead controls where the truth is 81 controls whose only promise is a panel and 54 that
promise a change to the router's own state. Both numbers are printed, because the second is the one
worth chasing and the first is the one a reader would otherwise assume it was.

Which controls are message-only is recorded per surface in `inventory.json` under
`controlsMessageOnly`, derived by `bin/design-controls.py` from the design of record's own handler
tables, not asserted here.

THE DISPOSITION PARTITION, ADDED BY J2
--------------------------------------
A numerator on its own says how many controls are proven and nothing at all about the rest. So
every declared control is now placed in exactly one of four classes, and the fourth is the finding:

    actuated        a passing effect-rung case drives it and reads the effect elsewhere
    message-only    the design's whole promised effect is a sheet, a panel or a notification
    stated reason   `inventory.json` `controlsUnactuatable` says, per control, why nothing drives
                    it -- the build draws no such control, or the only available read is an absence
    UNDISPOSED      none of the above: nobody has said anything about it

`controlsUnactuatable` is prose written by a person, so it is checked rather than believed: a
reason naming a control the surface never declared is a finding (exit 1), and so is a reason
attached to a control a passing case actually drives, because the two claims contradict and one of
them is stale. What it CANNOT check is whether the sentence is true; that limit is why the class is
printed as its own number beside the actuated count rather than folded into it.

TWO POPULATIONS, NOT ONE — DEF-080, closed here
------------------------------------------------
Until 2026-09-02 the word `controls` carried two different kinds of thing. SURF-045, SURF-046 and
SURF-047 are non-glass planes — a Scheduled Task, a COM activator, an MSIX package — and what they
declare is OPERATIONS a lane calls: `LogonTaskSupervisor.Register`, `MakeAppx pack`,
`Add-AppxPackage`. Those eight sat in the same denominator as the Mac Servers board's buttons, and
all eight were in the numerator, so the single headline "N of M declared controls actuated" added
together two quantities that do not mean the same thing and overstated how much GLASS anybody had
driven. The measured size of the overstatement, at the moment of the split:

    before   Controls:   57 of 210 across 33 surface(s)      (27.1%)
    after    Controls:   49 of 202 across 30 surface(s)      (24.3%)
             Operations:  8 of   8 across  3 surface(s)     (100.0%)

The registry now carries the two under different field names — `controls` for a thing a person can
press, `operations` for a call a lane makes — and this file prints a denominator for each and never
a sum of the two. The disposition partition applies to both, minus `message-only`, which is a
statement about a control whose promise is a panel appearing and has no meaning for an operation.
An operation's excuses live in `operationsUnactuatable`, checked exactly as its control twin is.

The split was not an alternative to enumerating the three planes. Leaving them out of the registry
so the ratio stayed pure is the failure this campaign exists to catch; they stay enumerated and the
reader now gets two numbers instead of one wrong one.

THE FIELD REFUSES A COMMAND — the second half of DEF-080
---------------------------------------------------------
`actuates` names a thing the surface DECLARES. It does not name the command your lane ran. In the
wave before this one, three runners wrote the command there — `dotnet test
app/windows/MCPRouter.Shell.Tests`, `UIA TogglePattern.Toggle()` — and the only thing that caught
them was the stray check, which catches a name that is not on the surface's list. That is not the
same check: a command written into `actuates` AND added to the surface's `controls` is a stray no
longer, and the census would then count a command line as a proven button.

So a command-shaped string is refused wherever it appears — in a case's `actuates`, and in a
surface's own declared list, because a declaration is the laundering route. What counts as
command-shaped is deliberately narrow: an invocation with ARGUMENTS, not a command's name. A path
separator between two words, a `-x`/`--xx` flag argument, a script or assembly extension, a `foo(`
call, a shell operator, or a first word that is a known runner (`dotnet`, `pwsh`, `git`, `msbuild`,
…) followed by more words. `winget validate` and `MakeAppx pack` are NOT refused and are not meant
to be: they are two-word operation names on an operation surface, which is what `operations` is for.
The check cannot tell those from a bare command name and does not try — that distinction is what
the separate denominator makes visible instead of hiding.

WHICH FIELD A MEMBER BELONGS IN IS THE SURFACE'S OWN DECLARATION — DEF-131, closed here
----------------------------------------------------------------------------------------
Until 2026-09-03 that question was answered by the SHAPE OF THE NAME: a `controls` entry matching
`Something.Method` (PascalCase either side of a dot) was refused and pointed at `operations`. That
rule caught SURF-045 and SURF-046 and could not catch SURF-047, and the measurement is DEF-131's:
moving SURF-045 and SURF-046 back from `operations` to `controls` reddened with four findings and
moving SURF-047 back reddened with NONE, because `MakeAppx pack`, `winget validate`,
`Add-AppxPackage` and `Remove-AppxPackage` are indistinguishable, to any string rule this file
could carry, from a button somebody labelled that. Widening the regex was not available either:
`winget validate` is a legitimate operation name and `Reset history` is a legitimate control name,
and no string rule separates them.

So the shape rule is GONE — deleted, not kept beside this one to disagree with it — and membership
is derived from a property the SURFACE declares in `inventory.json`:

    plane: glass          a person can see it and press it. Its members are `controls`.
                          Declaring `operations` here is a finding.
    plane: headless       no glass at all — a Scheduled Task, a COM activator, an HTTP route, the
                          daemon itself. Its members are `operations`. Declaring `controls` here
                          is a finding.
    plane: mixed          the surface genuinely has both halves over one subject. BOTH fields are
                          allowed, which means this file cannot decide the question for these rows
                          and says so on its own line rather than counting them as defended. A
                          `mixed` row must carry a `planeNote` saying what each half is, so the
                          escape hatch costs a written justification and stays visible.
    plane: undetermined   nobody has worked out which. Permitted only while the surface declares
                          NOTHING; a member declared under an undetermined plane is a finding,
                          because that is a guess about the denominator wearing a declaration's
                          clothes.

A surface with no `plane`, or with a value not on that list, is a finding. There is no default: a
silent default is the same guess this field exists to refuse.

`command_shape()` below is NOT the old rule and is kept deliberately. It answers a different
question — whether a string is an invocation rather than a declared name at all — and it never
assigns a member to a field, so it cannot disagree with the plane. `dotnet test app/x` is refused
on a headless plane exactly as it is on glass.

WHAT THE PLANE FIELD CANNOT DECIDE
----------------------------------
A surface that is partly glass and partly not is a real shape and `plane` forces one word onto it.
Two rows in this registry are that shape and are declared `mixed` for it: SURF-046, whose declared
members are notifier calls with no glass while the toast they raise carries two buttons a person
presses (REQ-036, undriven), and SURF-022, whose route is measured over the wire and also renders
a consent interstitial CASE-0157 photographs. On those two rows the misfiling class is UNDEFENDED
and the output says so by name. A third, SURF-047, is declared `headless` although an MSIX package
also installs from a double-click in File Explorer: the value describes the half this campaign
enumerated, and the unenumerated half is written into its `planeNote` rather than into a plane
value nothing has measured.

The plane also says nothing about a member misfiled INSIDE its own plane's field — a `Foo.Bar` API
name declared under `controls` on a glass board is a control by declaration here, and the deleted
shape rule did refuse that one case. That is coverage this change gave up rather than gained;
DEF-420 carries it, and `bin/arm-surface-plane.py` plants it against both censuses so the loss is
measured in both directions rather than admitted in a sentence.

THE RULES, WHICH ARE UPSTREAM'S AND NOT THIS FILE'S
---------------------------------------------------
  * A surface's denominator is its `controls` array, and, separately, its `operations` array.
    Absent means the surface declares none of that kind, which is reported as such rather than
    counted as clean.
  * Only `actuates` names that are IN the surface's declared list — either list — count. A name
    outside both is a finding, not a count: it means the case and the registry disagree about what
    the surface carries, and the census has nothing to count it against.
  * A case may name `actuatesSurface` when the control it PRESSES belongs to a different surface
    from the one it is filed against -- you reach a board by pressing the shell's sidebar, and the
    press is the shell's control while the claim is the board's. Added by K3, because two J5 cases
    on SURF-002 named `Servers` (SURF-001's sidebar row) and read as a registry contradiction when
    both halves were correct. It relaxes nothing: the name must still be declared on the surface it
    now points at, and a case that points at a surface declaring nothing is still a stray.
  * Only a PASSING case at an effect rung moves the count. `outcome`, `metamorphic`,
    `effect-witness`, `raster-visual` and `interactive-glass` are the effect rungs; a
    presence-rung or structural-rung pass that clicked a control and asserted the control is still
    there has measured the click and not the effect.

EXITS
-----
    0  the census ran and is printed. An inert surface is REPORTED and does not hold the gate:
       eleven of fourteen are inert today, and a gate that lands permanently red is a gate somebody
       switches off within a week (`registry-drop-gate.py`'s own finding, same week).
    1  a case actuates a name its surface never declared, OR `controlsUnactuatable` /
       `operationsUnactuatable` names something the surface never declared, OR it excuses one a
       passing case actually drives, OR a command-shaped string was written into `actuates` or into
       a declared list, OR a surface declares no `plane` or an unrecognised one, OR it
       declares a member under a field its plane does not carry, OR a `mixed` row carries no
       `planeNote` — every one of these is fixable in the registry right now, unlike an inert
       surface.
    2  no surface declares any controls or operations, so there is no denominator. This is the
       state G28 was written to end, and it is an exit rather than a quiet zero for the reason the
       campaign repeats: a census over an undeclared population reads exactly like a clean one.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CAMPAIGN = ROOT / "planning" / "test-campaign"

# Upstream's, copied rather than inferred: campaign.py's EFFECT_RUNGS at 0.14.1.
EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness", "raster-visual", "interactive-glass"}

# The two populations, and the field each is declared under. `message-only` is a control-side
# class only: it says the design's whole promised effect is a panel appearing, which is not a
# thing an operation can be.
KINDS = (
    ("control", "controls", "controlsMessageOnly", "controlsUnactuatable"),
    ("operation", "operations", None, "operationsUnactuatable"),
)

# A first word that is unambiguously a program rather than a label. `winget` and `MakeAppx` are
# deliberately absent: they are the leading words of two legitimate operation names on SURF-047,
# and a list that refused them would redden an honest row to catch a dishonest one it cannot
# distinguish anyway.
COMMAND_RUNNERS = {
    "dotnet", "npm", "npx", "node", "python", "python3", "py", "pwsh", "powershell", "bash",
    "sh", "zsh", "cmd", "git", "msbuild", "cargo", "curl", "wget", "schtasks", "reg", "swift",
    "xcodebuild", "make", "docker", "gh", "kubectl", "pytest", "ssh", "scp", "rsync",
}
_PATH = re.compile(r"[A-Za-z0-9_.\-][/\\][A-Za-z0-9_.\-]")
_FLAG = re.compile(r"\s--?[A-Za-z]")
_EXT = re.compile(r"\.(?:ps1|psm1|exe|dll|py|sh|cmd|bat|csproj|sln|cs|xaml|swift|js|ts)"
                  r"(?:$|[\s'\":;,])")
_CALL = re.compile(r"[A-Za-z0-9_\]\)]\(")
_SHELL = re.compile(r"&&|\|\||[|`]|\s>\s|\$\(")
# Which declared field each plane may carry. `undetermined` maps to no field at all: it is a
# statement that nobody has worked out the answer, and a surface making that statement while
# declaring members has guessed rather than deferred.
PLANE_FIELDS: dict[str, frozenset[str]] = {
    "glass": frozenset({"controls"}),
    "headless": frozenset({"operations"}),
    "mixed": frozenset({"controls", "operations"}),
    "undetermined": frozenset(),
}


def command_shape(name: str) -> str:
    """Why `name` reads as an invocation rather than a declared name, or "" if it does not."""
    text = str(name)
    if _PATH.search(text):
        return "carries a path separator between two words, so it is a command line's argument"
    if _FLAG.search(text):
        return "carries a `-x` or `--xx` flag argument"
    if _EXT.search(text):
        return "names a script or assembly file"
    if _CALL.search(text):
        return "is a code call: an identifier immediately followed by `(`"
    if _SHELL.search(text):
        return "carries a shell operator"
    words = text.split()
    if len(words) > 1 and words[0].lower().removesuffix(".exe") in COMMAND_RUNNERS:
        return "starts with the runner `%s` and takes arguments" % words[0]
    return ""


# Upstream's `state_of` resolves a status to pass/fail/skip/…; the only resolution this needs is
# whether the case passed, and a status carrying a reason after a colon keeps its head word.
def passed(status: str) -> bool:
    return (status or "").strip().lower().split(":")[0].strip() == "pass"


def main() -> int:
    # The other half of the same Windows fix. A console handle on this host encodes as cp1252, so
    # the arrow in a `controlsUnactuatable` reason raised UnicodeEncodeError AFTER the census had
    # printed four correct lines -- a gate that reports most of its finding and then dies with a
    # non-zero exit that has nothing to do with the registry. `errors="replace"` rather than a
    # hard utf-8: a mangled glyph in a prose reason is a cosmetic loss, and a crash is not.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):  # a pipe or a capture that is already text
            pass

    # `utf-8-sig` rather than the platform default, and it is not a tidy-up. `read_text()` with
    # no encoding decodes as cp1252 on Windows, so this file raised UnicodeDecodeError on the
    # first curly quote in `cases.json` and printed no census at all on the host that runs
    # `scripts/windows/verify.ps1`. A gate that cannot be read on half the machines that own it
    # reports nothing and looks like it was never wired up. `-sig` because the Windows lanes
    # write BOM-led JSON (`planning/evidence/WIN-SHELL/run/*.json` all carry one) and a BOM is
    # not a decode error, it is a byte order mark this reader should eat.
    inventory = json.loads((CAMPAIGN / "inventory.json").read_text(encoding="utf-8-sig"))
    cases = json.loads((CAMPAIGN / "cases.json").read_text(encoding="utf-8-sig"))

    # Everything below is keyed on (kind, surface id), so the two populations can never be added
    # by accident: there is no dictionary in this file whose values span both.
    declared: dict[tuple[str, str], list[str]] = {}
    message_only: dict[tuple[str, str], set[str]] = {}
    excused: dict[tuple[str, str], dict[str, str]] = {}
    titles: dict[str, str] = {}
    strays: list[str] = []

    # THE PLANE, read per surface before anything is counted. Every surface must carry one:
    # there is no default, because a default is a guess about the denominator that later reads
    # as a declaration (DEF-131).
    mixed_rows: list[str] = []
    for s in inventory.get("surface", []):
        sid, plane = s["id"], s.get("plane")
        declares = [field for _k, field, _m, _e in KINDS if s.get(field)]
        if plane not in PLANE_FIELDS:
            strays.append(
                f"{sid} declares `plane`: {plane!r}, which is not one of "
                f"{', '.join(sorted(PLANE_FIELDS))}. The plane is what decides whether this "
                f"surface's members are `controls` a person presses or `operations` a lane "
                f"calls, and nothing here guesses it — DEF-131.")
        else:
            for field in declares:
                if field not in PLANE_FIELDS[plane]:
                    allowed = " or ".join(f"`{f}`" for f in sorted(PLANE_FIELDS[plane])) \
                        or "nothing at all"
                    strays.append(
                        f"{sid} is declared `plane`: {plane} and declares {len(s[field])} "
                        f"member(s) under `{field}`. A {plane} surface declares {allowed}. "
                        f"Either the members are in the wrong field or the plane is wrong; the "
                        f"census will not decide which — DEF-131.")
            if plane == "mixed":
                mixed_rows.append(sid)
                if not str(s.get("planeNote") or "").strip():
                    strays.append(
                        f"{sid} is declared `plane`: mixed and carries no `planeNote`. `mixed` "
                        f"is the value that switches this check off for a row, so it costs a "
                        f"written statement of what each half is — DEF-131.")
        for kind, field, msg_field, excuse_field in KINDS:
            if not s.get(field):
                continue
            key = (kind, s["id"])
            declared[key] = [str(x) for x in s[field]]
            message_only[key] = {str(x) for x in ((s.get(msg_field) or []) if msg_field else [])}
            excused[key] = {str(k): str(v) for k, v in (s.get(excuse_field) or {}).items()}
            titles[s["id"]] = s.get("title", "")

    if not declared:
        print("Controls:   NOT DECLARED — no surface lists its controls, so nothing here counts "
              "them. A control renders, carries its accessible name, passes a contrast gate and "
              "accepts a click whether or not its handler does anything.", file=sys.stderr)
        return 2

    # Which surfaces carry which kind, and the flat membership a case's `actuates` resolves
    # against: a name may be declared as a control on one surface and an operation on another,
    # and the case is judged against whichever list the surface it points at carries.
    kinds_of: dict[str, list[str]] = {}
    for kind, sid in declared:
        kinds_of.setdefault(sid, []).append(kind)

    # A command written into a DECLARED list is refused here, before any counting. This is the
    # laundering route the stray check cannot see: add the command to `controls` and it stops
    # being a stray while remaining a command.
    for (kind, sid), names in sorted(declared.items()):
        for name in names:
            why = command_shape(name)
            if why:
                strays.append(f"{sid} declares `{name}` under `{kind}s` and it {why}. `{kind}s` "
                              f"names what the SURFACE carries; the command a lane ran belongs in "
                              f"the case's `note`.")

    actuated: dict[tuple[str, str], set[str]] = {k: set() for k in declared}
    claimed: dict[tuple[str, str], set[str]] = {k: set() for k in declared}
    # A case that actuates nothing is not a case this census can count, and until now it left no
    # trace: the numerator moved only for cases carrying `actuates`, and the size of the set that
    # could never move it was invisible. That set is the census's own blind spot — a surface whose
    # cases all sit in it reads as "declares controls that nothing actuates" with no way to tell
    # a control nobody drove from a suite that never names controls at all.
    no_actuation: list[str] = []
    for c in cases:
        names = [str(n) for n in (c.get("actuates") or [])]
        if not names:
            no_actuation.append(str(c.get("id") or "<case with no id>"))
            continue
        cid = c.get("id")
        # The command check first, and on every entry, whether or not it resolves to a surface.
        # A command that happens to be declared is still a command.
        commands = [(n, command_shape(n)) for n in names]
        for n, why in commands:
            if why:
                strays.append(f"{cid} actuates `{n}`, which {why}. `actuates` names a control or "
                              f"operation the SURFACE declares, not the command this lane ran — "
                              f"put that in the case's `note`.")
        # Where the control lives, which is not always where the case is filed.
        sid = c.get("actuatesSurface") or c.get("surface")
        if sid not in kinds_of:
            strays.append(f"{cid} actuates {len(names)} name(s) on "
                          f"{sid or 'no surface'}, which declares none")
            continue
        known: dict[str, str] = {}
        for kind in kinds_of[sid]:
            for n in declared[(kind, sid)]:
                known[n] = kind
        outside = [n for n in names if n not in known]
        if outside:
            strays.append(f"{cid} actuates {'; '.join(outside)} — not among {sid}'s "
                          f"declared controls or operations")
        counts = passed(c.get("status", "open")) and c.get("oracle") in EFFECT_RUNGS
        for n in names:
            kind = known.get(n)
            if not kind:
                continue
            claimed[(kind, sid)].add(n)
            if counts:
                actuated[(kind, sid)].add(n)

    # The disposition partition, per kind. Each declared name lands in exactly one class,
    # actuated first, so the classes add to that kind's denominator and nothing can be counted
    # twice by being excused and driven at once -- that contradiction is a finding rather than a
    # rounding.
    undisposed: dict[tuple[str, str], list[str]] = {}
    for key in declared:
        kind, sid = key
        known = set(declared[key])
        for name in sorted(set(excused[key]) - known):
            strays.append(f"{sid} excuses {name} under `{kind}sUnactuatable` — not among its "
                          f"declared {kind}s")
        for name in sorted((set(excused[key]) & known) & actuated[key]):
            strays.append(f"{sid} excuses {name} as unactuatable while a passing effect-rung case "
                          f"drives it — one of the two claims is stale")
        undisposed[key] = sorted(known - actuated[key] - message_only[key] - set(excused[key]))

    named_cases = len(cases) - len(no_actuation)
    print(f"Cases:      {named_cases} of {len(cases)} case(s) name a control or operation they "
          f"actuate; {len(no_actuation)} name none and cannot move any number below")

    def totals(kind: str) -> tuple[int, int, int]:
        keys = [k for k in declared if k[0] == kind]
        return (sum(len(actuated[k]) for k in keys),
                sum(len(declared[k]) for k in keys),
                len(keys))

    hit, total, surfaces_n = totals("control")
    msg_keys = [k for k in declared if k[0] == "control"]
    msg_total = sum(len(message_only[k]) for k in msg_keys)
    unhit_msg = sum(len(message_only[k] - actuated[k]) for k in msg_keys)
    unhit_state = (total - hit) - unhit_msg
    excused_total = sum(len((set(excused[k]) & set(declared[k])) - actuated[k]) for k in msg_keys)
    undisposed_total = sum(len(undisposed[k]) for k in msg_keys)

    print(f"Controls:   {hit} of {total} declared control(s) actuated by a passing effect-rung "
          f"case, across {surfaces_n} surface(s) that declare any")
    print(f"            {msg_total} of the {total} are message-only — the design's whole promised "
          f"effect is a sheet, a panel or a notification appearing.")
    print(f"            Of the {total - hit} not actuated, {unhit_msg} are message-only and "
          f"{unhit_state} promise a state change nothing has driven.")
    print(f"            Disposition: {hit} actuated · {unhit_msg} message-only · {excused_total} "
          f"with a stated reason · {undisposed_total} UNDISPOSED — nobody has said anything "
          f"about these.")

    op_hit, op_total, op_surfaces = totals("operation")
    op_keys = [k for k in declared if k[0] == "operation"]
    if op_total:
        op_excused = sum(len((set(excused[k]) & set(declared[k])) - actuated[k]) for k in op_keys)
        op_undisposed = sum(len(undisposed[k]) for k in op_keys)
        print(f"Operations: {op_hit} of {op_total} declared operation(s) actuated by a passing "
              f"effect-rung case, across {op_surfaces} surface(s) that declare any")
        print(f"            Disposition: {op_hit} actuated · {op_excused} with a stated reason · "
              f"{op_undisposed} UNDISPOSED.")
    else:
        print("Operations: none declared. No surface in this registry names an operation a lane "
              "calls, which is a fact about the registry rather than about the product.")
    if mixed_rows:
        print(f"            UNDEFENDED: {len(mixed_rows)} surface(s) are declared `plane`: mixed "
              f"— {', '.join(sorted(mixed_rows))} — and carry both halves over one subject, so "
              f"nothing here can decide which field a new member belongs in. Those rows are "
              f"checked by a person reading them. DEF-131.")
    else:
        print("            No surface is declared `plane`: mixed, so every declared member's "
              "field is derivable from its surface's own plane. DEF-131.")
    print("            The two counts above are NEVER added. A control is something a person can "
          "press on glass; an operation is a call a lane makes on a plane with no glass at all "
          "(a Scheduled Task, a COM activator, an MSIX package). DEF-080.")
    print()

    for kind, _field, _m, _e in KINDS:
        keys = sorted((k for k in declared if k[0] == kind), key=lambda k: k[1])
        if not keys:
            continue
        print(f"  {kind.upper()}S")
        for key in keys:
            sid = key[1]
            n, a = len(declared[key]), len(actuated[key])
            m = len(message_only[key])
            near = claimed[key] - actuated[key]
            tail = (f" · {len(near)} driven only by a case below `outcome` or not passing"
                    if near else "")
            u = len(undisposed[key])
            tail += f" · {u} undisposed" if u else " · fully disposed"
            msg = f" · {m} message-only" if kind == "control" else ""
            print(f"  {sid}  {a:>2} of {n:>2} actuated{msg}{tail}   {titles[sid]}")
            if a:
                print(f"        actuated: {'; '.join(sorted(actuated[key]))}")
            if excused[key]:
                print(f"        stated reason: "
                      f"{'; '.join(sorted(set(excused[key]) & set(declared[key])))}")
        print()

    inert = sorted({f"{k[1]} ({k[0]}s)" for k in declared if not actuated[k]})
    if inert:
        print(f"  {len(inert)} surface population(s) declare names that no passing effect-rung "
              f"case actuates: {', '.join(inert)}")
        print("  Reported, not blocked. The denominator is the finding; a gate that lands "
              "permanently red gets switched off.")

    if strays:
        print(f"\n  {len(strays)} finding(s) — the registry and the cases disagree about what "
              f"each surface carries, or a command was written where a declared name belongs:",
              file=sys.stderr)
        for s in strays:
            print(f"    · {s}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
