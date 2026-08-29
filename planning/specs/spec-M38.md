# M38: the staged tool diff's decision, witnessed at the catalog

**Category:** router · **Brief:** `planning/features-to-triage/staged-tool-diff-visual-review.md`
**Related:** M8 (the schema half of the diff) · M29 (the sheet and its disable write) ·
K5 (the disable write's missing witness) · R21 (approve answering 200 over a discarded write) ·
R29 (the live-reload mechanism this consumes).

---

## 1 · What the tree already holds, measured before anything was designed

The brief's acceptance sketch has five lines. Three of them are already built, and this spec says
so rather than rebuilding them:

| Sketch line | Where it lives | State |
|---|---|---|
| 1 · an Attention indicator on the server view | `MenuBarPresentation.AttentionCause.pendingChange`, `ServerRowAction.reviewHeldChange` | built (M18/M29) |
| 2 · a side-by-side comparison of descriptions **and** parameter changes | `ToolChangeCard` over `SchemaDiff.compare` | built (M8) |
| 3 · approve in one action, or keep the server held | `HeldChangeSheet` → `ServersBoardModel.approveHeldChange` / *Keep serving the old text* | built (M29) |
| 4 · **approving updates the active catalog served to connected AI clients** | — | **the gap** |
| 5 · mobile companion clients review the diff remotely | — | deferred, §5 |

So M38 is not a second review sheet. It is line 4, and the sentence the dispatch brief put beside
it: *a diff review that shows a change and then loses the decision is worse than none.*

### 1.1 · Line 4's defect: approve is the one tool-list mutation that tells nobody

`src/control.ts` calls `announceTools` from every mutation that changes what `tools/list` would
answer, and its own doc comment says *"from nowhere else"*. There are four call sites —
`:511` add, `:537` remove, `:549` re-index, `:699` the PATCH that changes what a server serves.

`POST /servers/:name/approve` promotes `entry.pending.tools` into `entry.tools`, which is the exact
member `unionTools` reads — `export function unionTools(`, `src/manifest.ts:464` at `08a24ed`. It
moves the served list by construction, and it
is **not** a call site.

What happens instead is the three-second manifest poller —
`.announceIfMoved(manifest.fileStamp(), 'the tool manifest was rebuilt outside this process')`,
`src/router.ts:502` at `08a24ed`. It notices the
file's stamp moved and announces — so the catalog does eventually reach an attached session, which
is why this reads as working. Two things are wrong with that:

- **It is not the moment of the decision.** The user presses *Accept the new text* and the tool
  list they just approved reaches their session up to three seconds later, on a timer whose whole
  stated purpose is *changes that arrive with no control-API request behind them*.
- **The reason is false.** The poller's sentence is `the tool manifest was rebuilt outside this
  process`. It was rebuilt inside this process, by a route this process answered. That line is what
  somebody reads when they ask why a model's tools changed mid-session.

### 1.2 · The decision is not read back anywhere that answers the user's question

`ControlApproveDispatchTests` A2 does read the manifest bytes back off disk — this spec does not
claim approve is unwitnessed. What no test asks is the question the user actually has, which is
**whether a session is now served the tools they approved**. The parity census says
the same thing in the repo's own words — the row `control-approve-post`,
`planning/parity/surface.tsv:48` at `08a24ed`, whose note reads *"the 200 PROMOTION path is NOT
two-router compared … a manifest-snapshotting differential helper is the missing piece"*.

That is the shape K5 named on M29's disable write and it is the same shape here: every existing
assertion reads the writer's own account, or the bytes the writer wrote, and none reads the
serving predicate.

---

## 2 · Decisions

**D1 — approve announces, and the Swift half does not.** The announce is added to `src/control.ts`
only. R29 shipped live-reload as TypeScript-only with the Swift router answering 404 for the whole
family, and that boundary is R29's, not this item's, so widening it here would be M38 building
R29's second half under M38's name. Nothing in `planning/parity/surface.tsv` enumerates the
notification stream, so this adds no divergence row and no census obligation.

**D2 — the count of notifications is not the oracle.** An arm that asserts *the attached session
was told* passes with and without the fix, because the poller supplies a notification either way.
The discriminator is the router's own log line: `live-reload: approved "<name>"'s new tool surface`
versus `live-reload: the tool manifest was rebuilt outside this process`. The count and the
observed latency are printed as corroboration and are not what the arm stands on.

**D3 — the read-back is the serving path, never the response.** `MCPEndpoint.listTools()` is what a
connected client's `tools/list` runs: `deps.manifest.current()` through `ManifestStore`, then
`ToolUnion.unionTools`. The Swift witness strikes `POST /servers/:name/approve` through the real
`ControlHandler.handle` and then asks that function, over a `ManifestStore` the control handler has
never seen. `listTools()` becomes `internal` rather than `private` to make it askable — the same
accessibility its sibling `callTool` already has for the same reason.

**D4 — the status code does not move.** R21's own instruction, and
`#expect(status == 500, "the route reports 500 when the write fails")`,
`app/Tests/RouterCoreTests/ControlApproveDispatchTests.swift:117` at `08a24ed` pins the pair it
stands beside. Nothing here touches the status code.

---

## 3 · Oracle lines

Every line is a claim something can fail on. The rung each one stands on is stated, because a line
proved only by a count is a line with no oracle.

1. `POST /servers/:name/approve` answering **200** announces `notifications/tools/list_changed` to
   every attached session. *(rung: the router's own log line, driven over a real socket.)*
2. That announcement is attributed to the approval — `approved "<name>"'s new tool surface` — and
   not to the poller's `rebuilt outside this process`. *(rung: as 1; this is the arm that fails
   without the change.)*
3. An approve that answers **409** — nothing pending — announces nothing. *(rung: absence of both
   the log line and a notification, over a window in which the manifest did not move so the poller
   cannot supply one.)*
4. The attached session's `tools/list` re-fetch after the approval carries the promoted
   description. *(rung: the SDK client's own re-fetch.)*
5. Before approval, a held surface is **not** served: the served catalog carries the approved tools
   and none of the pending ones. *(rung: `MCPEndpoint.listTools()` over `ManifestStore`.)*
6. Approving moves the served catalog to the promoted set, read through a `ManifestStore` the
   striking handler does not own. *(rung: as 5.)*
7. A sibling server untouched by the approval is served exactly what it was. *(rung: as 5. This is
   the control that makes 5 and 6 claims about *this* server: a handler that promoted the whole
   file passes them both without it.)*
8. A refused manifest write leaves the served catalog where it was **and** leaves the change
   pending. *(rung: as 5, plus `GET /servers/:name/changes` re-read after the strike. R21 read at
   the catalog rather than at the status code.)*
9. A second approve answers 409 and the served catalog does not move again. *(rung: as 5.)*

---

## 4 · What is not claimed

- **The Swift router does not announce anything**, because it has no live-reload family at all
  (R29, D1 above). Oracle lines 1–4 are TypeScript-only and say so.
- **The three-second poller is not removed.** It still covers `mcpr index` and the launchd watcher,
  which are what it was written for.
- **Nothing here re-reviews the sheet.** M8's schema diff and M29's sheet are cited as built and
  are not re-measured; §1's table is the citation, not a fresh verdict.

---

## 5 · Sketch line 5, deferred with its reason

*Mobile companion clients receive notification of pending tool diffs and can review changes
remotely* is **not built and not attempted here**. The reason is a standing constraint rather than
an estimate: `ORCHESTRATOR.md` records that **the phone queues; it never installs** — deliberately
narrower than remote control. Approving a tool surface is not a queued suggestion a person later
acts on at the Mac; it is a write that changes what every attached session is served, taken on a
device that cannot see the router's loopback control API. That is a new capability class with its
own trust boundary, and inventing it inside a review-surface item is how a control that does
nothing gets shipped.

Filed as `planning/features-to-triage/M38-phone-cannot-approve-a-tool-surface.md`.
