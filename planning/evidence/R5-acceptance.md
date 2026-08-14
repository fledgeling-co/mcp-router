# R5 acceptance evidence

**How to use this file.** One row per verifiable surface: what was verified, *how* (the actual
command, not a description of one), the commit it was verified at, and the result. Rows are
**appended, never rewritten** — an old row stays true of the commit it names.

**Read this before testing anything.** If a row exists and `git diff <that SHA>..HEAD` does not touch
the files behind it, that row **is** the evidence: skip the test and cite the row. Re-verifying a
surface nothing has changed under costs the user their time and proves nothing new.

R5 has **no UI**. It is the Swift router's OAuth flow and the two authorization routes, so the unit
of evidence here is a behavioural clause exercised over a real socket or a real filesystem, not a
screen. The Mac and iPhone authorization surfaces belong to M8 and I1 and are evidenced in their own
files.

---

## The loopback callback listener — verified at `12e1f6a`

Every row below drives a **real** `NWListener` on a real ephemeral loopback port with a raw HTTP
client that returns the bytes as they arrived, not `URLSession`. The listener that serves them is the
production `LoopbackCallbackListener`, not the test double.

| Clause | What is verified | How | Result |
|---|---|---|---|
| B65 · termination 1 | `GET /callback?code=…` exchanges the code, serves 200 + the connected page, resolves the flow | `swift test --filter codeIsExchangedOverTheWire` | pass |
| B65 · termination 2 | `?error=access_denied` serves 400 + the detail **verbatim**, rejects with that same string | `--filter providerErrorOverTheWire` | pass |
| B65, B86 · termination 3 | no code, no error: the page says `the provider returned no code` and the rejection says `no authorization code returned` — two different strings, both asserted | `--filter noCodeOverTheWire` | pass |
| B65 · termination 4 | a throwing `finishAuth` serves 500 carrying the thrown message | `--filter exchangeFailureOverTheWire` | pass |
| B65, B99 · termination 5 | the flow timeout writes **no** page, rejects `authorization timed out`, and the port stops answering | `--filter timeoutReleasesTheSocket` | pass |
| B82 | `/favicon.ico` answers 404 with **no** `content-type` and a zero-length body, settles nothing, and the real callback still lands afterwards on the same still-bound socket | `--filter strayRequestOverTheWire` | pass |
| B84 · pre-flow failure 1 | binding a port already in use throws `listen EADDRINUSE: address already in use 127.0.0.1:<port>`, and the flow closes **no** transport | `--filter bindFailureThrowsWithoutCleanup` | pass |
| B84 · pre-flow failure 2 | the URL race cleans up, closes the transport, and gives the port back to another listener | `--filter urlRaceReleasesThePort` | pass |
| B85 | a second flow takes over the same **fixed** port and its socket is the one answering | `--filter supersessionRebindsTheFixedPort` | pass |
| — | `stop()` does not return until the socket is free, across ten rebind cycles that each served a request first | `--filter stopReleasesTheSocket` | pass |
| — | a request split across two TCP segments mid-target is still answered | `--filter splitRequestIsAnswered` | pass |
| — | a connection accepted **before** `stop()` is still answered after it, as Node's `server.close()` does | `--filter lateRequestOnAnOpenConnectionIsAnswered` | pass |
| — | the bind is pinned to IPv4 loopback, never every interface; an unbindable port is refused rather than truncated | `--filter bindIsLoopbackOnly`, `--filter unbindablePorts` | pass |
| — | wire format: `content-length` counts UTF-8 **bytes**; the 404 carries neither `content-type` nor a body; the status reasons are the reference's | `--filter CallbackWireTests` | pass |

### Red-green, by mutation — verified at `12e1f6a`

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each mutation was applied
to the production source, the named test run, and the source restored.

| Mutation | Guard that fired | Result |
|---|---|---|
| `stop()` reverts to an unwaited `NWListener.cancel()` | `stopReleasesTheSocket`, `supersessionRebindsTheFixedPort` | RED |
| the loopback pin becomes `.ipv4(.any)` | `bindIsLoopbackOnly` | RED |
| `content-length` counts characters instead of bytes | `contentLengthIsBytes` | RED |
| the 404 gains a `content-type` | `notFoundBytes`, `strayRequestOverTheWire` | RED |
| the head is treated as terminated always | `requestTargetNeedsAWholeHead` | RED |
| `stop()` clears the handler as well as the listener | `lateRequestOnAnOpenConnectionIsAnswered` | RED |

The first mutation is the defect this work found. It is worth recording how it presented, because it
is the shape of bug a test double cannot have: the unwaited cancel failed **about half the time**, so
a single-rebind test passed on broken code every other run. Serving one request per cycle before
stopping — the state a *completed* flow leaves behind — made it fail 4 runs out of 4. Ten cycles then
turned "usually catches it" into "catches it".

---

## Gates — run at `12e1f6a`

| Gate | Command | Result |
|---|---|---|
| build | `cd app && swift build` | exit 0 |
| tests | `make test` | 338 executed, 52 suites, 0 failures |
| parity corpus | `make parity` | 230 vector cases compared, floor 230 |
| format | `swiftformat --lint . --config .swiftformat` | 0/113 files require formatting |
| lint | `swiftlint lint --strict --config .swiftlint.yml` | 0 violations in 112 files |
| design values | `scripts/lint/no-raw-design-values.sh` | clean |

**The `.swiftformat` trap, for whoever reads this next.** `.swiftformat` excludes `.worktrees`, and a
linting run that reports `0 files` from inside a worktree has examined **nothing** while exiting 0.
On this run, from `.worktrees/R5`, it reported `113 files` and did examine them — the exclusion is
resolved relative to the config file, and a worktree carries its own copy of the config at its own
root. Check the file count, not the exit code: a `0 files` line is a failed gate wearing a pass.

## Out-of-family gate

`codex` was unavailable for this fleet: every call, down to a one-word probe, returns an
account-level usage limit that clears after this fleet's horizon. Recorded as
**`codex: usage limit → claude (downgrade)`**. The completeness critic was run instead as a fresh
`claude -p` opus-5 session, briefed adversarially — told to refute, and that finding nothing would be
a failed review rather than a pass. Its verdict is in the R5 completion note. The weakness travels
with the evidence: every reviewer in this pipeline is now Claude auditing Claude.
