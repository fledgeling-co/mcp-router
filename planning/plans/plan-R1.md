# Plan — R1: Swift router, core, config, manifest

**Spec:** `planning/specs/spec-R1.md` · **Branch:** `ai/r1` · **Worktree:** `.worktrees/R1`
**Plan size:** Large
**Created:** 2026-08-14 · **Revised:** 2026-08-14 after two out-of-family review rounds

## The shape of the problem

Three TypeScript modules, ~650 lines, become a Swift library. The line count is not the difficulty.
R4 compares the two implementations mechanically, so the port must reproduce not just what the
reference *means* but what it *does* — thirteen behaviours (spec N1–N13) that are artefacts of
JavaScript rather than decisions, and five places (spec D1–D5) where it must deliberately differ.

Both security-relevant hashes are `sha256` over a `JSON.stringify` result, so **byte-identical
JSON serialisation is the foundation** and every parity claim above it is worthless without it.

Why that is not gold-plating: the tool-surface digest decides whether a server has "changed its
tools and needs approval". If the two implementations disagree on serialisation, then at R4's
cutover **every server appears to have changed at once**, and the user is handed a wall of
approval prompts — training them to click through the exact mechanism that exists to catch a
server rewriting its own tool descriptions.

**This plan states rules, not intentions.** The first draft said things like "matches the
reference" and "takes a backup"; the review's central objection was that a mechanism named is not
a mechanism specified, and an implementer handed that has to re-derive the rule and may derive it
differently. Every rule below is written out.

---

## Target layout

New SwiftPM library target `RouterCore` in `app/Package.swift`. **Neither app target depends on
it** (spec A35); `app/project.yml` changes only insofar as keeping that true.

```
app/Sources/RouterCore/
  JSON/       JSString.swift  JSONValue.swift  JSONParser.swift  JSStringify.swift  JSNumber.swift
  Config/     RouterHome.swift  UpstreamConfig.swift  RawServer.swift  ServerParser.swift
              ConfigLoader.swift  ConfigWriter.swift  UpstreamHash.swift  SelfReference.swift
  Manifest/   CachedTool.swift  Manifest.swift  ManifestIO.swift  ManifestStore.swift
              ToolsDigest.swift  DiffTools.swift  ToolUnion.swift  ManifestBookkeeping.swift
  Discovery/  ClientConfigs.swift  TOMLServers.swift  MiniTOML.swift
  Log/        RouterLog.swift
  IO/         FileSystem.swift  Clock.swift          (injectable seams — see P8)
app/Tests/RouterCoreTests/…  Vectors/*.json  VectorRegistry.swift
scripts/parity/generate-vectors.mjs
```

`RouterCore` depends on the MCP SDK pinned `exact: "0.12.1"` (spec A36; probe-built clean under
Swift 6 strict concurrency in 67s) for the protocol boundary type only. The SDK's `Tool` is never
the persistence type (spec A37).

---

## P1 — The JSON foundation

The first review round of this plan found the original design **architecturally wrong**, not merely
incomplete. Swift's `String` cannot carry a lone UTF-16 surrogate, and it compares by canonical
equivalence — so `"é"` and `"é"` are *equal* Swift strings and *distinct* JavaScript
keys. Storing JSON strings as `String` silently merges two keys the reference keeps apart and
changes the bytes the digest is taken over. The storage type is therefore code units, not `String`.

**`JSString`** — a wrapper over `[UInt16]`. `Equatable`/`Hashable` compare code units exactly, so no
Unicode normalisation happens anywhere. `Comparable` compares code-unit-wise, which *is*
JavaScript's `<` on strings (spec N1). Conversion to Swift `String` exists only at the API edge
where a value is handed to a caller, never on the digest path.

**`JSONValue`** — `.null`, `.bool`, `.number(Double)`, `.string(JSString)`, `.array([JSONValue])`,
`.object([(key: JSString, value: JSONValue)])`. Objects are an **ordered array of pairs**;
`JSONSerialization` and `JSONDecoder` both discard member order, and member order changes the
digest (spec N7).

**`JSONParser`** — hand-written, reproducing `JSON.parse`'s resulting object shape:

| Rule | Behaviour |
|---|---|
| Escapes first | `\uXXXX` escapes in **keys** are decoded *before* duplicate detection and before index classification. `{"a":1,"a":2}` is a duplicate |
| Duplicate keys | **Last value wins, at the first key's position.** `{"b":1,"a":2,"b":3}` → `{"b":3,"a":2}`. Neither "keep both" nor "delete and re-append" is correct |
| Index keys first | A key is an array index iff `String(UInt32(key)) == key` **and** `key != "4294967295"`. Those sort first, ascending numerically; all others keep insertion order |
| Numbers | Every number becomes IEEE-754 binary64 **at parse**. `9007199254740993` becomes `9007199254740992`; `1e400` becomes infinity, which serialises as `null` |
| Spelling discarded | `1.2300e+2` becomes `123`; escaped `/` becomes raw `/` |
| Surrogates | Lone surrogates are preserved as code units. `"\ud800"` stays a lone `D800` |

**`JSNumber`** — the ECMAScript `Number::toString` rules, which are *not* `String(n)` in every case:

| Input | Output |
|---|---|
| NaN, +∞, −∞ | `null` (this is `JSON.stringify`, not `String(n)`) |
| −0 | `0` |
| integral, \|v\| < 1e21 | no decimal point — `1e20` → `100000000000000000000` |
| ≥ 1e21 | `1e+21` — lowercase `e`, explicit `+`, no zero padding |
| < 1e-6 | `1e-7`; but `1e-6` itself → `0.000001` |
| otherwise | shortest round-trip, **JavaScript's choice among ties** — `1424953923781206.25` → `1424953923781206.2`, never `…6.3` |

Swift's `Double.description` is also shortest-round-trip but is not guaranteed to break ties the
same way, so it is a starting point that the fuzz must confirm value by value, never an assumption.

**`JSStringify`** — strings escape `"`, `\`, and controls below `0x20` using `\b \f \n \r \t` where
they exist and **lowercase** ``-style otherwise; `/`, `U+2028` and `U+2029` are emitted raw;
valid surrogate *pairs* combine into UTF-8, while unmatched units stay escaped — `"😀"`
→ the four UTF-8 bytes of 😀, but `"\ude00\ud83d"` stays `"\ude00\ud83d"`. Compact for the digest
path; a separate two-space pretty-printer for the manifest writer (spec A19).

**Stated precondition.** Every value serialised here originates from `JSON.parse` of wire or file
bytes — never a live JavaScript object. So `toJSON`, `undefined`, array holes, prototype effects,
symbol keys and `BigInt` cannot arise, and `__proto__` is an ordinary key. The review raised all of
these; they are out of scope *because of this precondition*, and the precondition is asserted at
the boundary rather than assumed.

**Verification.** Differential fuzz against real `JSON.stringify`: several thousand seeded random
values plus a fixed adversarial set — the N1 key pair, `{"b":1,"a":2,"b":3}`, `{"é":1,"é":2}`,
`"\ud800"`, `"😀"`, `"\ude00\ud83d"`, `U+000B`, `-0`, `9007199254740993`,
`1424953923781206.25`, `1e20`, `1e21`, `1e-6`, `1e-7`, `1e400`, index-like keys including
`"4294967295"` and `"01"`. Byte equality required. Any number that cannot be matched is recorded
as a **stated limit with its vector**, never quietly rounded.

---

## P2 — Config

**`ServerParser.parse(name:raw:)`** — check order is load-bearing and is: name charset → `__` →
transport selection → per-transport requirement. Returns the upstream or a reason.

*Transport selection (spec A9):* `type` if present, else `http` if a `url` key is present, else
`stdio`. An **empty-string** `url` is falsy in the reference, so `{url: ""}` with no `type` selects
**stdio**. `sse` stays `sse`; `streamable-http` becomes `http`; `http` stays `http`; anything else
is `unsupported transport "<type>"`. `isHttp` is true for every non-stdio transport (N13).

*Field mapping (spec A7)* — the whole returned value, not just the decision:

| Field | stdio | http/sse |
|---|---|---|
| `command` | required; **any non-empty string**, whitespace included | absent |
| `args` | defaults `[]` | absent |
| `env` | defaults `[:]` | absent |
| `cwd` | propagated, may be absent | absent |
| `url` | absent | required, validated for **parseability only** — `ftp://host` is accepted (N12/A10) |
| `headers` | absent | defaults `[:]` |
| `oauth` | absent | propagated, may be absent |
| `idleMs`, `startupTimeoutMs`, `projects`, `warm`, `placard` | propagated, may be absent | propagated, may be absent |

**`UpstreamHash`** (spec A11). Material is the array, serialised by `JSStringify`, then `sha256`,
hex, first 16 characters. Excluded: `name`, `idleMs`, `startupTimeoutMs`, `projects`, `warm`,
`placard`, `oauth`. stdio → `["stdio", command, args, cwd-or-null, sortedEnvPairs]`; http →
`[transport, url, sortedHeaderPairs]`, where `transport` distinguishes `http` from `sse`. **`cwd`
absent is JSON `null`, not an omitted element** — the array length is constant. `args` order is
preserved and never sorted (N2). Pairs sort by `JSString` code-unit comparison (N1).

**`ConfigLoader`** (spec A2/A3/A12/A15). Outcome is an enum: `missingFile` · `notJSON(reason)` ·
`unrecognisedShape(kind)` · `loaded(RouterConfig, skipped: [String])`, where a `loaded` config with
no servers is the legitimate empty case and is distinct from all three failures.
`mcpServers` absent → `unrecognisedShape(.missing)`; present but not an object (`"bad"`, `[]`,
`null`, `7`) → `unrecognisedShape(.wrongType)` (divergence D1, spec A3).
Skipped entries format `name (reason)` in JS enumeration order (N10). Self-references are **not**
filtered by the loader (spec A15). Unknown top-level and per-server fields are ignored. A server
whose *value* is `null` **aborts the whole load** rather than becoming a skip. Precedence is
nullish, so an explicit `0` or `""` wins (N3); defaults are `port` 8879, `host` `127.0.0.1`,
`idleMs` 300 000, `startupTimeoutMs` 60 000, and **`startupTimeoutMs` has no option-level
override** (spec A12).

**`SelfReference`** (spec A14/N9). True if the name is exactly `mcp-router` or `router`
(case-sensitive). Otherwise, if there is no `url`, false. Otherwise parse the url; on failure,
false. True only if the host is one of `127.0.0.1`, `localhost`, `::1`, `[::1]` **and** the url's
port *as reported* equals the router's port as a string — so a default port reports as empty and
`http://localhost:80` against port 80 is **false**. `127.0.0.2`, `0.0.0.0` and `mcp-router.example`
are not matches.

**`ConfigWriter`** (spec A16, divergence D3) — adopted from `src/index.ts`, disclosed as such.
Rules: read the existing file if present; **preserve every top-level key not being set**, including
`startupTimeoutMs` and unknown keys; set `port`, `host`, `idleMs`, `mcpServers`; serialise
two-space; write to `<path>.tmp-<pid>` and rename. Backup: copy the existing file to
`<path>.bak-<ISO8601-basic>` **before** the rename, keeping at most the five most recent and
deleting the oldest beyond that; **if the backup fails the write does not proceed**, and the error
names the backup path — losing the old list to save the new one is the wrong trade for a file the
user hand-edits.

---

## P3 — Manifest

**`CachedTool`** stores the tool's raw ordered `JSONValue` plus accessors for `name`, `description`
and `inputSchema`. Round-trips losslessly, member order included (spec A18). Conversions to and
from the SDK's `Tool` exist for the boundary R2 will use; a test proves an unmodeled field survives
the `CachedTool` path and is lost through the SDK path (spec A37).

**Unknown-field preservation (spec A20).** `Manifest` and `CachedServer` are *not* plain structs
with fixed keys — each keeps the ordered `JSONValue` it was parsed from and overlays typed
accessors, so a field the reference does not model survives a load/save cycle. Validation is as
shallow as the reference: `version == 1` and `servers` is an object **or an array** (`typeof [] ===
"object"`), and entries are not validated at all.

**`ManifestIO`** — `load` degrades to empty **and reports that it degraded and why** (divergence
D2). `save`: create the directory, write `<path>.tmp-<pid>`, rename over any existing file; on a
write failure **the temp file is left in place** and the error propagates, matching the reference.
Two-space pretty-print, no trailing newline (spec A19/A23).

**`ManifestStore`** — an `actor` over an injected clock and filesystem (P8). Four paths, all
required (spec A24):

| Path | Behaviour |
|---|---|
| Normal | re-read only when mtime **or** size moved |
| Failed reload | keep the previous manifest, back off **exactly 1000 ms**, do **not** record the stamp |
| Malformed at construction | `load` degrades to empty and the constructor **records that file's stamp**, so it does not retry until the file changes |
| Deleted | stamp reads empty; keep the previous manifest and do **not** clear the stamp |

The last two are latent defects in the reference, ported faithfully and reported as deferred
children.

**`ToolsDigest`** (spec A17/N6/N7) — material is, per tool, `[name, description ?? "", JSStringify(inputSchema ?? {})]`;
tools sort by name with a **stable** sort so equal names keep arrival order; the input array is not
mutated; every other tool member is ignored.

**`DiffTools`** (spec A21/A22/N11) — inspects only the **new description** of added and changed
tools; dedupes codepoints by first occurrence; emits added/changed in `after` order then removals
in `before` order; omits the old schema on a removal. The invisible set is exactly the reference's
ranges — `U+2066` is **not** among them and must not be reported.

**`ToolUnion`** (spec A27/A28/A29/N4/N5/N8) — `visibleTo`: no `projects` or an empty list → visible;
no cwd → not visible; otherwise `cwd == p || cwd.hasPrefix(p.hasSuffix("/") ? p : p + "/")`,
case-sensitive, no normalisation, so `projects: [""]` matches every absolute cwd.
`placardFor`: a **declared** placard outranks an entry error; otherwise a non-empty error becomes
one; otherwise none. `unionTools`: skip when not visible, then skip when the entry is absent or its
approved tools are empty — **before** any placard, which is what makes the error placard
unreachable through the normal failure path. Description is `[name] <own>` or the INOPERATIVE form
with its exact punctuation, where `own` is the tool's description **or its name when absent**;
`substitute` is appended only when non-empty; every other tool member is copied through.
`splitToolName` splits at the **first** separator, rejecting index ≤ 0 and either half empty.
`isStale` is true only for an absent entry, a hash mismatch, or a **non-empty** error.

**`ManifestBookkeeping`** (spec A26/N8) — the pure half of `buildManifest`, one function from
(previous entry, observation) to next entry:

| Observation | Result |
|---|---|
| No previous digest | approve: replace entry with the new tools, digest, hash, fresh `builtAt` |
| Digest equal | same as above — clears `error` and `pending` |
| Digest changed | keep approved `tools`, `digest`, `builtAt`; set `pending` to the new surface; update `hash`; clear `error` — the entry is then **not stale** |
| Failure | `tools: []`, the error, fresh `builtAt`, updated `hash` — **destroys the approved tools** |

Removed upstreams stay in the manifest; `force` bypasses staleness; the manifest is mutated in
place; processing and the `built`/`failed` lists follow upstream order.

---

## P4 — Client-config discovery

Six clients, fixed order, absent-is-normal, the router's own entry filtered out (spec A6):

| # | Client | Path | Shape |
|---|---|---|---|
| 1 | Claude Code | `~/.claude.json` | JSON `mcpServers` |
| 2 | Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | JSON `mcpServers` |
| 3 | Codex CLI | `~/.codex/config.toml` | TOML `[mcp_servers.<bare>]` |
| 4 | ChatGPT CLI | `<project>/.chatgpt/config.toml` | TOML `[mcpServers."<quoted>"]` |
| 5 | Cursor | `~/.cursor/mcp.json` | JSON `mcpServers` |
| 6 | opencode | `~/.config/opencode/opencode.json` | JSON `mcp` |

Result per client is `absent` · `unreadable(reason)` · `declaresNone` · `servers([...])` — four
distinct cases, so spec A5's "neither key shape" is `declaresNone` and is not confusable with a
parse failure (spec A4/A5).

**Both shapes in one file (spec A4), the stated rule:** parse both tables; a name in only one is
taken from that one; a name in **both** is an `unreadable(.conflictingTables(name))` for that file
rather than a silent pick, because the two tables mean the same thing and disagreeing about one
server is a config the user needs to fix, not one this code should choose between.

**`MiniTOML`** is a narrow reader, not a TOML implementation. It scans line-wise for table headers
and deep-parses only tables under `mcp_servers` / `mcpServers`, handling bare and quoted keys,
dotted headers, basic and literal strings, integers, booleans and string arrays. Anything it does
not understand — a `"""` or `'''` delimiter above all — is a **named error citing the line number**,
never a skip: a silent skip inside a config reader is the same defect class as the trap this item
exists to close. Verified against the real 24,753-line `~/.codex/config.toml` (checked: no
multi-line strings) and against fixtures transcribed from both dAIolog configs.

---

## P5 — Log

`RouterLog` as an `actor`. Line bytes identical to the reference (spec A30): a JS-style ISO-8601
timestamp **with milliseconds and `Z`** — a hand-built formatter, since `ISO8601DateFormatter`
omits milliseconds by default — then the level padded to five, the message, and `\n`. stderr only,
never stdout (spec A31). `configure` is re-enterable and can disable a previously set file, creates
the directory immediately rather than at first write, and writes stderr **before** the file (spec
A32). An **append** failure is swallowed (spec A33). `debug` computes nothing at all when verbosity
is off (spec A34). Divergences D4 and D5: directory-creation and stderr failures are contained
rather than propagated, and the API takes a structured event so no call can be handed a whole
config, env or header dictionary.

---

## P6 — Vectors, and making the corpus hard to fake

`scripts/parity/generate-vectors.mjs` requires `dist/*.js`, runs each reference function over the
corpus, and writes `app/Tests/RouterCoreTests/Vectors/*.json`. Vectors are committed; `dist/` is
not (spec A39). Re-running produces an identical file, which is itself a test.

The review's objection to the first draft was that counting vectors proves nothing — a mislabelled
or placeholder vector passes a name check, and a count can be right while cases are duplicated or
never compared. So `VectorRegistry.swift` carries, per named vector:

- the **N or D row** it exists for, and the **assertion** that consumes it — an entry with no
  consumer fails;
- a **payload fingerprint**, so a vector cannot be replaced by a copy of another;
- an **executed-case attestation**, so a decoded-but-never-compared vector fails.

And each named vector is **mutation-tested**: the build breaks the behaviour that vector guards,
the parity gate must go red, then it is restored. A vector that cannot be made to fail is a
decoration and is reported as such (spec A40).

`make` gains a `parity` target reporting the executed vector count; `make all` fails if it is below
the registry size (spec A41).

---

## P7 — Wiring and the guardrails

`Package.swift` gains `RouterCore`, its test target, and the exact SDK pin. `app/project.yml` gives
**neither** app target a `RouterCore` dependency, asserted from the generated build settings plus a
check that neither app target's sources name the config path (spec A35). A test asserts no pin
anywhere is a range (spec A36). A check asserts this branch changes nothing under `src/`,
`install.sh` or `package.json` (spec A38).

---

## P8 — The checks the reference cannot provide

Three gaps the review named, each needing a test the TypeScript oracle cannot supply.

**Divergence contracts (D1–D5).** TypeScript is not the oracle for a deliberate divergence, and
three of the five are invisible in its output. Each gets its own test: typed-error assertions for
D1 and D2; filesystem fault injection for D3 and D4 (unwritable directory, failing backup, a
process killed between temp-write and rename); and an API-surface test for D5 asserting no log
entry point accepts a dictionary or an arbitrary encodable.

**One end-to-end path.** File-disjoint agents can each pass their own tests and still disagree at
the boundary — or quietly reach for `JSONSerialization` or the SDK's decoder and bypass P1's
ordered representation entirely, which no unit test in either file would notice. One integration
test therefore runs the whole public path — parse config → hash → load manifest → apply
bookkeeping → save → reload → digest → union — over an input with **reordered object members and
unmodeled tool fields**, and asserts both survive end to end.

**Stateful traces.** `FileSystem` and `Clock` are protocols with a real and an in-memory
implementation, so `ManifestStore`'s four paths are driven as *sequences* — malformed at
construction, then corrected; loaded, deleted, recreated with identical mtime and size; failed
reload, then a retry inside the back-off window and another outside it — rather than as four
independent cases that each pass while the transitions are wrong.

---

## Execution order and delegation

P1 → P2 ‖ P3 ‖ P4 ‖ P5 → P6 → P7 → P8.

Delegation is capped at **five** implementation agents (P2, P3, P4, P5, and the vector generator),
each given the spec clauses and N/D rows it owns plus the rule tables above. P1, P6's registry and
mutation gate, P7 and P8 stay with the conductor — P1 because every parity claim rests on it, P6
and P8 because they are the checks that catch a delegated agent having quietly gone its own way,
and P7 because it is where the standing constraints are enforced.

## Definition of done

`make all` green; the parity suite executing its full registry with every vector mutation-tested
red-then-green; every clause A1–A41 with the evidence its row names; `src/`, `install.sh` and
`package.json` untouched; committed on `ai/r1` and **stopped before merge**.
