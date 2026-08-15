# plan-P4 — Derive the manifest rows, and fix the directory-dependent normaliser

Spec: `planning/specs/spec-P4.md`. Branch `ai/p4`, worktree `.worktrees/P4`.

Two files change, both mine this wave:

- `scripts/acceptance/parity-manifest-check.sh` — three new reconciliations (cli, mcp, cited ids)
- `scripts/acceptance/parity-fixture.sh` — the normaliser

One file changes by one line: `scripts/acceptance/parity-gate.sh`, because manifest-check gains a
new reason to exit 2 and the gate's current message for that would be wrong.

**No router source changes. No `surface.tsv` row is added, edited or deleted.** If a new check
demands a row that does not exist, that is a finding to report, not a row to write — the whole item
is about rows that appear and disappear without anyone noticing.

---

## Step 1 — `parity-manifest-check.sh`: the CLI reconciliation

Placed after the control section, before the fixture section, so the file reads source-group by
source-group.

**Extract.** The switch block only:

```bash
CLI_SWITCH="$(awk '/switch \(cmd\) \{/,/^  \}$/' "$INDEX_TS")"
```

Then fall-through **groups**, one per line, labels space-separated. A `case` line joins the current
group; any other line that is not blank and not a comment closes it. `default:` closes it, which is
what we want.

```awk
BEGIN { gi = 0 }
/^[[:space:]]*case[[:space:]]/ {
  if (match($0, /\047[^\047]*\047/)) {
    lab = substr($0, RSTART + 1, RLENGTH - 2)
    group[gi] = (gi in group ? group[gi] " " : "") lab
  }
  next
}
/^[[:space:]]*$/                     { next }
/^[[:space:]]*(\/\/|\*|\/\*)/        { next }
{ if (gi in group) gi++ }
END { for (i = 0; i <= gi; i++) if (i in group) print group[i] }
```

Against today's source this yields nine lines:
`import` · `index refresh` · `serve` · `status` · `tools` · `auth` · `usage` · `watch` ·
`help --help -h`.

**Declared aliases.** One list in the script, with its reason:

```bash
# A case label that is not a manifest row must be DECLARED here. Nothing is classified by
# spelling: the first draft of this check called any label starting with "-" a flag and let it
# through, which meant `case '--serve':` could add a CLI spelling the gate never compares and
# never counts. An undeclared label is an error, so new CLI surface cannot arrive silently.
CLI_ALIASES="--help -h"
```

**Reconcile**, five ways:

1. every label is a `cli` row subject or a declared alias — else
   *"`src/index.ts` dispatches \"X\", which is neither a `cli` manifest row nor a declared alias"*
2. every `cli` row subject is a label — else *"the manifest carries cli row \"X\", which
   `src/index.ts` does not dispatch"*
3. every declared alias is a label — else *"declared alias \"X\" is not a case label; the
   declaration is stale"*
4. every group containing an alias contains a label that is a row — else *"case group \"…\" is all
   aliases, so this CLI surface has no row to represent it"*
5. every verb advertised in `usage()` is a label:
   `sed -n "s/^[[:space:]]*mcp-router \([a-z][a-z-]*\).*/\1/p"` → today
   `import index serve status tools auth usage watch`. One direction only, per A3.

**The independent guard** (A6), in the shape the control section already uses. The control section
counts dispatch lines because its extractor reads three idioms and could miss a fourth. The CLI
analogue is a verb dispatched *outside* the switch:

```bash
outside="$(grep -cE "cmd ===|cmd ==" "$INDEX_TS")"
[ "$outside" = 0 ] || note "src/index.ts compares cmd outside the switch …"
```

Measured on today's source: `0`. `cmd` is assigned once (`process.argv[2]`) and read once.

Zero labels extracted is an **environment failure**, exit 2, message naming the switch shape —
never a clean report against an empty list.

---

## Step 2 — `parity-manifest-check.sh`: the MCP reconciliation

**Paths, from `src/router.ts`:**

```bash
literals="$(sed -n "s/.*url\.pathname === '\([^']*\)'.*/\1/p" "$ROUTER_TS")"      # /health /status
mcp_path="$(sed -n "s/^const MCP_PATH = '\([^']*\)';.*/\1/p" "$ROUTER_TS")"       # /mcp
```

`/mcp` is reached through `url.pathname !== MCP_PATH`, so it is resolved through the constant rather
than as a literal — asserted explicitly: if `url.pathname !== MCP_PATH` is not present, or
`MCP_PATH` does not resolve, that is an environment failure naming the changed shape.

**The count guard:** `grep -cE "url\.pathname [!=]== " "$ROUTER_TS"` is `3` today and must equal the
number of extracted paths. A fourth comparison that the extractor cannot read makes these disagree.

**The control delegation is asserted, not extracted.** `isControlPath(url.pathname)` (:258) hands a
whole family of paths to `handleControl`; those carry `control` rows and must not also demand `mcp`
rows (A4, and A10 — the denominator does not move). The check asserts the call is still there:

```bash
grep -q "isControlPath(url.pathname)" "$ROUTER_TS" || note "router.ts no longer delegates …"
```

Without this the delegation could be deleted and the `mcp` reconciliation would stay perfectly
green while sixteen `control` rows described a surface `router.ts` had stopped routing to.

**Methods, from the SDK — not from a table:**

```bash
symbols="$(grep -oE "setRequestHandler\([A-Za-z]+" "$ROUTER_TS" | sed 's/.*(//' | sort -u)"
```
→ `CallToolRequestSchema`, `ListToolsRequestSchema`. Each is resolved by asking the installed SDK
for the literal its schema pins:

```bash
node -e 'const t=require("@modelcontextprotocol/sdk/types.js");
         for (const s of process.argv.slice(1)) {
           const v = t[s] && t[s].shape && t[s].shape.method && t[s].shape.method.value;
           if (!v) { console.error("unresolved:" + s); process.exit(3) }
           console.log(v)
         }' $symbols
```

Verified by hand: `ListToolsRequestSchema -> tools/list`, `CallToolRequestSchema -> tools/call`. A
symbol that does not resolve exits 2 naming it — never skipped, because a skipped handler is a
JSON-RPC method with no row.

**Reconcile** the union (`/health /status /mcp tools/list tools/call`) against the `mcp` rows, whose
subjects are compared on their last whitespace-separated token (`GET /health` → `/health`), both
directions.

**Environment:** `node` missing, or the SDK unresolvable, exits 2 with a message naming
`npm install`. That is the honest answer and not a degrade.

---

## Step 3 — `parity-manifest-check.sh`: cited row ids (A11)

The file already resolves cited *tests* and cited *scripts* on the stated principle that a citation
has to keep being true. Row ids are cited in notes and are not resolved:

```
control-auth-post      note names control-auth-post-http
control-auth-post-http note names control-auth-post
div-r1-d3              note names div-r1-d3-control
```

Scan every note for tokens of row-id shape and assert each is a live id:

```bash
grep -oE '\b(control|fixture|divergence|div|pool|mcp|cli|install|state|log)-[a-z0-9]+(-[a-z0-9]+)*\b'
```

Measured across all 83 notes, that regex returns exactly four distinct tokens: the three ids above
and **`mcp-router`**, the product's own name, in the notes of `cli-auth` and `install-claude-json`.
So one declared exclusion, with its reason:

```bash
# `mcp-router` is the product, not a row. Declared rather than pattern-excluded so that a token
# which merely looks like an id is a decision someone made, not a silence.
NOT_ROW_IDS="mcp-router"
```

This is what closes §2.5: deleting `control-auth-post-http` now breaks the citation in
`control-auth-post`'s note, which is a `note` and therefore exit 1.

---

## Step 4 — `parity-fixture.sh`: the normaliser

Four edits inside the Python heredoc.

**4a. Structural project normalisation, before the substitution table.** The contract is
`src/usage.ts:305` — `projectOf = cwd ? basename(cwd) : undefined`. Every `project` in the corpus
has a sibling `cwd`: in `usage.json` records, and in `usage-summary.json`'s `projectNames` entries,
which are `{cwd, project, calls}` objects.

The pass **collects** the project values that are legitimate and then substitutes those literals in
the text. It deliberately does not dump the parsed document back out: the comparison stays
byte-level everywhere else, so whitespace and member-order differences keep being caught.

```python
def legitimate_projects(node, out):
    """A project is normalisable only where it is exactly basename(cwd) of its own object and is
    non-empty. Anything else is a real change to what the reference reports and must survive to the
    comparison — a whole cwd in the project field, or "/" or "." or "", each of which an earlier
    path rule would otherwise rewrite into something that matches the recording."""
    if isinstance(node, dict):
        cwd, proj = node.get('cwd'), node.get('project')
        if isinstance(cwd, str) and isinstance(proj, str) and proj \
           and proj == posixpath.basename(cwd.rstrip('/')) :
            out.add(proj)
        for v in node.values():
            legitimate_projects(v, out)
    elif isinstance(node, list):
        for v in node:
            legitimate_projects(v, out)
```

then, for each collected value,
`re.sub(r'"project"\s*:\s*"' + re.escape(value) + '"', '"project":"<project>"', text)`.

An unparseable body skips the pass, leaves `project` unnormalised, and mismatches. It fails closed.

**4b. Delete the `"project":"[A-Za-z0-9]+"` entry.** Replaced by 4a. Leaving it would re-admit
everything 4a exists to reject.

**4c. Delete the `projectNames` entry.** Its comment claims it preserves array length; it was
written for an array of strings and the corpus holds an array of objects, so it splits
`{"cwd":…,"project":"F3","calls":1}` on internal commas and emits three markers for one entry —
**substituting `"<project>"` for the `calls` count.** With 4a each entry's `project` normalises
against its own `cwd`, the `cwd` normalises through the path rules, and the array length and every
`calls` value compare honestly for the first time.

**4d. Two character classes in the same table:**

```python
(r'/Users/[^"]*?/mcp-router/\.worktrees/[^"/]+', '<repo>'),   # was [A-Za-z0-9]+
(r'"cwd":"[^"]+"',                               '"cwd":"<cwd>"'),   # was [^"]*
```

One path **segment** for the worktree name — `[^"]+` there would swallow the rest of the path and
collapse real structure. `+` not `*` for `cwd`, the lesson the `hash` entry already records.

---

## Step 5 — `parity-gate.sh`, one line

manifest-check can now exit 2 for a reason other than an unreadable manifest. The gate prints
*"the manifest could not be read, so there is no surface to report against"*, which would be wrong
for a missing SDK. Changed to *"the manifest could not be checked — see above"*; manifest-check's
own stdout is already printed unredirected, so the precise reason is on screen.

---

## Step 6 — mutations, each proven red then green

Run from `.worktrees/P4`. Exit codes captured directly, never through a pipe. **Every mutation is
restored by re-applying the inverse edit, never by `git checkout --`.** Manifest-check reads
`.ts` source rather than `dist/`, so no mutation here needs a rebuild — except M12, which mutates
the installed SDK.

| # | Mutation | Must redden | Proves |
|---|---|---|---|
| M1 | delete the `cli-import` row | manifest-check | A1 — **deleting a cli row can no longer raise the figure** |
| M2 | add a `cli` row `doctor` | manifest-check | A1 the other direction |
| M3 | `case 'tools':` → `case 'toolz':` in `src/index.ts` | manifest-check, both directions at once | A1 |
| M4 | add `case '--serve':` falling through with `serve` | manifest-check | A1 — grok's hole; the old `-` heuristic passed this |
| M5 | add `case '-x': case '-y': return usage();` (alias-only group) | manifest-check | A2 |
| M6 | remove `-h` from source, leave it declared | manifest-check | A2, stale declaration |
| M7 | delete `mcp-health` row | manifest-check | A4 |
| M8 | add an `mcp` row `GET /metrics` | manifest-check | A4 the other direction |
| M9 | delete the `ListToolsRequestSchema` handler | manifest-check | A4 |
| M10 | delete `isControlPath(url.pathname)` | manifest-check | A4, the delegation assertion |
| M11 | add `if (cmd === 'doctor') return cmdIndex();` **above an intact switch** | manifest-check | A6 — the fourth-shape hole |
| M12 | change `tools/list` to `tools/listv2` **in the installed SDK** | manifest-check, naming `tools/listv2` | A5 — the name is read from the SDK, not a table |
| M13 | delete `control-auth-post-http` | manifest-check, citation broken | A11 — §2.5, the hole the review found |
| M14 | in a captured body, set `project` to the whole `cwd` | the fixture lane | A7 — the over-normalisation the wider class would have hidden |
| M15 | in a captured body, set `project` to `""` | the fixture lane | A7, the `+` constraint |
| M16 | in a captured body, change a `projectNames[0].calls` count | the fixture lane | A12 — invisible before this change |

M14–M16 mutate the **captured** side (the scratch copy), never the recorded fixtures: a lane that
edits its own oracle proves nothing. Implemented by running the capture, mutating `$WORK`, and
re-comparing — driven from a throwaway harness script, not committed.

Any mutation that cannot redden is a finding about the check's design and gets re-aimed, not
swapped for an easier one.

---

## Step 7 — the numbers, from both places

The whole point of the item, so it is measured the same way twice.

1. `bash scripts/acceptance/parity-gate.sh` from `/Users/lukerhodes/Dev/mcp-router`
2. `bash scripts/acceptance/parity-gate.sh` from `/Users/lukerhodes/Dev/mcp-router/.worktrees/P4`

Recorded for each: exit code, proven/total, blocked, DIVERGED **and which rows**, and the per-group
table. A9 is judged on the **`fixture` group's per-row verdicts being identical** and on
`fixture-usage` reading proven from the repo root — not on the totals, which §2 shows already agree
while D-o is live.

Expected, stated in advance so a surprise is visible: root goes 73 → **74 of 83** with the
`fixture usage` divergence gone; the worktree reads the same 74, since it was already normalising.
Denominator stays **83**. If either number moves any other way, that is reported, not reconciled.

`D-p4-a` may put `div-r2-d6` red in either run under load. If it does, it is reported as `D-p4-a`
with the 8-of-8 isolated evidence beside it, and the run is repeated once — **not repeated until
green**, and the repeat is disclosed either way.

---

## Step 8 — gates

Each captured directly, `cmd > /tmp/f.txt 2>&1; echo $?`, never through a pipeline.

- `bash -n` on all three changed scripts
- `shellcheck` if present; if absent, said so rather than implied
- `scripts/acceptance/parity-manifest-check.sh` alone, exit 0, from **both** directories
- `scripts/acceptance/parity-lane-selftest.sh` — the harness's own self-test
- `make lint` — exit code checked, because swiftformat runs first and short-circuits, so
  "0 violations" from the swiftlint half is not a pass
- `make test`

No Swift source changes, so `make build-mac` / `test-ios` are **not** run and that is stated rather
than implied. The acceptance surface for this item is the parity harness; there is no UI, so no
screen is driven and no app is launched.

---

## Step 9 — evidence and commit

`planning/evidence/P4-acceptance.md`: the before pair, the after pair, the sixteen mutations with
their exit codes, the gates, the review verdicts and their lane.

`spec-P4.md` and `plan-P4.md` stay in the **main tree, uncommitted**. Only
`scripts/acceptance/*.sh` and the evidence file are committed on `ai/p4`. Commit with
`git commit -F`, never `-m` with backticks in the message. No push, no merge.
