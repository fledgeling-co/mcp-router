# Trawl — features for the mcp-router Mac app

**Receipt:** Trawl standard — 5 frames, 39 ideas → 27 after mechanism-dedup, 7 floored,
0 frames apoptosed. ★ BEATS baseline. Run 2026-08-13.

## Brief

*What should the mcp-router Mac app do beyond the stated set (menu-bar popover +
window, view logs, reset logs, install, browse a registry, authenticate, remove,
highlight unused)?*

**Frozen baseline** (the 30-second senior answer, held for the boss gate): per-server
enable/disable toggle; a form to edit env vars and args; a health check that pings
each server and badges failures; a notification when a server errors; launch-at-login
plus start/stop the router; export/import the config.

**Frames:** freelance contractor billing six client repos · a 3-second glance
constraint with clicks forbidden · adversary + inversion · commercial aviation
flight-deck design (cross-domain) · head sommelier maintaining a cellar (wild seat).

## Two measurements that decided four ideas

Both were run against the real system rather than assumed, and both flipped a verdict.

- **Cold start is a real cost.** From the live router's own log, n=38: median **769ms**,
  p90 **3538ms**, worst **5704ms** (`lifeline`). Every pre-warming idea carried the same
  self-declared falsifier — "cold start consistently under ~400ms" — and the measurement
  clears it. Pre-warming survives.
- **The official MCP registry has no popularity signal.** `registry.modelcontextprotocol.io`
  returns `{server: {name, description, repository, version, remotes[], packages[]}, _meta:
  {publishedAt, updatedAt, isLatest}}`. No downloads, no ratings, no stars. "Popular and
  trending" has no first-party source, and any ranking has to be imported or dropped.
  This also guts the Confusable Gate's second evidence source (publisher account age).

## Wide set, by cluster

**A · Attribution and cost** — project ledger joining cwd to server-seconds and call
counts · menu-bar monogram of the repo currently calling · RAM-saved gauge.

**B · Trust in what a server says** — schema quarantine (hash tool name+description+schema,
gate on change) · confusable/typosquat gate at install · provenance chain from registry
entry to running process · taste-before-you-pour (probe a safe tool, withhold from the
tool list if it fails).

**C · Blast radius and secrets** — inverse index of secret → servers that inherit it,
with a minimal-environment allowlist · per-project scoping of which servers a directory
may see · one-gesture containment (kill all, seal tokens, rotate the control token).

**D · Signalling discipline** — dark cockpit (nothing drawn at rest, plus a lamp test) ·
anomaly-only notification budget keyed to per-project baselines · failure shown with its
live blast radius (which sessions break) and its actions in one stack · silence detector
for a stalled session · fixed spatial matrix where position encodes identity.

**E · Degradation as a state** — MEL placard: a broken server stays dispatchable and its
tools return a structured error naming the substitute, addressed to the model · squawk log
inherited by the next session · postmortem rules authored from a specific incident.

**F · Lifecycle and resources** — a committed warm set under a RAM budget, zero-sum so
adding one evicts one · maturity states that bind different idle policy · phase inhibit
(during an agent burst, suppress notifications *and* the router's own idle-reap and cache
refresh) · cross-spawn trend detection for leaks and orphans.

## Converge — shortlist

Three slots, maximally different in mechanism, one from each of three clusters.

★ **1 · Schema quarantine** (cluster B) — **BEATS**
The cached tool list is the router's core mechanism and its core liability in the same
breath: it answers "what tools exist" from disk with nothing running, so whatever a server
last wrote into its descriptions is what every session is handed. Hash name + description +
schema at the moment the user accepts a server; on any change, keep serving the accepted
version and raise a word-level diff with zero-width, bidi and homoglyph characters rendered
visible. Nothing in the baseline can see this: the server is healthy, nothing errors, no
ping fails. *First step:* the manifest already stores per-server `hash` and full `tools[]` —
add a `approvedHash` alongside it and diff in `unionTools`.

**2 · Per-project scoping, with the ledger that justifies it** (cluster A+C) — **BEATS**
The router already resolves the calling process's working directory. That makes two things
possible the baseline cannot express: a ledger of which project used which server, and a
tool list filtered by caller — the same server on for one repo and off for another
simultaneously, where the baseline toggle is one global boolean. Ship the ledger first and
the enforcement behind it. *First step:* `/usage/summary` already returns per-server
`projects{cwd: calls}`; the filter is a predicate in `unionTools`.

**3 · MEL placard** (cluster E) — **TIES** — *non-obvious slot*
When a server is broken, do not hide its tools and do not return a stack trace. Return a
structured error carrying the reason and the named substitute, so the assistant reroutes on
its first attempt instead of burning a turn. The consumer of this feature is the model, not
the human — which is why no baseline item resembles it. Weakest of the three on evidence:
its own analogy-break is that a self-written, infinitely re-deferrable placard has none of
the enforcement that makes an MEL work.

**Adopted as rules rather than features:** *dark cockpit* — the menu bar draws nothing at
rest, any glyph means a decision is needed, and a lamp test exists so blank and broken are
distinguishable; *fixed spatial matrix* — the popover and the window share one geometry so
a server is found by location, not by reading.

**Measured-in:** the *warm set*, on the p90 3.5s number above.

## Traps — attractive, and each fails for a nameable reason

- **Blocking per-call consent prompt.** MCP clients time out well inside human reaction
  time, so every prompt fails closed and is experienced as random breakage. The
  non-blocking form (filter the tool list) survives; the prompt does not.
- **Full request/response capture by default.** Stores client source fragments and tool
  arguments — including secrets — in plaintext on disk. Viable only as explicit opt-in.
- **A "RAM saved" gauge.** Needs a counterfactual resident size the router never observes,
  because it never runs the 190-process world. Fabricating a number on a surface whose
  credibility rests on real ones is the same trade already rejected for the marketing page.
  The certain quantity — processes not currently running — is fine.
- **Per-pid socket and egress auditing.** Requires a privileged helper sampling the kernel
  process table; the entitlement and review burden is larger than the rest of the app, and
  sampling misses short connections, so a clean result is a false negative.
- **Keychain-anchored tamper chain.** Defends against an adversary that already executes as
  the user, who can equally compromise the app holding the chain.
- **Self-attacking rebind probe.** A security test suite for the daemon, not a feature of a
  server manager. Right idea, wrong product.
- **Multi-version co-residency with replay diffing.** A product on its own: a per-cwd routing
  table, two resident versions, and a replay harness whose diffs are dominated by
  non-idempotent calls.

## Provocation

The router is the only process on this machine that outlives every Claude session and sees
all of them at once. Every idea above still treats it as infrastructure reporting upward to
a human. What would it do if it were allowed to act on what only it can see — and what is
the first thing you would refuse to let it decide?
