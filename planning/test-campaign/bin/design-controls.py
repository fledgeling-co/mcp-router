#!/usr/bin/env python3
"""Enumerate, from the design of record, the controls each Mac surface is specified to carry.

WHY THE DESIGN AND NOT THE BUILD
--------------------------------
`campaign.py check` (0.11.0 and later) counts how many of a surface's declared controls a passing
effect-rung case actuated. That count needs a denominator, and a denominator read off the running
app cannot contain a control the app never drew — which is the one class of defect this campaign
has already paid to find twice, both times the expensive way:

  * DEF-011  — Cleanup's per-row Inspect/Remove actions are specified by the design and drawn by
               nothing.
  * SURF-003 — the witness verdict for the Activity board: the design specifies a "Reset history…"
               button the build draws nowhere. Confirmed independently by `vocab-differential.py`
               at designControls=1 buildControls=0.

Both were found by differential, one board at a time, against a mock that had to be rendered and an
accessibility dump that had to be on disk. A declared control list answers the same question by
census, for every board at once, and keeps answering it after the dumps go stale.

So the list comes from `design/mocks/prototype.html` — the file `campaign.json` names as
`designOfRecord`, and the file `vocab-differential.py` already reads for its design half.

A BOARD IS ITS STATES, NOT ITS FIRST RENDER
-------------------------------------------
The prototype boots with `log:[]`, `inbox:[]`, no selection, no sheet and no menu open. Harvesting
that one render returns 47 controls across eleven surfaces and reads as the design being thin. It
is not: the Inbox's Review…/Decline pair exists only once something is queued, every board's row
context menu exists only on a right-click, and 65 of the 141 controls below are reachable only past
the boot render — in a sheet, a menu, an inspector or a populated board. So each surface here is a
LIST of states, reached through the prototype's own deep-link parameters (`pane`, `sheet`, `sel`,
`sfilter`, …, documented at the bottom of the mock) plus, where the mock has no parameter, the
state field its own action would have set. The census is the union.

WHAT COUNTS AS A CONTROL
------------------------
An element the design draws as actuable — button, `[role=button]`, input, select, summary — that
is visible and not drawn disabled. Three subtractions, the same shape `vocab-differential.py` uses
and for the same reasons:

  1. REGION.  A control belongs to the surface that draws it. The sidebar, window title and menu
     bar appear on every board, so they are the shell's (SURF-001) and no board's. Without this
     every board would inherit fourteen navigation controls and the denominator would be mostly
     chrome.
  2. THE TENANT'S OWN DATA.  A control repeated once per row — Cleanup's three Inspect buttons — is
     ONE control: the design specifies one affordance and the fixture decides how many rows it
     lands on. Deduplication is by resolved name within a surface.
  3. DESCRIPTION TEXT.  A toggle's label is its first line; the paragraph under it is help. Settings'
     three update toggles read as 40-to-90-character labels unless the `.t3` descendants are
     stripped, and a width filter then drops them — measured here: a first pass at this file
     reported Settings as carrying three controls, and it carries ten.

NAMING, AND THE ONE HAND-WRITTEN HALF
-------------------------------------
A control's census name has to be stable across fixtures, because a case's `actuates` cites it by
string. Most controls name themselves. Two classes cannot:

  * a row that IS the control — the Servers board draws each server as a button that opens the
    inspector, so its label is a server name;
  * a control the design draws with a glyph — the inspector's `✕`, the menu bar's status item.

Those resolve through `FALLBACK`, keyed on the design's own `data-a`/`data-v`/`data-ctx`
attributes, which is the mock stating what the control is for. Every raw label is kept in the
emitted JSON beside the resolved name, so the mapping is auditable rather than asserted.

MESSAGE-ONLY CONTROLS
---------------------
Every actuable element in the prototype carries `data-a`, naming its entry in the mock's `A{}`
action table. Two of those entries, `recheck` and `noop`, are empty functions; the rest of
`MESSAGE_ONLY_ACTIONS` open a panel, a sheet or a selection and change nothing else. That is the
design saying a control's whole promised effect is something appearing on screen. A census that
counted those as unactuated state changes would be demanding evidence the product never promised,
so they are recorded as their own class — and they are NOT removed from the denominator, because a
sheet that does not open is still a broken control.

WHY OBSCURA AND NOT A PARSE
---------------------------
The prototype renders its panes from JavaScript template functions; no board-attributable label is
in the static HTML. `getBoundingClientRect()` is documented correct on this engine and
`offsetParent` is not — measured 20 Aug 2026 and recorded in `vocab-differential.py`'s own comment
for the same probe — so visibility is taken from the box.

EXITS
-----
    0  every state returned its controls and every surface has at least one
    2  a state returned nothing, or a surface came back empty — a board specifying no controls is a
       broken probe far more often than a true empty, so this refuses rather than writing an empty
       denominator, which is the failure the whole census exists to avoid
    3  obscura could not be run at all
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOCK = ROOT / "design/mocks/prototype.html"
CONSOLE = ROOT / "design/mcp-router-console.html"
OUT = ROOT / "planning/test-campaign/evidence/design-controls.json"
INVENTORY = ROOT / "planning/test-campaign/inventory.json"

# surface id -> (title, [(state name, query, setup JS, region selector), …])
# `only=mac` hides the phone column so nothing on it can be attributed to a Mac surface.
SURFACES: list[tuple[str, str, list[tuple[str, str, str, str]]]] = [
    ("SURF-001", "Mac shell — sidebar, title, menus", [
        ("sidebar", "pane=activity", "", ".side"),
        ("menu-bar", "pane=activity", "", "#menubar"),
        ("menu:Conduit", "pane=activity", "S.menu='Conduit'", "#menubar"),
        ("menu:File", "pane=activity", "S.menu='File'", "#menubar"),
        ("menu:Edit", "pane=activity", "S.menu='Edit'", "#menubar"),
        ("menu:View", "pane=activity", "S.menu='View'", "#menubar"),
        ("menu:Window", "pane=activity", "S.menu='Window'", "#menubar"),
        ("menu:Help", "pane=activity", "S.menu='Help'", "#menubar"),
    ]),
    ("SURF-002", "Mac Servers board", [
        ("board", "pane=servers", "", ".main"),
        ("board:needs-you", "pane=servers&sfilter=attn", "", ".main"),
        ("inspector:running", "pane=servers&sel=obscura", "", ".insp"),
        ("inspector:held", "pane=servers&sel=fetch-pro", "", ".insp"),
        ("context-menu:server", "pane=servers", "CTX('server')", ".ctx"),
        ("sheet:add-server", "pane=servers&sheet=addserver", "", ".sh"),
        ("sheet:confirm-remove", "pane=servers&sheet=remove:obscura", "", ".sh"),
        ("sheet:quarantine", "pane=servers&sheet=held:fetch-pro", "", ".sh"),
    ]),
    ("SURF-003", "Mac Activity board", [
        ("board", "pane=activity", "", ".main"),
        ("sheet:reset-history", "pane=activity&sheet=reset", "", ".sh"),
    ]),
    ("SURF-004", "Mac Skills board", [
        ("board", "pane=skills", "", ".main"),
        ("board:held", "pane=skills&kfilter=held", "", ".main"),
        ("inspector:skill", "pane=skills&sel=trawl", "", ".insp"),
        ("inspector:provenance", "pane=skills&sel=pr-summariser", "", ".insp"),
        ("context-menu:skill", "pane=skills", "CTX('skill')", ".ctx"),
        ("sheet:add-marketplace", "pane=skills&sheet=addmarket", "", ".sh"),
        ("sheet:capability-delta", "pane=skills&sheet=update:trawl", "", ".sh"),
        ("sheet:version-history", "pane=skills&sheet=history:trawl", "", ".sh"),
    ]),
    ("SURF-005", "Mac Discover board", [
        ("board:skills", "pane=discover", "", ".main"),
        ("board:servers", "pane=discover", "S.dkind='servers'", ".main"),
        ("sheet:registry-detail", "pane=discover&sheet=reg:discipline", "", ".sh"),
    ]),
    ("SURF-006", "Mac Checks board", [
        ("board", "pane=evals", "", ".main"),
    ]),
    ("SURF-007", "Mac Cleanup board", [
        ("board", "pane=cleanup", "", ".main"),
        ("sheet:confirm-remove", "pane=cleanup&sheet=remove:mac-doctor", "", ".sh"),
        ("sheet:skill-provenance", "pane=cleanup&sheet=prov:pr-summariser", "", ".sh"),
        ("sheet:reset-history", "pane=cleanup&sheet=reset", "", ".sh"),
    ]),
    ("SURF-008", "Mac Inbox board and review sheet", [
        ("board:empty", "pane=inbox", "", ".main"),
        ("board:queued", "pane=inbox",
         "S.inbox=[{n:'discipline',when:'2m ago',fresh:true}]", ".main"),
        ("sheet:queued-detail", "pane=inbox&sheet=reg:discipline",
         "S.inbox=[{n:'discipline',when:'2m ago',fresh:true}]", ".sh"),
    ]),
    ("SURF-009", "Mac menu-bar popover and inbox band", [
        ("popover", "pane=activity&popover=1", "", ".pop"),
        ("popover:inbox-band", "pane=activity&popover=1",
         "S.inbox=[{n:'discipline',when:'2m ago',fresh:true}]", ".pop"),
    ]),
    ("SURF-010", "Mac Pairing sheet", [
        ("sheet:pair", "sheet=pair", "", ".sh"),
    ]),
    ("SURF-011", "Mac Settings board", [
        ("board", "pane=settings", "", ".main"),
        ("sheet:pair-another", "pane=settings&sheet=pair", "", ".sh"),
        ("sheet:reset-history", "pane=settings&sheet=reset", "", ".sh"),
    ]),
]

# The mock's own action table, read at `const A={…}`. An entry here is a control whose only
# promised effect is something appearing on screen. `recheck` and `noop` are literally empty
# functions in the design of record — the design specifying a control it has not wired.
MESSAGE_ONLY_ACTIONS = {
    "sheet": "opens a sheet and changes nothing else",
    "sel": "opens or closes the inspector and changes nothing else",
    "recheck": "empty function in the design of record — specified as a no-op",
    "noop": "empty function in the design of record — specified as a no-op",
    "menu": "opens a menu and changes nothing else",
    "mitem": "navigates or opens a sheet and changes nothing else",
    "popover": "opens or closes the menu-bar popover and changes nothing else",
    "goto": "navigates to a board and changes nothing else",
    "closesheet": "dismisses a sheet and changes nothing else",
    "closeveil": "dismisses a sheet and changes nothing else",
    "pdetail": "opens a detail view and changes nothing else",
    "pback": "returns from a detail view and changes nothing else",
    "texpand": "expands a row and changes nothing else",
}

# The hand-written half, and the only one. A control whose drawn label is a fixture value or a
# glyph gets its name from what the design says it is FOR, keyed on the mock's own
# `data-a`/`data-v`/`data-ctx` attributes. Every raw label survives into the emitted JSON beside
# the resolved name, so the mapping is auditable rather than asserted.
FALLBACK: dict[tuple[str, str], str] = {
    ("sel", "ctx:server"): "Server row → inspector",
    ("sel", "ctx:skill"): "Skill row → inspector",
    ("sel", "v:"): "Close inspector",
    ("sheet", "v:reg"): "Registry row → detail sheet",
    ("sheet", "v:held"): "Attention row → held-description review",
    ("sheet", "v:update"): "Attention row → update review",
    ("goto", "v:servers"): "Attention row → Servers",
    ("goto", "v:inbox"): "Attention row → Inbox",
    ("popover", ""): "Menu-bar status item",
    # Two controls in the design share `data-a="popover"` and draw no text: the status item in the
    # menu bar, and the popover's own ✕. Region is what separates them, and it is keyed first.
    ("popover", "region:.pop"): "Close popover",
}

# A row context menu labels one control two ways depending on the row's state — the same item
# reads "Keep warm" or "Stop keeping warm" — so the label cannot be the census name. The action
# can, because the mock routes both labels to one entry in its `A{}` table.
CTX_MENU: dict[str, str] = {
    "sel": "Context menu → Open in inspector",
    "warm": "Context menu → Keep warm",
    "scope": "Context menu → Only load in named projects…",
    "sheet:remove": "Context menu → Remove…",
    "sheet:history": "Context menu → Version history…",
}

# A label carrying a fixture version or count, renamed to what the design specifies rather than to
# what this fixture happens to show. A table rather than a regex because each is a judgement about
# which half of the string is the affordance.
OVERRIDES: dict[str, str] = {
    "Review 2.3.0…": "Review the held update…",
    "Promote 2.3.0": "Promote the held update",
    "Keep 2.2.0": "Keep the installed version",
    "Roll back to 2.1.0…": "Roll back to an earlier version…",
    "Show full diff (412 lines)": "Show full diff",
    "Remove fetch-pro": "Remove the server",
    "Update to 1.5.0": "Update to the held version",
    # The console draws four popup menus whose closed label is the value currently chosen, so the
    # drawn text moves with the fixture rather than naming the control.
    "Last 7 days": "Insights window",
    "Claude CLI \u00b7 haiku": "Analyst model",
    "Grok CLI \u00b7 grok-4.6 medium": "Second-opinion model",
    "Every 6 hours": "Analyst cadence",
}

# Classes the mock draws a DATA ROW with. A row is one affordance repeated per fixture item, so it
# is named by intent and counted once; without this the Servers board reports eight controls called
# `obscura`, `dossier`, `sift` … and the denominator becomes the fixture.
ROW_CLASSES = {"tr", "brk", "bandr", "card", "trow", "sf-card", "side-row", "hero"}

# ── THE SECOND SOURCE, AND WHY THERE HAS TO BE ONE ──────────────────────────────────────────────
#
# `campaign.json` names `design/mocks/prototype.html` as `designOfRecord` and the eleven surfaces
# above come from it. Three Mac surfaces are not in it AT ALL, because they were drawn after it:
# M22 added the Harnesses and Insights boards and M30 added the capability-document panel, and the
# same three are the ones `surface-reconcile.py` was written for after they shipped with no campaign
# surface. ORCHESTRATOR.md's Contract has already moved on — it names `design/mcp-router-console.html`
# as the design of record settled 2026-08-22 and the prototype as superseded, "cited only for
# surfaces not yet converted".
#
# Declaring nothing for those three would put three shipped Mac boards outside the denominator,
# which is precisely the failure this census exists to end. So each surface is sourced from the
# design that actually draws it, and which file that was is recorded per surface in the output.
# The disagreement between `campaign.json` and the Contract is real and is not this script's to
# settle; it is reported rather than papered over.
CONSOLE_SURFACES: list[tuple[str, str, list[tuple[str, str, str]]]] = [
    ("SURF-025", "Mac Harnesses board", [
        ("board:ideal", "BOARDS('ideal')", "#b-harnesses"),
        ("board:empty", "BOARDS('empty')", "#b-harnesses"),
        ("board:error", "BOARDS('error')", "#b-harnesses"),
    ]),
    ("SURF-026", "Mac Insights board", [
        ("board:ideal", "BOARDS('ideal')", "#b-insights"),
        ("board:empty", "BOARDS('empty')", "#b-insights"),
        ("board:error", "BOARDS('error')", "#b-insights"),
    ]),
    ("SURF-028", "Mac capability document panel — three tabs over one package", [
        ("sheet:readme", "SHEET('sh-readme')", "#sh-readme"),
    ]),
]

# The console routes every control through `data-act`, and its own dispatcher says what an
# unrecognised one does: `showNotification('MCP Router', 'That action is specified in the state
# matrix rather than wired up in this mock.')`. So an act with no entry in the console's ACTIONS
# table is message-only BY THE DESIGN'S OWN STATEMENT, and an act whose entry is a single
# `showNotification(…)` call is message-only because that is the whole of what it promises. Both
# are read out of the file rather than listed here, so this cannot drift from the design.
CONSOLE_MESSAGE_ONLY_PREFIXES = ("sheet:", "board:", "mdtab:")
CONSOLE_MESSAGE_ONLY_ACTS = {"act:close-sheet", "act:hide-notif", "act:toggle-sidebar",
                             "act:toggle-inspector", "act:settings", "act:close-settings",
                             "act:focus-search", "act:open-console"}

# Descendant text that is help, badge, timing or fixture rather than the control's name.
NOISE = ".t3,.t4,.lbl,.k,.m,.ev,.bg,.tag,.rk,.dl,.sb,.sw2,.pip,.dot,.sw,.msep,svg"

HARVEST = r"""(()=>{
  const CTX = (kind) => {
    const row = document.querySelector('[data-ctx="'+kind+'"]');
    if (!row) return;
    row.dispatchEvent(new MouseEvent('contextmenu',
      {bubbles:true, cancelable:true, clientX:120, clientY:160}));
  };
  // The console draws every board into the document and shows one; each board's empty and error
  // states are selected by a `data-state` attribute the mock's own state segment sets. Both are
  // driven here rather than through the page's own dispatcher, which lives inside an IIFE and is
  // not reachable from an evaluated expression.
  const BOARDS = (state) => document.querySelectorAll('.board').forEach(b => {
    b.classList.add('active'); b.dataset.state = state;
  });
  const SHEET = (id) => {
    const scrim = document.getElementById('scrim'); if (scrim) scrim.hidden = false;
    const sh = document.getElementById(id); if (sh) sh.hidden = false;
  };
  __SETUP__;
  if (typeof render === 'function' && __RERENDER__) render();
  const NOISE = __NOISE__;
  const own = (e) => {
    const c = e.cloneNode(true);
    c.querySelectorAll(NOISE).forEach(n => n.remove());
    // A segmented filter draws its count as a bare-integer child, so `All` reads `All8` and the
    // name moves with the fixture. Only a child whose whole text is an integer is dropped, which
    // leaves `Keep 2.2.0` and `Show full diff (412 lines)` intact for the override table.
    c.querySelectorAll('*').forEach(n => {
      if (/^\d+$/.test((n.textContent || '').trim())) n.remove();
    });
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  };
  const out = [];
  document.querySelectorAll(__REGION__).forEach(root => {
    root.querySelectorAll('button,[role=button],[data-a],input,select,summary').forEach(e => {
      const r = e.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return;
      const cls = ' ' + (e.className || '') + ' ';
      if (e.disabled || cls.includes(' dis ')) return;
      // A context-menu item carries `data-ctxa="action:value"` instead of the data-a/data-v pair
      // every other control uses, so the two spellings are normalised to one here.
      let action = e.getAttribute('data-a') || '', value = e.getAttribute('data-v') || '';
      const ctxa = e.getAttribute('data-ctxa');
      if (!action && ctxa) { const p = ctxa.split(':'); action = p[0]; value = p.slice(1).join(':'); }
      // The console spells the same thing `data-act="act:verify"` / `"sheet:reconcile"`, and
      // its markdown viewer spells its tabs `data-mdtab`. Kept whole, because the prefix is
      // what the console's dispatcher routes on.
      if (!action) action = e.getAttribute('data-act') ||
        (e.getAttribute('data-mdtab') ? 'mdtab:' + e.getAttribute('data-mdtab') : '') ||
        (e.getAttribute('data-board') ? 'board:' + e.getAttribute('data-board') : '');
      out.push({raw: (e.textContent || '').replace(/\s+/g,' ').trim().slice(0,120),
                own: (e.getAttribute('aria-label') || e.placeholder || own(e)).slice(0,80),
                action: action, value: value,
                ctx: e.getAttribute('data-ctx') || '',
                cls: (e.className || '').split(/\s+/).filter(Boolean),
                tag: e.tagName});
    });
  });
  return JSON.stringify(out);
})()"""


def resolve_name(row: dict, region: str) -> str | None:
    """The census name for one drawn element, or None if it is fixture data and not a control.

    Three routes, in this order, because each answers a question the next one cannot:
      * a context-menu item names itself two ways depending on row state, so it is named by action;
      * a data row's label IS the fixture, so it is named by what the design says it is for;
      * everything else is named by the label the design draws, which is what a case's `actuates`
        string should read like.
    """
    action, value, ctx = row["action"], row["value"], row["ctx"]
    classes = set(row.get("cls") or [])
    label = " ".join(row["own"].split())
    label = OVERRIDES.get(label, label)

    if region == ".ctx":
        return CTX_MENU.get(f"{action}:{value.split(':')[0]}") or CTX_MENU.get(action) or \
            (label if label else None)

    keys = [(action, f"region:{region}")]
    if ctx:
        keys.append((action, f"ctx:{ctx}"))
    if value:
        keys.append((action, "v:" + value.split(":")[0]))
    if action and not value:
        keys.append((action, "v:"))
    keys.append((action, ""))
    fallback = next((FALLBACK[k] for k in keys if k in FALLBACK), None)

    if ctx or (classes & ROW_CLASSES):
        # A row is one affordance repeated per fixture item. Named by the design's intent or
        # dropped — never by the tenant's data, which would make the denominator the fixture.
        return fallback

    # A name the design owns: two characters or more and short. The width is ten words and 60
    # characters because the design's Settings toggles run that long once the `.t3` help paragraph
    # under each is stripped — "Promote an update when the capability diff is empty" is a name, and
    # a narrower filter silently dropped it, reporting Settings as carrying two update toggles
    # where it carries three. Nothing here excludes a leading digit: the Discover board's window
    # filter is drawn "24h" / "7d" / "30d", and a leading-digit rule dropped all three. What a
    # fixture-shaped row is caught by is ROW_CLASSES above, which is the property that is actually
    # true of it.
    if 2 <= len(label) <= 60 and len(label.split()) <= 10:
        return label
    return fallback


def harvest(url: str, setup: str, region: str, rerender: bool) -> tuple[list[dict], str]:
    js = (HARVEST
          .replace("__SETUP__", setup or "0")
          .replace("__RERENDER__", "true" if rerender else "false")
          .replace("__NOISE__", json.dumps(NOISE))
          .replace("__REGION__", json.dumps(region)))
    r = subprocess.run(["obscura", "fetch", url, "--eval", js],
                       capture_output=True, text=True, timeout=180)
    line = next((l for l in reversed(r.stdout.splitlines()) if l.strip().startswith("[")), "")
    if not line:
        return [], ((r.stderr or r.stdout) or "no output").strip()[-300:]
    try:
        return json.loads(line), ""
    except json.JSONDecodeError as e:
        return [], str(e)


def console_message_only() -> set[str]:
    """Acts the console's own source says do nothing but put a message on screen.

    Read out of `design/mcp-router-console.html` rather than listed, because a hand-copied list of
    another file's handlers is a second thing to keep in step and this one would go quietly wrong.
    Two shapes count: a handler that is a single `showNotification(…)` call, and an act with no
    handler at all — the console's dispatcher sends those to `showNotification('MCP Router', 'That
    action is specified in the state matrix rather than wired up in this mock.')`, which is the
    design stating in words that the control's whole effect is a message.
    """
    src = CONSOLE.read_text(errors="replace")
    declared = set(re.findall(r"'(act:[a-z-]+)':\s*function", src))
    used = set(re.findall(r'data-act="(act:[a-z-]+)"', src))
    notify_only = {m.group(1) for m in
                   re.finditer(r"'(act:[a-z-]+)':\s*function \(\) \{ showNotification\([^;]*\); \}", src)}
    return notify_only | (used - declared) | CONSOLE_MESSAGE_ONLY_ACTS


def classify(action: str, source: str, console_msg: set[str]) -> bool:
    if source == "console":
        return action.startswith(CONSOLE_MESSAGE_ONLY_PREFIXES) or action in console_msg
    return action in MESSAGE_ONLY_ACTIONS


def main() -> int:
    if not shutil.which("obscura"):
        print("obscura is not on PATH — no verdict printed, because a count from an instrument "
              "that did not run is not evidence", file=sys.stderr)
        return 3

    console_msg = console_message_only()
    # (surface id, title, source, [(state, url, setup, region, rerender), …])
    plan: list[tuple[str, str, str, list]] = []
    for sid, title, states in SURFACES:
        plan.append((sid, title, "prototype", [
            (st, f"file://{MOCK}?{q}&only=mac", setup, region,
             bool(setup) and not setup.startswith("CTX("))
            for st, q, setup, region in states]))
    for sid, title, states in CONSOLE_SURFACES:
        plan.append((sid, title, "console", [
            (st, f"file://{CONSOLE}", setup, region, False) for st, setup, region in states]))

    result: dict[str, dict] = {}
    broken: list[str] = []
    for sid, title, source, states in plan:
        controls: dict[str, dict] = {}
        dropped: list[str] = []
        for state, url, setup, region, rerender in states:
            rows, err = harvest(url, setup, region, rerender)
            if err or not rows:
                broken.append(f"{sid}/{state}: {err or 'no element matched ' + region}")
                continue
            for row in rows:
                name = resolve_name(row, region)
                if name is None:
                    dropped.append(row["raw"][:60])
                    continue
                c = controls.setdefault(name, {"name": name, "action": row["action"],
                                               "states": [], "rawLabels": []})
                if state not in c["states"]:
                    c["states"].append(state)
                if row["raw"] not in c["rawLabels"]:
                    c["rawLabels"].append(row["raw"][:60])
        ordered = [controls[k] for k in sorted(controls)]
        message_only = [c["name"] for c in ordered
                        if classify(c["action"], source, console_msg)]
        result[sid] = {
            "title": title,
            "source": str((MOCK if source == "prototype" else CONSOLE).relative_to(ROOT)),
            "states": [st[0] for st in states],
            "controls": [c["name"] for c in ordered],
            "messageOnly": message_only,
            "detail": ordered,
            "droppedAsRowData": sorted(set(dropped)),
        }
        print(f"{sid}: {len(ordered)} control(s) specified across {len(states)} state(s), "
              f"{len(message_only)} message-only  [{source}]")
        for c in ordered:
            mark = "  ·message-only" if c["name"] in message_only else ""
            print(f"    {c['name']:<46} [{c['action'] or '—'}] {','.join(c['states'])}{mark}")
        if not ordered:
            broken.append(f"{sid}: no controls at all")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "designOfRecord": str(MOCK.relative_to(ROOT)),
        "secondSource": str(CONSOLE.relative_to(ROOT)),
        "secondSourceReason": "The prototype predates the Harnesses board, the Insights board and "
                              "the capability-document panel; ORCHESTRATOR.md's Contract names the "
                              "console as the design of record settled 2026-08-22.",
        "surfaces": result}, indent=2) + "\n")
    total = sum(len(v["controls"]) for v in result.values())
    msg = sum(len(v["messageOnly"]) for v in result.values())
    print(f"\nexamined={len(plan)} surface(s) · {total} control(s) specified · "
          f"{msg} message-only · wrote {OUT.relative_to(ROOT)}")
    if broken:
        print("\nSTATES THAT RETURNED NOTHING — the census is not writable from this run:",
              file=sys.stderr)
        for b in broken:
            print(f"  · {b}", file=sys.stderr)
        return 2

    if "--set-controls" in sys.argv:
        # A DELIBERATE FLAG, never a side effect. A gate that rewrote the registry on every run
        # would leave the tree dirty and the next `git merge` would refuse — measured in this
        # repository on 2026-08-27 and written into `registry-drop-gate.py`'s own header. Reading
        # the census and writing the denominator are separate acts.
        inv = json.loads(INVENTORY.read_text())
        written = 0
        for srec in inv.get("surface", []):
            found = result.get(srec["id"])
            if not found:
                continue
            srec["controls"] = found["controls"]
            srec["controlsMessageOnly"] = found["messageOnly"]
            srec["controlsSource"] = found["source"]
            written += 1
        # `ensure_ascii=False` because this file holds its em-dashes raw. Writing it back escaped
        # rewrites 120 lines that did not change, which buries the census in a diff nobody can read.
        INVENTORY.write_text(json.dumps(inv, indent=2, ensure_ascii=False) + "\n")
        print(f"--set-controls: wrote controls onto {written} surface(s) in "
              f"{INVENTORY.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
