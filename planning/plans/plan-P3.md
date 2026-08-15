# plan-P3 — Oracles for the usage stream and registry search

Branch `ai/p3`, worktree `.worktrees/P3`. Docs live in the **main tree** and are not committed on
the branch. Rows owned: `control-usage-stream`, `control-registry-search`,
`fixture-registry-search`, and nothing else in `planning/parity/surface.tsv`.

**The row count does not move.** 83 before, 83 after. No row is added, deleted or renamed, so the
pinned census comment at `surface.tsv:3` is not touched. TWO `verdict` fields and three `note`
fields change — the third row stays `blocked` by decision, see Step 6; the file is not reflowed, re-sorted or reformatted.

---

## Step 0 — the baseline, measured before anything changed

`parity-gate.sh` from `.worktrees/P3` on `main @ 7babd97`:

```
control     13 of 16 proven, 3 blocked      fixture     23 of 24 proven, 1 blocked
divergence  15 of 15 proven (4 by suite)    pool         6 of  6 proven
mcp          5 of  5 proven                 cli          9 of 10 proven, 1 blocked
install      4 of  5 proven, 1 blocked      state/log    1 of 1 each
parity: 77 of 83 rows proven, 6 blocked. GATE EXIT 1
```

The six blocked are `control-usage-stream`, `control-registry-search`, `control-auth-post-http`,
`fixture-registry-search`, `cli-auth`, `install-rollback`. Three of them are P3's. **Target: 79 of
83** — two of the three become provable and the third is accepted as uncomparable (Step 6). Still
exit 1 by design.

Four measurements taken before the plan was written, each of which decided a step:

| # | Measurement | Consequence |
|---|---|---|
| 1 | `parity-stream.sh` run by hand: exit 0, 1 row, 5 frames diffed | the oracle exists and is unwired — Step 1, not a new lane |
| 2 | Swift `GET /registry/search` → **502**, reference → 200 | Step 4 exists at all |
| 3 | Both routers' stream response heads are **byte-identical** apart from `Date` | Step 2a is achievable and is not a divergence hunt |
| 4 | Both routers deliver a late subscriber **exactly one** frame, no backlog | Step 2c is an agreement to lock in, not a defect to fix |

---

## Step 1 — `parity-gate.sh`: dispatch the two lanes

One line. Append rather than insert, so the diff is one token per lane and lane ordering (and
therefore port scheduling) for the existing eight is unchanged.

```diff
-LANES="${PARITY_LANES:-control fixture divergence pool suite mcp cli install state log}"
+LANES="${PARITY_LANES:-control fixture divergence pool suite mcp cli install state log stream registry}"
```

Nothing else in that file changes. The reconciliation, the orphan check, the blocked/mismatch
accounting and the exit-code precedence are all untouched — a lane appearing in `LANES` is the
whole mechanism.

**Why this was invisible.** The missing-script guard at `parity-gate.sh:74` only fires for a lane
the gate was *asked* to run. A lane script that exists and is never named produces no result rows,
no environment failure and no complaint; its row stays blocked, and the note explaining why it is
blocked is the only trace. That is worth a comment in the file next to `LANES`, and it gets one.

## Step 2 — `parity-stream.sh`: four dimensions the row claims and the lane did not compare

### 2a. The response head, byte for byte

`curl -D` writes the status line and every header to a file. Both are compared after one
substitution: `Date:` is a clock. Measurement 3 says the rest already agree —
`content-type: text/event-stream`, `cache-control: no-store`, `connection: keep-alive`,
`Transfer-Encoding: chunked`, in that order, on both routers — so this locks in an agreement
rather than hunting one, and it is exactly the "framing" half the manifest note says is reported
and never compared.

### 2b. Every line, not three line kinds

`frames_of` becomes: take the frame region, and compare **all** of it, blank lines included.

```diff
-frames_of() { sed -n '1,/^: ping$/p' "$1" | grep -E '^(: connected|data: |: ping)' | normalise; }
+# Every line in the region, blank frame terminators included. The previous form grepped for three
+# line kinds, which silently DROPPED anything else — so an `event:`, `id:` or `retry:` line, or a
+# missing blank-line terminator, diffed clean. SSE frames are delimited by that blank line; a
+# stream without it parses as one frame forever, and this lane called it parity.
+frames_of() { sed -n '1,/^: ping$/p' "$1" | normalise; }
```

Plus an explicit assertion that the region contains **only** the three expected line kinds and
blanks, so a new line kind is a named failure rather than a diff both sides happen to share:

```
unexpected="$(grep -vE '^(: connected|: ping|data: .*)$|^$' "$WORK/$side.frames" | head -3)"
```

The `< 5` emptiness floor is raised to 9, since blank terminators are now counted.

**The alternation carries no empty branch.** Written the obvious way — `'^(a|b|c|)$'` — BSD grep
refuses it with `empty (sub)expression`, matches nothing, and leaves the check reporting clean on
every input. The first cut of this fix shipped exactly that, inside the fix for another gate that
could not fail. The blank line is its own pattern: `'^(a|b|c)$|^$'`.

### 2c. A late subscriber gets no backlog

A second reader is opened **after** two calls have already been recorded, then one more call is
made. The assertion is three-part, and the third part is what makes it a comparison rather than a
coincidence:

1. each router's late reader carries the opening comment;
2. each router's late reader carries **exactly one** `data:` frame — not three;
3. the two late readers' frame regions diff byte for byte after the same normalisation.

Part 2 is the one that fails on a port that replays history, and none of the existing assertions
can see it: every one of them measures a reader that connected first.

### 2d. The stream did not terminate itself

Before the teardown, `kill -0` on each reader pid. `curl` exits when the server closes the
connection, so a live reader is proof the stream is still open after the last record and the
heartbeat. Today the lane kills a reader it never established was alive — and a router that closed
the stream after the third frame would pass every assertion above it.

The existing reader-disconnect check (both routers still serve `/health`) stays as it is.

## Step 3 — `RouterCore`: a production HTTP GET, and the deps the daemon never built

### 3a. `app/Sources/RouterCore/HTTP/RegistryHTTPClient.swift` — new, ~35 lines

The only conformance to `HTTPFetching` outside the test targets. One `URLSession` GET, the
headers it is given, the timeout it is given, status and body back. It maps a non-HTTP response to
`HTTPFetchError` rather than force-unwrapping, and it does not interpret the status — `getJSON`
already applies the reference's `if (!r.ok) throw new Error(\`HTTP ${r.status}\`)`.

### 3b. `RouterServiceDispatch.swift` — the wiring, ~10 lines

```swift
registry: RegistryDeps(
    http: RegistryHTTPClient(),
    fileSystem: fileSystem,
    routerHome: home.root,
    officialBase: environment["MCP_ROUTER_REGISTRY"],
    smitheryBase: environment["MCP_ROUTER_SMITHERY"],
    githubToken: environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"],
    nowMs: clock.nowMilliseconds
),
```

**The `??` chain is nullish on both sides and that is load-bearing.** `ProcessInfo`'s dictionary
returns `Optional("")` for a variable that is set and empty, exactly as `process.env.X` yields
`''`; JavaScript's `??` keeps it, and Swift's `??` keeps it. So `MCP_ROUTER_REGISTRY=""` resolves
to `""` on both, `new URL('/v0/servers', '')` throws on the reference, and
`Registry.resolve` throws `Invalid URL` on Swift — the same warning either way. Widening this to
`.flatMap { $0.isEmpty ? nil : $0 }` would be the natural-looking Swift and would silently
diverge; `RegistrySearch.swift:31` already records B59 for this reason.

`RouterServiceDispatch.swift` is 237 lines and the cap is 400, so this stays where the rest of the
`ControlDeps` graph is built rather than being split off for length.

**What this does not do.** Nothing conforms to `AuthTransport` afterwards, so
`control-auth-post-http` stays blocked on `D-p1-a`. A registry client is a plain GET; an OAuth
client is discovery, dynamic registration and a PKCE exchange. Folding one into the other would
let this item claim a row it has not earned.

## Step 4 — `scripts/fixtures/registry-fixture-server.mjs` — new

A deterministic stand-in for the two live indexes, served over loopback.

- `GET /v0/servers?search=&limit=` → the official envelope
  (`{servers:[{server:{…}, _meta:{"…":{updatedAt}}}]}`).
- `GET /servers?q=&pageSize=` → the Smithery envelope.
- Anything else → 404.

Four properties, each deliberate:

1. **The corpus is fixed and does not filter on the query.** A registry filters; a fixture's job
   is to hand both routers identical bytes.
2. **One entry per index echoes the query string it received** into its `description`. That is how
   the lane proves the router *forwarded* `search`/`limit` and `q`/`pageSize` correctly — the
   echoed value lands inside the diffed body, so a router that sent a different limit fails on
   content rather than on a check nobody wrote. Without it, ignoring the query would also mean
   ignoring what the router asked for.
3. **One server appears in both indexes under the same `github.com` repository**, so `repoKey`
   dedupes it to a single `source: "both"` row — the most interesting path on the route, and the
   one a naive fixture loses.
4. **`FIXTURE_REGISTRY_FAIL=official|smithery`** makes that index answer `503`. Both
   implementations turn a non-2xx into `HTTP 503` (`src/registry.ts:63`;
   `RegistrySearch.swift:161`), so the warning text is `… unreachable: HTTP 503` on both.

**REVISED DURING IMPLEMENTATION, and the revision is an improvement rather than a retreat.** This
step originally said the failure scenario had to be an HTTP status and *not* a refused connection,
because a refused connection would yield node's wording against URLSession's and be a false red.
That was measured instead of assumed: node's `fetch` throws `"fetch failed"` for both a refused
connection and a DNS failure, and `"This operation was aborted"` on an abort. The first cut of
`RegistryHTTPClient` put a whole `NSError` dump — failing URL and internal task id included — into
a warning the Discover board renders. It now reproduces node's two strings exactly, so **the
refused-connection path is byte-comparable too** and is a scenario rather than an excluded case.
The residue (URLSession's idle-timeout semantics versus a total deadline, and the differing request
headers) is `D-p3-e`.

## Step 5 — `scripts/acceptance/parity-registry.sh` — new lane

Owns `control-registry-search` and nothing else; the same `OWNED` guard the stream lane uses, so a
mis-addressed `record` is a lane bug rather than a quiet write into another row.

Environment: node, `dist/index.js`, the Swift binary, three free ports (two routers, one fixture
registry), the ports refused rather than shared. Two scratch homes.

**Both homes are seeded with `github-cache.json`** carrying the corpus's repo keys, each with a
fresh `at`, so `deps.nowMs - at < 24h` is a hit on both sides and neither issues the GitHub
request. This keeps the dedupe, the star enrichment and the `useCount → stars → updatedAt` ranking
in the comparison while removing the one dependency with no env seam in the reference.

Scenarios, each its own two-router diff of **status and body**:

| # | Request | What it establishes |
|---|---|---|
| 1 | `?q=github&limit=3` | the envelope, member order, the merged `source:"both"` row, the seeded stars, the ranking |
| 2-5 | `limit=0`, `limit=abc`, `limit=-1`, `limit=99` | `Math.min(Number(x ?? 30) \|\| 30, 60)` at its four edges, including the negative that reaches `slice` and *drops* rows |
| 6 | no `q` at all | `?? ''`, and the query the router forwards |
| 7 | `FIXTURE_REGISTRY_FAIL=smithery` | the `warnings` array and the partial-result path |
| 8 | the fixture registry stopped | the transport-failure warning, `"fetch failed"` on both |

**Normalisation: none at all**, and that is an assertion rather than an omission. The plan first
said "the two ports only"; the bodies turn out to carry no port, no minted timestamp and no
run-dependent value of any kind, so they are compared as raw bytes. A body that needed normalising
would be telling us something.

**`installed` is not a separate scenario.** `Cinder` is seeded into both `servers.json` files
before the routers start, so every populated body carries one `installed:true` row and several
`installed:false` — the flag is inside all eight diffs rather than in a ninth. Seeding rather than
`POST /servers` also keeps this row off `D-v1a`, which is about whether a control-API write reaches
the running process and is not this row's subject.

**A shape guard, added after the spec gate.** Before any scenario is believed, the reference's own
body must carry every path the lane claims to compare: `source` in all three states, npx and uvx
stdio installs, sse and http remote installs, a `requires[]`, `installed` in both states, the
seeded stars, and a non-empty `sources` census. Two parsers that both returned nothing diff clean,
and a fixture that quietly stopped producing the interesting rows would leave eight agreements
about almost nothing.

**The egress guard is two observables, and the plan originally named the weaker one.** It first
said the lane would check that no unseeded key appeared in `github-cache.json` — but a real GitHub
call for a key that IS seeded leaves no new key, so that check could not see the case it was for.
The strong observable is in the compared body: `"stars":1520` is the seeded number and not the real
project's, and the corpus is ordered so those stars decide which of two rows sorts first. The weak
one is `lsof -a -p <pid> -iTCP -sTCP:ESTABLISHED` on both routers, described as weak because it is a
point-in-time sample.

## Step 6 — `fixture-registry-search`: accepted as uncomparable, NOT re-recorded

**This step inverted after the out-of-family spec gate, and the inversion is the point.** The
first plan re-recorded `registry-search.json` against the pinned registry and diffed it. That was
rejected: over a pinned corpus the row's claim collapses to "the reference still transforms P3's
own synthetic input the same way", which `control-registry-search` already compares every gate run
against the live reference AND the live Swift router — so the flip buys a green row carrying no new
information, while destroying the only production-shaped registry sample the decode suite has
(`"repository": "https://github.com/"`, an owner-less repository URL no synthetic corpus invents).

So:

- `app/Sources/MCPRouterKit/Control/Fixtures/registry-search.json` — **unchanged**.
- `scripts/acceptance/parity-fixture.sh` — **unchanged**, skip and normaliser both.
- `scripts/capture-control-fixtures.sh` — **unchanged**.
- The manifest row stays `blocked`, owner `accepted-uncomparable`, with the whole decision in its
  note so a reader cannot mistake it for work someone will get to.

**And the consequence is reported, not absorbed: 83 of 83 is unreachable.** Registered as
`D-p3-f` for R4-C and the owner.

## Step 7 — the manifest, three rows, in place

Two verdicts flip to `proven` (`control-usage-stream`, `control-registry-search`); the third stays
`blocked` by decision. Three notes rewritten. **83 rows before, 83 after; the pin at
`surface.tsv:3` is not touched, no row is added, deleted or renamed, and no new verdict token is
introduced** — a token that does not count toward coverage is a place a future row can be parked
to make a number rise.

## Step 8 — mutations, each against a rebuilt binary

Each is reverted before the next, and `swift build` runs before every red run: without it a
mutation reports against the previous binary and reads BLOCKED rather than red.

| # | Mutation | Must redden | Claim it proves |
|---|---|---|---|
| M1 | Remove `stream` from `LANES` | the gate: `control-usage-stream` back to blocked | Step 1 is load-bearing |
| M2 | Remove `registry` from `LANES` | the gate: `control-registry-search` back to blocked | same, for the new lane |
| M3 | Swift's opening frame `": connected"` → `": ready"` | `parity-stream.sh` | the frame region is compared, not counted |
| M4 | Swift's SSE `cache-control` header dropped | `parity-stream.sh` head verdict | the head is compared — the old lane could not see this at all |
| M5 | Swift's stream replays the last records on subscribe | `parity-stream.sh` late verdict | a backlog replay is caught; every pre-existing assertion still passes |
| M6 | Revert the `registry:` wiring in `RouterServiceDispatch` | `parity-registry.sh` | the row compares the capability, not a fixture of it |
| M7 | `coerceLimit`'s `min(truthy, 60)` → `min(truthy, 30)` | `parity-registry.sh` limit scenarios | the limit edges are compared |
| M8 | `RegistryHTTPClient` maps a transport error to URLSession's own description | `parity-registry.sh` unreachable scenario | the user-visible warning string is compared, not just its presence |

M4, M5 and M8 aim at dimensions that did not exist before this item. Any that cannot redden is
**re-aimed at the same claim**, never swapped for an easier one.

## Step 9 — gates and numbers

`make lint` (0), `make test`, `make build-mac`, `parity-manifest-check.sh` (0), `make
parity-selftest` (0), and `parity-gate.sh` from **both** the worktree and the repo root — both,
because `D-o` was a verdict that depended on the directory the gate ran in.

`make lint` runs `swiftformat --lint` first and short-circuits, so formatting is settled before
any swiftlint count is read. `make format` is not run blind: it adds wrapped lines and can push a
file past the 400-line cap.

## Step 10 — evidence, commit, stop

`planning/evidence/P3-acceptance.md`, appended. Committed on `ai/p3` by explicit pathspec — never
`git add -A`, because the worktree carries an untracked `dist` symlink that `.gitignore`'s
`dist/` does not match (a symlink is not a directory).

Spec and plan stay in the main tree and are **not** committed on the branch. No merge.

---

## Amendment — after the plan gate and the Phase D critic (2026-08-15)

Both ran out of family on `grok-4.6` and both returned **AMEND**. Eighteen findings; eleven changed
the delivery. The plan as written above is superseded in these places, and the reasons are recorded
so the next reader does not re-derive them.

1. **Step 8's M3 was aimed at an assertion it could not reach.** `": connected"` → `": ready"` dies
   at the opening-`await` arrival gate that pre-dates P3, so it never exercised the frame
   comparison it was supposed to prove. Replaced by **M3a** (drop the blank-line terminator) and
   **M3b** (inject an `event:` line), both of which redden inside the compared region.
2. **Step 8's M5 could not show that the other verdicts still held**, because the fourth record was
   driven only when the late-subscriber check had already passed. The drive is now unconditional;
   M5 reddens the late verdict alone and still-open stays green.
3. **A mutation for Step 2d was missing.** Added as **M9**: the daemon ends the stream after its
   heartbeat. It reddens still-open and nothing else.
4. **The lane's result accounting was unsound** and no step covered it. Verdicts recorded as they
   went, and the gate scores a row proven on any `ok` with no `fail`, so a lane dying after the
   happy path left the row green. Results are now buffered and flushed once, after asserting all 12
   scenarios ran. Added as **M10**.
5. **Four assertions could pass while both routers were equally wrong**: ranking (never compared —
   both could skip it and agree), `limit=-1` (no length assertion), the still-open verdict (a frame
   count, not a diff), and late-stream line kinds (the check ran on one of the two streams). All
   four are now absolute per-router assertions.
6. **Two scenarios the fixture could already produce were never run**: official-index-down, and
   both registry bases set-and-empty — the latter being the nullish-default divergence the
   implementation comment calls load-bearing.
7. **`URLSession.shared` was wrong for a daemon.** It carries the process-wide `URLCache`, which
   node's `fetch` has no equivalent of; a cacheable registry response would have made the two
   answer differently from the same upstream. Now `.ephemeral`.
8. **Step 6 stands.** Both gates agree `fixture-registry-search` should NOT be flipped. What was
   struck is the manifest's claim that the risk it guarded is "now carried by
   `control-registry-search`" — live-index currency is carried by nothing and remains `D-p3-a`. The
   one recoverable part, the owner-less `https://github.com/` repository, is now in the fixture
   corpus and shape-guarded.
9. **Step 9 required the gate from two places and only one was reported.** Both are now measured.

The census did not move at any point: 83 rows before, 83 after, pin untouched.
