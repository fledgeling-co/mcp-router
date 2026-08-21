# R7 — the out-of-family lane

Two passes, both `gpt-5.6-sol` at `model_reasoning_effort=high`, read-only sandbox. The writer here
is Claude, so the reviewer is not. Header asserted rather than assumed: `model: gpt-5.6-sol` and
`reasoning effort: high` were both matched in the run log, and the output file was checked non-empty
and freshly written, because `codex exec` exits 0 on a usage limit.

## Pass 1 — the design question the brief handed to this item

The brief left one thing undecided: whether the `mcp-remote` shim is presented as
routed-with-a-qualification or as its own state. It was put out of family with the §1.2
measurements attached and the two options in the brief's own words. **Taken in full**, including
the refinement this spec did not have — capability as a separate three-valued field that changes
the remedy rather than the state, which is what makes `.unknown` answerable for opencode.

---

Pick **A**.

“Via stdio shim” is materially different from direct HTTP: it adds a child process—the exact overhead the router is meant to eliminate. Calling it merely “routed” hides an actionable defect and weakens the board’s purpose.

Model only what is observed:

- **Measured HTTP-capable:** “Via stdio shim” → remedy: “Switch to `httpUrl` and remove the shim.”
- **HTTP capability unknown:** keep the same observed state, but change the action to: “Check for native streamable HTTP support.” Do not imply the shim is necessary or removable.

So capability should be separate metadata with values such as `supported`, `unsupported`, and `unknown`. The board state describes current wiring; capability evidence determines the remedy. Unknown capability does not require a fifth state.

There is a better third design: separate the board into orthogonal dimensions:

1. **Route:** not wired / direct HTTP / stdio shim  
2. **Duplicate upstreams:** yes / no / unknown  
3. **Native HTTP capability:** supported / unsupported / unknown

That is cleaner because duplicate direct upstreams can coexist with either HTTP or shim routing—it is not truly an alternative transport state. If the UI must retain exactly four headline states, use A, but derive the fourth “duplicate upstreams” presentation as a higher-priority warning layered over the underlying route. This preserves truthful observations, avoids invented process counts, and always gives the user an evidence-appropriate next action.
---

## Pass 2 — the diff review, re-run in the gap-fix, and delivered by all three

**The first attempt's record was wrong, and being wrong about that outranked every defect it
missed.** It recorded three families attempted and none delivering. The verifier re-ran the same
three and all three delivered; so did this gap-fix. **Both original failures were operator error,
not lanes being down.**

| Lane | Invocation | Outcome |
|---|---|---|
| OpenAI | `codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only -C <worktree> -o …`, alarm 900, prompt inline | **4,578 B.** Header asserted in the log: `model: gpt-5.6-sol`, `reasoning effort: high` |
| xAI | `grok -m grok-4.6 --effort xhigh -p "<prompt>"`, alarm 900 | **4,750 B**, after an early ~200 B of narration. That early write is what the first attempt mistook for the whole output |
| Google | `agy --model gemini-3.7-flash-high -p "<prompt>"`, alarm 900 | **5,371 B** |

Two diagnoses, both mechanical. `codex exec` refuses instantly with *Not inside a trusted
directory* when launched from `/tmp`, writing no `-o` file at all; `-C <worktree>` fixes it, and
the first attempt's 328 KB of file listings was a *different* failure — a lane sent to explore a
tree rather than handed the diff. Passing the diff **inline** and forbidding exploration is what
makes all three finish inside the alarm. An absent or empty `-o` file is a lane failure; a small
early write is not, and neither is a lane that has not finished.

Raw outputs: `planning/evidence/R7/gapfix-review-{codex,grok,agy}.md`.

### What they found, and what was done with it

**All three independently named the same top defect**, and it was one the gap-fix had already
introduced while closing F1: the `httpUrl` widening was applied to **every** harness rather than to
Gemini. codex — *"Those harnesses do not necessarily interpret `httpUrl`… Recognize `httpUrl` only
for harnesses confirmed to support it."* grok — *"Global `httpUrl` is how you get a false route."*
agy reached the same conclusion from the other end, confirming the canonicalisation could not leak
outside the R7 path but flagging its blast radius. **Taken in full**: `HarnessDialect` is now
per-client, on the same rule `HTTPCapability` follows, and a Cursor entry carrying Gemini's key
reads `not-wired` with a test that says why.

Taken, in the order they were filed:

| Finding | Lane(s) | Action |
|---|---|---|
| The dialect applies to every harness — F1 inverted, and it could delete a stdio server the harness really runs | all three | **Taken.** `HarnessDialect.known(for:)`, per client, with two tests |
| A truthy non-string `url` shadows a real `httpUrl` and coerces to `"true"` | codex | **Taken.** Endpoints must be strings |
| `canonicalised` leaves `httpUrl` beside the injected `url` | grok, agy | **Taken.** It now emits one endpoint under one key |
| `raw.member(key)` in one place and `members.first(where:)` in another disagree on a duplicated key | grok | **Taken.** One lookup |
| The stdout exclusion drops the whole line, so `try data.write(to: t) // FileHandle.standardOutput` erases itself | codex, agy | **Taken.** The printing call is neutralised *within* the line, not the line dropped |
| `code_of` misses block comments, and rule 2 read the unfiltered file | codex, grok, agy | **Taken.** Comments are blanked (numbers preserved) and both rules read code |
| `code_of "$f" \| grep -q` can SIGPIPE under `pipefail` and silently un-find a match | codex | **Taken.** Captured, then matched with a here-string |
| `FileHandle.init(forWritingTo:)` does not match a token anchored on the type name | grok | **Taken.** The vocabulary is argument labels, so every spelling matches |
| `forUpdatingTo:`, `forUpdatingAtPath`, `OutputStream(url:)` missing | codex, grok, agy | **Taken**, plus `/bin/cp`, `/bin/mv`, `/usr/bin/tee` |
| P5 passed for the wrong reason — its plant also carried `handle.write(data)` | codex | **Taken.** P5 and the new P8 each carry exactly one write token |
| The read-only assertion greps for one token a rewrite could preserve | codex, grok | **Taken**, both passes. sha256 over every fixture — which also closes `D-r7-j` |
| `gemini_plan`'s awk runs to EOF if a block's footer is missing | grok, agy | **Taken**, bounded at the next unindented line rather than agy's proposed regex, which eats the footer |
| Pass 5 accepts any non-empty `unreadable`, including `"ok"` | grok | **Taken.** The wire's sentence must appear verbatim on the screen, and the whole empty row is pinned |
| The lane never exercises an `httpUrl` duplicate on the wire | agy | **Taken.** A fourth duplicate, matched on identity, in pass 4 |

Overruled, with the reason:

- **"Widen rule 3 to `MCPRouterCLI/*.swift`"** (grok). Not taken: `ImportVerb.swift` legitimately
  writes `~/.claude.json` through the `install-entry` path, which is pre-existing parity-locked
  behaviour, so that widening turns the gate red on shipped code. grok's own alternative — *"keep
  `D-r7-m` and stop citing this script as the reason an applier cannot land"* — is what was done:
  the gate's header, `spec-R7.md` §7 and the ledger row now all state what it does check, and the
  selftest asserts the miss.
- **The gate's stdout exclusion is still same-line** (grok): `let h = FileHandle.standardOutput`
  then `h.write(data)` counts as a file write. Not fixed — it over-fires rather than under-fires,
  the gate prints the offending line, and closing it needs flow analysis. Registered `D-r7-q`.
- **"Mark conflicting endpoint keys unparsed rather than guessing"** (codex). Not taken here:
  nothing establishes which key `agy` itself prefers, the shape has been seen on no machine, and
  the current rule matches what `ServerParser` would do with the same bytes. Registered `D-r7-p`
  so the assumption is written down as one.

Everything the three lanes agreed on was taken. Nothing was overruled on more than one lane's
objection without the reason above.
