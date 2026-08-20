# R7: is this harness actually routed, and what is it duplicating

**Category:** router · **Brief:** `planning/features-to-triage/R7-harness-reconciliation.md`
**Depends on:** R3 (control API) — merged. **Related:** R6 (child PATH), M22 (Harnesses board).

The README's headline — 190 processes down to 0 at rest — is a claim about one harness. This
spec makes "is this harness actually routed, and what is it duplicating" a question the shipped
binary answers, for every harness whose config it can read, from evidence rather than from
belief. It builds the detection and the diff. **It writes no harness config**, and §7 says why
that is the boundary rather than an unfinished half.

---

## 1 · What was measured, and by what instrument

Everything in this section was taken on the author's machine on **2026-08-21**, read-only. The
brief's own table was taken on 2026-08-15 and four of its rows have since moved, so it is
restated rather than cited.

### 1.1 · The harness configs

| Harness | Binary | Config | Entries | Router entry | State |
|---|---|---|---|---|---|
| Claude Code | `claude` | `~/.claude.json` (298 KB) | 3 global, 8 project-scoped | `router` `type:http` `http://127.0.0.1:8879/mcp` | wired via HTTP, **1 duplicate** |
| Claude Desktop | — | `~/Library/Application Support/Claude/claude_desktop_config.json` | 0 | none | not wired |
| Codex CLI | `codex` 0.146.0 | `~/.codex/config.toml` (944 KB) | 5 `[mcp_servers.*]` | none | **not wired**, 1 overlap |
| Cursor | `cursor-agent` 2026.08.11 | `~/.cursor/mcp.json` (22 B) | 0 | none | not wired |
| Gemini / Antigravity | `agy` 1.1.17 | `~/.gemini/settings.json` | 18 | `router` → `npx -y mcp-remote http://127.0.0.1:8879/mcp` | **wired via a stdio shim**, **12 duplicates** |
| grok | `grok` 1.0.5 | `~/.grok/config.toml` | 3 `[mcp_servers.*]` | `[mcp_servers.router] url = "http://127.0.0.1:8879/mcp"` | wired via HTTP, **1 duplicate** |
| opencode | `opencode` 1.0.169 | `~/.config/opencode/opencode.json` | — | — | config absent |

The router itself was running with **13 upstreams** and 91 tools (`GET /status` on :8879).

**Three of those rows are new since the brief and two of them contradict it.**

- The brief recorded Claude Code as "1 router entry — working as designed". It carries **three**
  today: the router, a direct `pocketsmith` HTTP entry, and a direct `namecheap` stdio entry —
  and `namecheap` is a server the router already fronts. The one harness the brief exempted is
  now in the duplicate state itself. That is the drift the brief's own rule 2 predicted, observed
  six days later on the machine the brief was written on.
- **grok was never audited** and is wired via HTTP already, carrying one duplicate (`mobbin`).
- Codex has 5 entries, not 7, and no router entry at all.

### 1.2 · The transport question the brief left open

The brief's closing line — "which harnesses genuinely speak streamable HTTP is the first thing
the research panel was asked" — has no answer in this repository: `planning/deep-research/` is
empty. It was established here instead, by probing the **shipped binaries on this machine**.
Each row below states its instrument, because a claim about another program's capability is
worth exactly what produced it.

| Harness | Streamable HTTP | Provenance | Instrument |
|---|---|---|---|
| Claude Code | yes | **measured, end to end** | `~/.claude.json` carries `type:http`, and this repository's own agent session reaches every routed upstream through it |
| Codex CLI 0.146.0 | yes | **measured, on the binary** | `codex mcp add <NAME> --url <URL>` → *"URL for a streamable HTTP MCP server"*; binary links `rmcp-1.8.0/src/transport/streamable_http_client.rs`; TOML keys `url`, `bearer_token_env_var`, `http_headers` |
| Cursor 2026.08.11 | yes | **measured, on the binary** | shipped bundle contains `{…type: <url present> ? "streamableHttp" : "stdio"…}` keyed off `url` in `~/.cursor/mcp.json` |
| Gemini / Antigravity `agy` 1.1.17 | yes | **measured, on the binary** | embeds `mcp.StreamableClientTransport` and `mcp.StreamableHTTPConnector` from the Go MCP SDK; MCP-server config struct carries `json:"command"` … **`json:"httpUrl"`** … `json:"headers"` … `json:"timeout"` |
| grok 1.0.5 | yes | **measured, on the binary and in use** | links `rmcp-2.1.0/.../streamable_http_client.rs`; carries its own doc string `[mcp_servers.my-streamable-server]`; and is wired that way right now |
| Claude Desktop | no | **taken on documentation** | not installed with a config here; no binary was probed |
| opencode 1.0.169 | unknown | **not established** | no config present, and the launcher is a shim whose bundle was not probed |

**The brief's premise is false for the harness it was written about.** Rule 3 says *"`mcp-remote`
is how a harness with no HTTP MCP transport reaches the router at all, so it is not simply a
mistake"*. `agy` 1.1.17 ships a streamable-HTTP MCP client and a config key for it. The shim in
`~/.gemini/settings.json` is not a workaround for a missing transport; it is a stale wiring
choice, and it is removable.

**What none of this establishes**, stated rather than implied: probing a binary for a symbol and
a config key proves the code path is *present*, not that a given endpoint would *connect*. The
only end-to-end measurement here is Claude Code's. Every other "yes" is a capability claim about
a shipped artifact, and §3 carries that distinction into the type rather than leaving it in prose.

### 1.3 · The duplicate count, computed rather than eyeballed

Router upstreams: `ref-tools-mcp ai-elements namecheap docker-mcp dossier google-search
media-gen-pro yt-transcript sift lifeline obscura mobbin atlas-admin`.

Against Gemini's 18 entries: **11 match by name**, and **one more matches by config identity
under a different name** — Gemini's `Ref` and the router's `ref-tools-mcp` are both
`npx -y ref-tools-mcp@3.0.3` with the same env key, and both hash to `30da6798334b2466` under
the existing `UpstreamHash`. Twelve, not the brief's ten.

Against grok's 3: `mobbin` matches **by name and not by identity** — the router fronts
`https://api.mobbin.com/mcp`, grok declares `https://mcp.mobbin.com/mcp`.

Those two rows are the argument for §4's two-basis rule, and they point opposite ways: name-only
matching misses `Ref`, identity-only matching misses `mobbin`. Neither basis alone is correct on
this machine, so both run and **each duplicate carries the basis that found it**.

---

## 2 · What ships

1. A reconciliation engine in `RouterCore` that, given the harness configs on disk and the
   router's own upstream set, answers per harness: how it is routed, what it duplicates, and
   whether it could speak HTTP.
2. Two harnesses added to the reader that it could not previously see: **Gemini CLI** and
   **grok**. Gemini is the brief's entire subject and was absent from `MCPClient`.
3. `mcp-router harnesses` — the verb that makes §1 reproducible from the shipped binary.
4. A `ReconciliationPlan` that names every entry a fix would remove and the entry it would add,
   and renders it as a diff. **Nothing applies it.**
5. A red-green acceptance lane and a lint gate that keeps the write seam empty.

---

## 3 · The model: three axes, not four states

The brief's acceptance asks the app to state *"which of: not wired · wired via HTTP · wired via
a stdio shim · wired but carrying duplicate direct upstreams"*. Those four are not alternatives.
Gemini is simultaneously the third and the fourth; Codex is the first while carrying an overlap.
A single four-valued enum cannot hold the machine this spec was written on.

So three independent axes are recorded, and the brief's four-way answer is **derived** from them:

```
HarnessRoute      .notWired | .directHTTP(url) | .stdioShim(bridge, url)
duplicates        [Duplicate]  — each with the basis that found it
HTTPCapability    .measured(binary, probe, on) | .documented(source) | .unknown
```

`HarnessReport.summary` collapses the first two into the brief's four cases, with duplicates
taking precedence over the route when the harness is wired, and the route surviving inside that
case so nothing is lost. The acceptance criterion is met by a value the type can produce; the
underlying report is the thing the board in M22 will draw.

**This shape was not chosen alone.** The question the brief handed to this item — whether the
shim is its own state or a qualification on "routed" — was put to `gpt-5.6-sol` at high effort,
out of family, with §1.2's measurements attached and the two options in the brief's own words.
Its answer, quoted in `planning/evidence/R7-review-codex.md`: pick the distinct state, *"it adds
a child process — the exact overhead the router is meant to eliminate. Calling it merely 'routed'
hides an actionable defect"*; and, unprompted, the same orthogonal decomposition — *"duplicate
direct upstreams can coexist with either HTTP or shim routing — it is not truly an alternative
transport state"*. It contributed one thing this spec did not have: **capability as a separate
three-valued field that changes the remedy rather than the state.** Where capability is
`.measured`, the shim's remedy is "this harness speaks `httpUrl`; switch and drop the shim".
Where it is `.unknown`, the state is identical and the remedy becomes "check whether this
harness speaks streamable HTTP" — which is the only honest thing to say about opencode. That
refinement is taken, and it is why `HTTPCapability` carries its provenance in the case rather
than in a comment.

**On §6 of `DESIGN.md` — no number the router does not observe.** Every figure this item emits
is counted from a file the binary read in that run: entries, duplicates, overlaps. Nothing is
extrapolated into a process count or a memory figure. `HTTPCapability` is not a number and not
an observation by the router: it is a recorded measurement of another program, and the case name
says who took it and when, so a reader can tell `.measured` from `.documented` without trusting
this document.

---

## 4 · Detection rules

**Route.** A harness is wired when one of its entries points at *this router's endpoint*, which
is decided **by URL and never by name**:

- `.directHTTP` — an entry whose `url` has a loopback host (`127.0.0.1`, `localhost`, `::1`,
  `[::1]`) and this router's port.
- `.stdioShim` — a **stdio** entry, any of whose `command` or `args` is such a URL. The bridge is
  named from the first argument that is neither a flag nor the URL (`mcp-remote`), falling back
  to the command's last path component. This catches `supergateway`, `mcp-proxy` and a
  hand-rolled bridge as readily as `mcp-remote`, because the evidence is the endpoint in the
  argument list, not a package name on an allowlist.
- `.notWired` — neither.

`SelfReference.isSelfReference` is deliberately **not** reused. It returns true for the bare name
`router` or `mcp-router` with no URL at all, which is right for `import` — never adopt a thing
called router — and wrong here, where the question is where the harness actually connects. A
harness entry named `router` pointing at some other host is not wired, and this item must say so.
The loopback host set is shared with `SelfReference` so the two cannot drift apart.

**Duplicates.** Each of a harness's non-router entries is compared against the router's upstream
set on two bases, and the first that matches is recorded:

- `.name` — byte-equal names. The router's names are `[A-Za-z0-9_-]+` and matching is
  case-sensitive, so `Ref` and `ref` are different servers, which is what both files mean.
- `.identity` — equal `UpstreamHash.hash`, which is the existing config-identity digest over
  transport, command, args, cwd and sorted env, and which excludes `name` by design. This is
  what catches a duplicate that has been renamed.

An entry the harness declares that `ServerParser` cannot parse is reported as **unparsed** and
is never silently counted as "no duplicate" — an entry nobody could read is not evidence of
absence.

For a harness that is **not wired**, the same overlaps are computed and reported under the word
*overlap* rather than *duplicate*: nothing is being duplicated when there is no route, and the
number means "what adopting this harness would consolidate".

---

## 5 · The verb

`mcp-router harnesses [--port N] [--host H] [--config PATH] [--json]`

The flags are the ones every other verb takes, resolved by the same `Flags` and
`ConfigLoader`; the router home comes from `MCP_ROUTER_HOME` as it does everywhere else,
rather than from a flag this verb alone would carry.

Reports every harness in `MCPClient.allCases`, in fixed order. Human output is one block per
harness naming the state, the path, the counts, and the overlapping names in the order the
harness declares them. `--json` emits the same via `JSStringify`.

Exit status is **0 whenever the measurement succeeded**, including when harnesses are
misconfigured. A configuration finding is not a failure of the command that found it, and a
non-zero exit here would put every gate that ever calls it into a state where a true report
looks like a broken tool. Exit 1 is reserved for the router's own config being unreadable — the
one case where the right-hand side of every comparison is missing and no answer can be given.

**It is dispatched before `dispatchReferenceVerb`, exactly as `install-entry` is**, so the arm
list that mirrors `src/index.ts` stays one-to-one and readable against it. It is absent from
`Copy.usage` for the same reason `install-entry` is: `cli-help` is a proven parity row comparing
all four help arms at both binaries, and a verb in the usage block that the reference does not
have would turn it red. `parity-cli.sh`'s unknown-verb arm uses the literal `not-a-real-verb`,
which is unaffected.

**No control-API route, and no board.** Adding one would diverge from `src/control.ts` and owe a
new parity row, and the surface that would draw it is M22, which is untriaged. Deferred as
**R7-C1** (§8).

---

## 6 · Parity

`RouterCore/Discovery` has no counterpart in `src/` and never has: the TypeScript reference reads
`~/.claude.json` for `import` and `watch` and has no client-discovery layer at all. This item adds
only to `Discovery` and to the Swift-only verb arm, so **no row of `planning/parity/surface.tsv`
changes and `src/` is not touched**. That is not a licence taken; it is the pre-existing shape of
this subsystem, and R4-C2 — retiring `src/*.ts` — is held for reasons unrelated to it.

The new lane `scripts/acceptance/r7-harness-reconciliation.sh` is **not** named `parity-*.sh`, so
it is outside `parity-manifest-check.sh`'s LANES membership rule, exactly as `r6-child-path.sh`
is. It is dispatched from `make acceptance`, so D-p3-a's failure — a lane script nothing runs —
does not recur here.

---

## 7 · The boundary: this item does not write a harness config

The configs this reads are the developer's live ones: `~/.claude.json` at 298 KB and
`~/.codex/config.toml` at 944 KB, both holding working state and credentials. Every fixture in
this item's tests and its acceptance lane is created under a scratch directory. Nothing in
`app/Sources` opens a harness config for writing.

`ReconciliationPlan` is the seam, and it is deliberately inert: it names the entries a fix would
remove and the entry it would add, and it renders a diff. There is no `apply`, no writer
protocol and no conformer. `scripts/lint/no-harness-config-writes.sh` runs in `make lint` and
fails if any file under `app/Sources` names a harness config path in a writing position, so the
seam cannot gain a caller without someone deleting the gate that says it should not.

Two reasons, and only the first is about safety. Mutating a developer's live agent configuration
is not a change a fleet runner makes unattended. And the brief's own framing is that **config
writing is the easy half** — the diff is the product. An engine that can say "Gemini carries
twelve duplicates, here they are, here is the file that would fix it" has delivered the item;
the write is R7-C2's, behind a human.

---

## 8 · Deferred children

| ID | Title | Why not here |
|---|---|---|
| **R7-C1** | The Harnesses board and the control-API route behind it | Needs a `GET /harnesses` route, which diverges from `src/control.ts` and owes a parity row; the surface that draws it is M22, untriaged |
| **R7-C2** | Apply a reconciliation plan to a harness config, behind a human | §7. Needs per-dialect writing, undo, and a confirmation surface — and it is what the brief puts out of scope |
| **R7-C3** | opencode's transport, unestablished | No config on this machine and the launcher is a shim; its capability is `.unknown` and is displayed as unknown rather than guessed |
| **R7-C4** | Project-scoped harness entries | `~/.claude.json` carries 8 more entries across 5 projects, and Codex has `[projects.*]`. This item reports the global scope only, and says so in the output rather than counting a project entry as absent |

---

## 9 · Acceptance

| ID | Criterion | Proved by |
|---|---|---|
| A1 | For each supported harness the binary states not wired / wired via HTTP / wired via a stdio shim / wired with duplicates | `HarnessReport.summary`; unit tests over all four; the verb printing all seven harnesses |
| A2 | Duplicates are found by comparing against the router's own upstream set and the overlapping names are named | `HarnessReconciliation.duplicates`; a test asserting the names, not just the count |
| A3 | **Red-green:** a fixture harness config carrying three duplicates reports three, and zero after reconciliation | `scripts/acceptance/r7-harness-reconciliation.sh` — one fixture, two runs |
| A4 | §1's measurement is reproducible from the shipped binary, not from ad-hoc shell | `mcp-router harnesses` against the real configs, recorded in `planning/evidence/R7-acceptance.md` |
| A5 | Route detection is by endpoint, so a harness entry *named* `router` pointing elsewhere is not wired | unit test |
| A6 | A renamed duplicate is caught, and a same-name-different-target entry is caught, and each says which basis found it | unit tests built from §1.3's two real cases |
| A7 | Nothing under `app/Sources` writes a harness config | `scripts/lint/no-harness-config-writes.sh`, in `make lint`, shown able to go red |
| A8 | The detector can go red | the acceptance lane's arming pass mutates the comparison and requires a wrong answer |
