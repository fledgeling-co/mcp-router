# spec-R26 — Upstream auth expiry notification

**Item** R26, `router` lane · **Brief** `planning/features-to-triage/upstream-auth-expiry-desktop-notification.md`
**Requirement** REQ-034 · **Cases** CASE-0314 … CASE-0320

---

## 1. What this is, and the one fact that shapes all of it

The brief asks for a notification before a tool call fails on an expired credential: an alert when
a token is expiring or has been refused, a click-through to the server, a warning that clears when
the authorisation is fixed, and a throttle so an offline server does not spam.

R27 shipped the health machinery this sits beside and made one decision that is inherited rather
than relitigated: **a probe of a stdio upstream IS a child process**, and `README.md`'s first
guarantee — REQ-001 — is that at rest there are none. So R27's background probing defaults off and
a scheduled sweep never cold-starts.

An expiry notification looks like it has the same problem and does not have it. **It needs no
probe.** An access token's expiry is `authorizedAt + expires_in`, and both halves are already on
disk in the record this router wrote when the flow settled — `AuthRecord.accessTokenExpiry` already
computes it, for `UpstreamStateReport`'s one caller. The refusal half is the same: the manifest
already carries the error a previous index recorded, and `AuthRefusal.isRefusal` already reads it.

So R26 meets R27's rule by not needing it. **Nothing here spawns, arms a task, or holds a timer.**
That is why it is ON by default where health probing is off, and why `AuthExpiryPolicy` has no
interval: there is nothing to schedule.

The cost of that choice is stated rather than hidden. A derived expiry is what the *provider said*
when the token was issued; it is not proof the token still works. A provider that revokes early is
invisible to this feature until an index records the refusal — which is exactly why `refused` is a
notice kind of its own rather than a footnote on expiry.

## 2. The state that can say it does not know

**`unknown` is the case this item exists to keep reachable.** A token whose record declares no
`expires_in` has no derivable expiry, and the tempting reading — it has not expired, therefore it
is fine — is the vacuity class this campaign keeps finding: a state that reads healthy because
nothing measured it.

`AuthExpiryRecord.state` has **no path** from a missing number to `valid`:

| state | when |
|---|---|
| `not-applicable` | `isStdio(u) \|\| u.oauth === false` — `describe()`'s own test. No credential to expire. |
| `no-credential` | authorisable, holding no access token. A server nobody authorised is not one whose authorisation lapsed. |
| `unknown` | a token is held and its expiry cannot be derived, with `unknownReason` saying which half is missing |
| `valid` | derived, and further away than `warnWithinMs` |
| `expiring` | derived, and inside `warnWithinMs` |
| `expired` | derived, and passed |

**The state is derived, never stored** — `UpstreamHealthRecord` records the same rule for the same
reason: a stored `state` beside a stored `expiresAtMs` makes `(valid, yesterday)` representable.

On the wire an unknown expiry carries **no** `expiresAt` member at all rather than
`expiresAt: null`, for `ControlHealthJSON`'s stated reason: an absent member is not there to be
misread.

## 3. The policy, and this item's own vacuity rule

`warnWithinMs` and `renotifyAfterMs`, in a top-level `authExpiry` block. **Global only**: a warning
window is a preference about when its owner wants to be told, which is a property of the person
rather than of one upstream. A per-server override would need the writer R26-C2 needs anyway.

Out-of-range values are **refused, not clamped**, and the refusal reaches the wire carrying the
key, the value as written, the floor and its scope — R27's rule, for R27's reason: a clamp reports
60000 over a file that says 500 and the operator's next reading of their own file disagrees with
the router for a reason neither of them can see.

| key | floor | why |
|---|---|---|
| `warnWithinMs` | 60000, and **zero is not accepted** | **with a window of zero a token passes straight from `valid` to `expired`, `expiring` is unreachable, and the promise this feature exists to keep — you are told before it stops working — would hold only because nothing can enter the state it names.** R27's `tripAfter >= 2`, one item on. |
| `renotifyAfterMs` | 60000, zero not accepted | zero is not "no throttle", it is the alert spam the brief asked this not to be: a caller polling every second would raise a notification every second. |

## 4. The throttle withholds a repeat and never an escalation

The brief asks that a recurring error not spam. The naive reading — one alert per server per window
— swallows the one transition that matters. Four things make a notice due, and the first three are
why the throttle cannot hide anything:

1. nothing has been said about this server yet;
2. **the kind changed** — `expiring` becoming `expired` goes out however recently the warning did;
3. **the expiry moved** — the credential was replaced, so this is a new fact about a new token;
4. `renotifyAfterMs` has elapsed.

And a server that stops deserving a notice has its delivery record **dropped**, which is the
brief's *resolving authentication immediately clears the warning status*: a clear, not an age-out,
so the next failure is reported at once instead of waiting out six hours.

`AuthExpiryNotice.about` carries the `mobbin` rule from `UpstreamStateReport` into the
notification: with a refresh token held, **no command is offered**, because telling its owner to
re-authorise sends them round a loop that cannot succeed.

An `unknown` expiry is **reported and never notified about**. An alert every time the router cannot
compute a date is one nobody can act on and one that never stops; the inventory is where that fact
belongs, and it is never rounded up to `valid` there.

## 5. The wire

Two routes, both Swift-only, both declared in `planning/parity/surface.tsv` at `f684f3297ab0b2a5a250973440c56ae51ff04377` (historical source) as `div-r26-inventory`
and `div-r26-notify`.

- **`GET /upstreams/auth-expiry`** — every declared upstream in configuration order, with its
  derived state, the policy in force and any refusals. A `not-applicable` server is present rather
  than omitted, for the reason `div-r27-inventory` keeps its unprobed rows.
- **`POST /upstreams/auth-expiry/notify`** — the notices due now, with the throttle advanced.

**Reading and claiming are two operations on purpose.** Folding them together would make the GET
spend the notification a caller was about to be shown, so opening a settings pane would silence the
next alert — the same rule this repository enforces on its own gates.

The POST is a POST for two reasons rather than one. The verb selects the token gate, as
`div-r22-bundle` records. And unlike that route it genuinely mutates: the throttle is state held by
the daemon for the life of the process, which is why the monitor is `RouterService`'s and not built
per request.

With no monitor both routes answer **503 naming the missing capability**, the way `/harnesses`,
`/extensions`, `/caches` and `/upstreams/health` do.

## 6. Scope, and what is deliberately not here

Delivered: the router half — the policy, the derivation, the throttle and two control routes.

**Not delivered, and registered rather than dropped:**

- **R26-C1 — the desktop notification itself, the click-through and the status indicator.** The
  brief's acceptance sketch names all three. The `router` lane's convention is the router half
  (R22, R27, R28, R29 and R31 all shipped routes with no UI), and a rendered surface carries
  `design-review` and `be-my-witness`, which this item renders nothing for. It needs
  `UNUserNotificationCenter`, a notification-permission state with its own refused branch, and a
  deep link into the server detail view.
- **R26-C2 — a writer for the policy, and per-server overrides.** The config file is the only
  writer today, and `PATCH /servers/:name` is a reference-diffed route whose allow-list must not
  grow without a parity decision — R27-C1's blocker exactly.

## 7. Evidence

| | |
|---|---|
| `AuthExpiryPolicyTests` | 9 tests — refusals, both floors, and the state machine at every boundary |
| `AuthExpiryMonitorTests` | 10 tests — what is read off disk, and every term of the throttle |
| `ControlAuthExpiryRoutesTests` | 7 tests — both routes through `ControlHandler.handle` |
| `scripts/acceptance/r26-auth-expiry.sh` | 30 assertions over the daemon's own socket against records planted on disk; enrolled in `acceptance-lanes.sh` |
| `planning/test-campaign/bin/arm-r26-auth-expiry.py` | eight arms, all watched red, sources restored byte-identically |
| `planning/evidence/R26/verdicts.md` | the verdict lines with the commands that produced them |

**The lane is the load-bearing one, and its absences are paired.** The claim that expiry is derived
rather than asked has an absence in it — nothing was spawned — and an absence asserted alone is
satisfied by a feature that does nothing, which is REQ-035's recorded lesson. So the lane never
asserts one alone: the zero-children readings sit in the same run as an assertion that the reported
`expiresAt` **moved** when the planted credential record was rewritten, and every "X is not among
the notices" is read off a reply that names two other servers.

**One arm changed the work rather than confirming it.** `clamp` first reported CASE-0315's route
assertion surviving: that test injected its refusals as a literal, so it asserted the JSON shape of
a refusal and could not fail when the resolution stopped producing one. It now resolves from
configuration text.
