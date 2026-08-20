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

## Pass 2 — the diff review, and it did not happen

**Attempted on three families and delivered by none.** Recorded rather than dropped, because a
logged downgrade is a result and a silent pass is not.

| Lane | Invocation | Outcome |
|---|---|---|
| OpenAI | `codex exec -m gpt-5.6-sol -c model_reasoning_effort=high -s read-only -o /tmp/r7-codex-review.md`, alarm 900 | Killed by the alarm still enumerating the tree. Header asserted `model: gpt-5.6-sol` and `reasoning effort: high`; the log reached 328 KB of file listings and **the `-o` file was never created**. |
| xAI | `grok -m grok-4.6 --effort xhigh`, alarm 700 | Exited having written **379 bytes of narration and no finding** — three sentences about what it was going to read. |
| Google | `agy --model gemini-3.7-flash-high -p`, alarm 700, the diff **inline** so it need not explore | Exited with a **0-byte** output file. |
| OpenAI, retried once with the diff inline and "do not read any files" | `codex exec …`, alarm 600 | Same shape as the first: header correct, **no `-o` file**. |

The diagnosis for the first attempt is legible in its own log — it spent its whole budget walking
`app/Sources` rather than reading the diff it was given — and inlining the diff was the fix that
should have worked. It did not, for either of the two lanes it was tried on.

**What this costs, stated rather than waved away.** The design fork above was reviewed out of
family and the answer was taken. The **diff was not.** Every claim about this diff's correctness
rests on the gates in `R7-acceptance.md` — 1551 unit tests, 22 of them this item's, an acceptance
lane shown able to go red, a lint gate shown able to go red, and swiftlint `--strict` at zero — and
on one Claude reading its own work, which is the thing an out-of-family pass exists to distrust.
The verifier that takes this item to Done is a fresh agent from another family, and this is the
first thing it should re-do.

`codex exec` exits 0 on a usage limit and `grok` exits 0 when session init fails, so none of these
outcomes was read off an exit code. Each is read off a missing or empty output file.
