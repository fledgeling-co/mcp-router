# spec-P3 — Oracles for the usage stream and registry search

| | |
|---|---|
| Item | **P3** — `D-l` + `D-m` |
| Branch | `ai/p3` · worktree `.worktrees/P3` |
| Rows owned | `control-usage-stream`, `control-registry-search`, `fixture-registry-search` |
| Rows NOT owned | everything else in `planning/parity/surface.tsv`. `install-launchd-watch` is the other runner's |
| Status | Ready for work |
| Review lane | grok-4.6 (out of family). Codex account-blocked until 2026-08-20 |

---

## 1. The brief, and the two places measurement contradicted it

The brief says, of all three rows: *"they are oracle problems rather than implementation
gaps. The Swift side may well be correct already; what is missing is a way to KNOW."*

**That is right about `D-l` and wrong about `D-m`, and the second one is a live product
defect.** Both statements below are measurements taken on `main` at `7babd97`, not readings
of source.

### 1.1 `D-l`: the oracle already exists, passes, and the gate has never run it

`scripts/acceptance/parity-stream.sh` was written by R2-R. It opens `GET /usage/stream` at
both routers over a real socket, holds both connections open, drives three identical
`tools/call`s at each, and diffs the frames. Run by hand from `.worktrees/P3`:

```
  both routers delivered the opening comment while the connection stayed open
  both routers streamed one frame per call, as the calls happened
  both routers sent the 25s heartbeat on the open connection
  ok   GET /usage/stream — 5 frames diffed byte for byte on an open connection
compared 1 rows: 1 ok, 0 failed          EXIT 0
```

The row is blocked anyway, for one mechanical reason: `A lane that is not NAMED here is not run, and nothing says so. The missing-script guard`, `parity-gate.sh:32` at `42ea4d3` reads

```
LANES="${PARITY_LANES:-control fixture divergence pool suite mcp cli install state log}"
```

**`stream` is not in that list.** The lane script exists, is executable, is correct, and is
dispatched by nothing. The gate's own missing-script guard (`classifies every affected row blocked, exits 2 and names the remedy. That behaviour is`, `parity-gate.sh:74` at `42ea4d3`) only fires
for a lane it was *asked* to run, so a lane nobody asks for produces no result, no
environment failure and no complaint — the row simply stays blocked with a note about SSE
that stopped being true when R2-R merged.

So `D-l` is not "an oracle needs building". It is **an oracle needs connecting**, plus the
strengthening in §2, because what the lane compares today is genuinely narrower than the
row's claim.

### 1.2 `D-m`: the Swift router cannot answer `GET /registry/search` at all

Both binaries started on scratch homes, same request at each:

```
GET /registry/search?q=github&limit=2
  swift      → HTTP 502  {"error":"registry search is unavailable: no HTTP client is configured"}
  reference  → HTTP 200  {"results":[{"id":"smithery:github", … }], …}
```

The mechanism, traced to source and confirmed by grep across the whole of `app/Sources`:

- `guard let registryDeps = deps.registry else {`, `ControlRegistry.swift:9` at `42ea4d3` guards on `deps.registry`, and answers 502 when it is `nil`.
- `var deps = await ControlDeps(`, `RouterServiceDispatch.swift:109` at `42ea4d3` builds the daemon's `ControlDeps` and **never sets
  `registry:`**, so it is `nil` in the only process that ships.
- There is **no production conformance to `HTTPFetching` anywhere in `app/Sources`.** The
  protocol is declared at `public protocol HTTPFetching: Sendable {`, `RegistrySearch.swift:4` at `42ea4d3`; every implementation of it lives under
  `app/Tests`. `RegistryDeps(` appears in no source file at all.

`Registry.search`, `RegistryMerge`, `coerceLimit` and the GitHub-cache logic are all
implemented and unit-tested. What is missing is the one thing that would let any of it run
in the shipping binary: a client that performs an HTTP GET.

**This is why the row being blocked was dangerous rather than merely incomplete.** It was
blocked with an oracle reason, so nobody looked past the oracle; a reader of the manifest
would conclude the Swift side was probably fine and unmeasurable. It is not fine, and after
a cutover the Mac Discover board and the phone's Discover tab — whose entire content comes
from this route — would show an error banner on a Swift router where they show results on
the reference.

---

## 2. What each row must prove, and what it must not be allowed to claim

### 2.1 `control-usage-stream`

The row's governing sentence is the brief's: **framing agreement is not body parity.** The
lane must not be allowed to pass on status and content-type. Five dimensions, each a
separate assertion:

| # | Dimension | State on `main` |
|---|---|---|
| A | Status line and **every response header** | **not compared anywhere.** `cache-control: no-store` and `connection: keep-alive` (`if (p === '/usage/stream' && req.method === 'GET') {`, `control.ts:456-459` at `42ea4d3`) are asserted by nothing |
| B | Opening frame arrives before the body ends | covered |
| C | One `data:` frame per call, bodies byte-identical | covered, but see the blind spot below |
| D | The 25s heartbeat actually fires | covered |
| E | **A late subscriber gets no backlog** | **not covered** |
| F | The stream does not terminate itself | **not covered** — the lane kills the reader without ever checking it was still alive |

**The blind spot in C.** `"the response head — status line and every header — is byte-identical on both routers,`, `parity-stream.sh:252` at `42ea4d3` extracts frames with

```
sed -n '1,/^: ping$/p' "$1" | grep -E '^(: connected|data: |: ping)'
```

so any line that is *not* one of those three kinds is dropped before the diff. Its own
header comment claims *"the frame's `data: ` prefix and its blank-line terminator are all
compared byte for byte"* — **the blank-line terminators are filtered out by that grep, and
so would be an `event:` line, an `id:` line, or a `retry:` line.** A port that named its
events (`event: usage`) or omitted the blank line that terminates an SSE frame would diff
clean today. SSE frames are delimited by the blank line; a stream without them is not
parseable by any client, and this lane would call it parity.

**E is the dimension the brief names and the one most likely to diverge.** The reference
subscribes and nothing more ("res.write(`: connected\n\n`);", `control.ts:462` at `42ea4d3`): a client that connects after ten calls have
happened sees none of them. A port that replayed history to a new subscriber would double
every record in the Activity board of an app that reconnects — and every existing assertion
in this lane would still pass, because they all measure a single reader that connected
first.

### 2.2 `control-registry-search`

Two things have to be true before this row can be compared at all, and the second is what
the ledger already named as the honest route:

1. **The Swift router has to be able to answer it.** §1.2. This is implementation, and it
   is in scope: leaving it out would mean reporting the row blocked on an oracle when the
   oracle is not what blocks it.
2. **Both binaries must query the same deterministic thing.** The reference resolves its
   two indexes from `process.env.MCP_ROUTER_REGISTRY` and `process.env.MCP_ROUTER_SMITHERY`
   ("const OFFICIAL = process.env.MCP_ROUTER_REGISTRY ??", `src/registry.ts:18-19` at `42ea4d3`), and `RegistryDeps.officialBase` / `.smitheryBase` are the
   Swift side of exactly that seam. A recorded fixture registry served over loopback makes
   both sides read identical upstream bytes, so any difference in the response is the
   port's.

**GitHub is a third live dependency and is pinned rather than avoided.** `enrichWithStars`
("`GITHUB_TOKEN` raises the ceiling to 5,000 if one is present.", `src/registry.ts:220` at `42ea4d3`) calls `https://api.github.com/repos/…` for every entry whose
`repository` matches `github.com`, and that host is **hard-coded in the reference** — there
is no env seam for it. Two ways to make the route deterministic:

- serve repository URLs that are not GitHub, so `repoKey` returns nothing and no fetch
  happens. Deterministic, but it also switches off the `repoKey` **dedupe** path, which is
  how a server appearing in both indexes becomes one `source: "both"` row. That is the most
  interesting behaviour on the route and losing it would be a real hole.
- **pre-seed `github-cache.json` in both scratch homes.** Both implementations read a
  day-old cache before fetching (`if (hit && now - hit.at < GH_TTL_MS) {`, `src/registry.ts:235` at `42ea4d3`; `if let hit, let cachedAt, deps.nowMs - cachedAt < githubTTLMs {`, `RegistrySearch.swift:225` at `42ea4d3`,
  `githubTTLMs`), so a seeded entry with a fresh `at` is a cache hit and the network is
  never touched. Deterministic **and** the dedupe, the star enrichment and the
  `useCount → stars → updatedAt` ranking are all exercised.

The second is what this item does. A run that reaches `api.github.com` at all is a lane
failure, not a slow lane.


### 2.3 `fixture-registry-search` — accepted as uncomparable, and the reasoning is the deliverable

The first draft of this spec proposed re-recording
`app/Sources/MCPRouterKit/Control/Fixtures/registry-search.json` against the pinned fixture
registry, un-skipping it in `parity-fixture.sh`, and taking the row to `proven`. **The
out-of-family review killed that, correctly, and this section is the replacement.**

The fixture group's claim is **reference currency** — the recorded body is still what the
reference emits. For this one fixture the recorded body is `f(live registry payloads)`. Pin
the payloads and the claim does not become measurable; it becomes a *different claim*: "the
reference still transforms P3's own synthetic corpus the same way". And that claim is
**already compared, on every gate run, by `control-registry-search`** — which drives the
live reference and the live Swift router over exactly that corpus and diffs the bytes.

So a re-record buys a green row carrying no information the gate does not already hold. It
is not free either. The committed body is the only production-shaped registry sample the
decode suite has, and it contains a real-world deformity — `"repository": "https://github.com/"`,
a repository URL with no owner or repo — that no synthetic corpus would invent and that
`repoKey` has to survive. Replacing it with a clean fixture destroys that evidence.

**That is the shape of the failure this item was warned about**: a formulation under which
the row goes green without the capability having been compared. The capability here is
currency against the real indexes; it cannot be compared deterministically by anything, and
swapping in a weaker claim that already has a stronger instrument is the quiet pass.

So the row **stays `blocked`**, with the owner column reading `accepted-uncomparable` and a
note that says all of the above in the manifest itself. No new verdict token is introduced:
the census still knows the row, the coverage fraction still counts it against the
denominator, and nothing about it becomes easier to park.

`parity-fixture.sh` is **not touched at all** — not its by-name skip, not its normaliser, not
its comments. P4 rewrote that file two commits ago and the skip it contains is still exactly
right.

**The consequence, stated rather than buried: 83 of 83 is unreachable while this row is
enumerated and unprovable.** R4-C's gate is written as "the parity gate must reach 83 of 83".
That needs an owner's decision — either the target becomes 82 of 83 with this row's reason
attached, or someone redefines what the row is for. It is not a runner's call and it is not
quietly absorbed.

---

## 3. Acceptance criteria

- **A1** `parity-gate.sh` dispatches the `stream` lane and a new `registry` lane, and a row
  either lane owns is reconciled from its results like any other.
- **A2** The stream lane compares the **status line and every response header** at both
  routers, with `Date` the only substitution, and additionally asserts the three handler
  headers present by name so a new header fails with a sentence rather than a diff.
- **A3** The stream lane compares **every line** of the frame region, blank-line frame
  terminators included, and fails on any line kind it was not told to expect — **even when
  both routers produce it**.
- **A4** The stream lane opens a **second, late** reader, waits for its opening comment,
  asserts **zero** `data:` frames on each side *absolutely* (not as an agreement), then
  drives one call and asserts each late reader holds exactly that one, byte-identical.
- **A5** The stream lane proves the first connection was **still open and still delivering**
  — the reader pid alive *and* the original readers carrying the record driven after the
  heartbeat — before anything is torn down.
- **A6** `GET /registry/search` is compared as a **byte diff of status and body** against the
  reference for the same request. An empty `results` is a failure, not an agreement.
- **A7** The registry lane reaches **no host outside loopback**, proved two ways: the seeded
  star count survives into the compared body (a router that really called GitHub carries
  different numbers), and neither router process holds an established off-loopback socket.
- **A8** Each scenario is its **own** byte diff: the merged `source:"both"` row, both official
  install recipes, the four `limit` edges (`0`, `NaN`, negative, `>60`), an absent `q`, one
  index answering 503, and the registry gone entirely.
- **A9** A **shape guard** refuses the whole run unless the reference's own body carries every
  path the lane claims to compare — `source` in all three states, npx and uvx stdio installs,
  sse and http remote installs, a `requires[]`, `installed` in both states, seeded stars, a
  non-empty `sources` census. Two parsers that both returned nothing diff clean.
- **A10** The seeded GitHub cache is **load-bearing for the compared bytes**: the corpus is
  built so the seeded stars decide the relative order of two rows, so a cache that silently
  missed on both sides changes the body rather than passing quietly.
- **A11** `fixture-registry-search` stays `blocked`, its note in the manifest states the
  standing exclusion and the 83/83 consequence, and `parity-fixture.sh` is unmodified.
- **A12** The manifest's **row count does not move**: 83 before, 83 after, pin untouched, no
  row deleted or renamed, no new verdict token.
- **A13** `parity-manifest-check.sh` and `make parity-selftest` both stay exit 0, and neither
  is edited — the problem counter is G1's.
- **A14** Every mutation is proven red against a **rebuilt** binary; any that cannot redden is
  re-aimed at the same claim rather than swapped for an easier one.

## 4. Out of scope, deliberately

- **`mac-shell.sh`, the freshness checks, and `parity-manifest-check.sh`'s problem counter** —
  G1's, in flight.
- **`install-launchd-watch`** — the other runner in this wave.
- **`parity-fixture.sh` and `capture-control-fixtures.sh`** — untouched, per §2.3.
- **`ControlDiff`** — deliberately left with no registry client. Wiring one would put a live
  registry call inside every control-lane run, unpinned and rate-limited; leaving it means the
  control lane keeps printing an in-process 502 for a route the product now answers, which is
  the lesser harm and is recorded in `ControlPorts.swift`.
- **The `D-p1-a` OAuth client.** A registry client is a plain GET; an OAuth client is
  discovery, dynamic registration and a PKCE exchange.
- **Proving `RegistryHTTPClient` against the real indexes** — TLS, redirects and request
  headers are URLSession's and are unexercised here. `D-p3-e`. **P3 does not claim the
  Discover boards work against the real registries.**

## 5. Deferred children this item registers

| # | Child | Absorbed by | Mechanism |
|---|---|---|---|
| `D-p3-a` | The registry rows are pinned against a frozen upstream, so a schema change at the real registries is invisible | new item | If `registry.modelcontextprotocol.io` renames a field, both routers mis-parse it identically and every P3 row stays green. Needs a separate, **non-gating** liveness probe against the real indexes; a gating one would be nondeterministic by construction |
| `D-p3-b` | `enrichWithStars` is proven only on the cache-hit path | new item | Both binaries run with a pre-seeded in-TTL cache, so neither issues the GitHub request. The 403/429 rate-limit warning, the `budget` cap and the cache **write** are unexercised on the wire, and `api.github.com` has no env seam in the reference to point elsewhere |
| `D-p3-c` | The late-subscriber frame proves no-backlog, not ordering under concurrency | new item | Records are driven one at a time. Two subscribers receiving interleaved records from concurrent calls in the same relative order is a stronger claim and needs a concurrent driver |
| `D-p3-e` | `RegistryHTTPClient` is unexercised against TLS, redirects and a real host | R4-C | Every scenario is `http://127.0.0.1`. Three residues: URLSession's `timeoutInterval` is an **idle** timeout where the reference aborts on a total 12s deadline, so a server that dribbles bytes forever is aborted by one and not the other; redirect handling is URLSession's default and the reference's is undici's; and the two send **different request headers**, `User-Agent` included, which no lane compares because a fixture that echoed them would produce a false red nobody can fix |
| `D-p3-f` | **83 of 83 is unreachable as the manifest is enumerated** | R4-C · owner | `fixture-registry-search` is a standing exclusion (§2.3). R4-C's gate is written as 83/83 and cannot be met. Either the target becomes 82/83 with the exclusion's reason attached, or the row's claim is redefined by its owner. A runner must not resolve this by deleting the row, which raises coverage |

## 6. Status

Written after the two measurements in §1, and revised after the out-of-family spec gate.
`D-m`'s premise — that the row is an oracle problem — is **contradicted by measurement and
the measurement wins**: it is an oracle problem *and* a missing implementation. `D-l`'s
premise is contradicted the other way: the oracle already existed and the gate had never been
told to run it.

## 7. Review — grok-4.6, adversarial, out of family

Verdict: **AMEND**, gated — *"do not start work on A1 until 1, 2, 5 and 9 are written into the
ACs."* 11 findings: 2 CRITICAL, 7 HIGH, 2 MEDIUM. Lane smoke-tested for real content before
use (`LANE-OK-P3 42`), because grok exits 0 when session init fails.

| # | Finding | Disposition |
|---|---|---|
| 1 | CRITICAL — the fixture registry could serve the merged envelope, both parsers return `[]`, and empty-and-identical passes | **Accepted.** The fixture serves the two native index dialects on their real paths, and A9's shape guard now refuses the run unless the reference's body carries `source:"both"`, both install recipes and a non-empty census |
| 2 | CRITICAL — A6's "envelope" is weaker than the `control` group's own claim | **Accepted.** A6 is a byte diff of **status and body**; the lane compares the status code explicitly, which it did not before |
| 3 | HIGH — A8 "covers" paths it does not compare; the negative-limit case is a no-op on a small catalogue; the unreachable-index warning cannot be byte-diffed | **Accepted in part, and one half refuted by measurement.** Each case is now its own byte diff and the catalogue is 7 merged rows. The warning **is** byte-comparable: node's `fetch` throws `fetch failed` (measured), and P3's client reproduces that string exactly rather than dumping an `NSError` — so no normalisation is needed and none is applied |
| 4 | HIGH — the GitHub-cache pin can no-op and still match | **Accepted, and it changed the corpus.** `beacon`'s and `relay`'s `updatedAt` are now ordered so the seeded stars decide which sorts first: with them beacon leads, without them relay does. A7 also gained the `lsof` observable, described honestly as the weaker of the two |
| 5 | HIGH — A9 re-records a shared oracle, does not pin the recorder, and destroys the only live-shaped sample | **Accepted, and it inverted the outcome.** The row is no longer re-recorded. §2.3 replaces it: accepted as uncomparable, `parity-fixture.sh` and `capture-control-fixtures.sh` untouched, and the 83/83 consequence registered as `D-p3-f` |
| 6 | HIGH — the client's scope, and ControlDiff | **Accepted.** The client is `URLSession` (so TLS and redirects are the platform's, not hand-rolled), the TLS/redirect/header residue is `D-p3-e`, the Discover-is-fixed claim is withdrawn, and ControlDiff is explicitly left unwired with the reason recorded in source |
| 7 | HIGH — A4 can green a replay if it is only a differential of a racy read | **Accepted.** Zero backlog is asserted **absolutely on each side** after a settle, before any diff |
| 8 | HIGH — A2's "every header" will be filtered or will flake on `Date`/`Keep-Alive` | **Accepted in part; the flake is refuted by measurement.** Both routers send the same five headers in the same order and only `Date` differs, measured before the assertion was written. `Date` is the only substitution, and the three handler headers are additionally asserted present by name |
| 9 | HIGH — the gate ignores a lane's `ok` on a `blocked` row, so "two verdict fields" hides a hole | **Accepted, and it is now exact.** Two rows flip to `proven`; the third stays `blocked` **by decision**, not by omission, and §2.3 says why |
| 10 | MEDIUM — A3 still cuts the region at the first ping; A5 has no observable | **Accepted for A5, declined for the cut.** A5 is now the reader pid alive *and* the original readers carrying a record driven after the heartbeat. The region stays cut at the first ping: beyond it the two streams are compared on when a 25s timer landed relative to a teardown, which is scheduling. The post-heartbeat delivery check is what covers the far side |
| 11 | MEDIUM — §1.1 calls the existing lane "correct" | **Accepted.** §1.1 now says what it is: an under-claiming draft that was never connected |
