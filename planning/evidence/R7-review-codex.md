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