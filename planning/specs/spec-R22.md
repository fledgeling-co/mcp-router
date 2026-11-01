# spec-R22 — The daemon diagnostics bundle

**Item** R22, `router` lane · **Brief** `planning/features-to-triage/daemon-diagnostics-bundle-export.md`
**Requirement** REQ-035 · **Cases** CASE-0270 … CASE-0275 · **Defect filed** DEF-070

---

## 1. What this is, and the one fact that shapes all of it

The brief asks for one action that packages "recent activity logs, process execution status, and
listener state" so somebody debugging a hung upstream can attach it to a bug report instead of
assembling it by hand across four terminal tools.

Every fact it wants is already reachable. The gathering is not the problem.

**The fact that shapes the design is that `servers.json` carries live bearer tokens right now.**
W1/W2 inventoried 13 credentials across 9 configs; the migration behind Warden is prepared and
deliberately not run. So a convenience that packages the router's state into one document is a
convenience that packages its credentials into one document — and then hands it to a person whose
next action is to send it to somebody else.

That inverts the usual priority. This is a redaction feature that happens to gather diagnostics,
not a gathering feature that happens to redact, and every decision below follows from reading it
that way round.

## 2. Scope, and what is deliberately not here

Delivered: the router half — the redactor, the gathered document, and two control routes.

**Not delivered, and registered rather than dropped:**

- **R22-C1 — the menu item, the Settings action, and writing the file.** The brief's acceptance
  sketch names an Export Diagnostics action in the application menu and the settings view, a save
  panel, and a confirmation step before writing. The `router` lane's convention is the router half
  (R27, R28, R29 and R31 all shipped routes with no UI), and a rendered surface carries
  `design-review` and `be-my-witness`, which this item renders nothing for. `GET /diagnostics` is
  the preview that action would show and `POST /diagnostics/bundle` is what its confirm button
  would call.
- **R22-C2 — the archive.** The brief says "a single zip archive". The router answers one JSON
  document and the app writes it. Two out-of-family lanes were asked and both picked that split
  unprompted, on the same ground: zipping in the daemon means either a Swift zip writer or
  shelling out to `/usr/bin/zip`, and REQ-001's headline promise is that at rest this process has
  zero children. A spawn to compress a debug file is the most expensive possible place to spend
  that promise. Writing an intermediate file also leaves an unredacted-if-anything-went-wrong
  artifact in `/tmp` that nobody cleans up.

## 3. The model — two layers, and why one is not enough

### 3.1 Layer 1 is structural, and lives in the gatherer

A field whose **position** makes it secret-bearing is never placed in the document. Not gathered
and then removed — not gathered. Every `env` value, every header value, a URL's userinfo and every
URL query value.

The precedent is already here and is followed rather than reinvented: `Describe.row` emits
`envKeys` and `headerKeys` and never a value, because "this endpoint is reachable by anything that
can open a loopback socket, and a server's env is where its API keys live" (B10).

**The alternative was a deny-list of key names, and it is the wrong shape.** The configs on this
machine carry `GITHUB_TOKEN` and `NOTION_SECRET`, which a name list catches, and they equally carry
names no list can predict, because the naming is not a convention anybody agreed to. A list that is
wrong is worse than no list: it reports thorough redaction while a value walks out under a name
nobody thought of. Both out-of-family reviewers rejected it independently and in the same terms.

### 3.2 Layer 2 is by value, and covers the locations layer 1 cannot

Layer 1 is complete over the config and blind everywhere else. A credential reaches a diagnostics
export by more routes than the field it was configured in: an upstream that rejects a call and
quotes the token back in its error text, a command line carrying `--token=`, a log line somebody
wrote by hand. Those are strings the bundle has every reason to carry, and the only thing
distinguishing the secret inside one is its value.

So layer 2 knows values. Every literal the router can name as a secret — every `env` value, every
header value, every URL userinfo, and the control token — is removed from every string that
survived, and replaced with `<redacted:<key>>`, which names where the removed text came from.

**The two are not redundant and the arming pass proves it rather than asserting it.** ARM 1 removes
layer 1: CASE-0270 and CASE-0272 go red, CASE-0271 stays green. ARM 2 removes layer 2: CASE-0271
and CASE-0273 go red, CASE-0270 stays green. Disjoint. A single "no secret in the bundle" case
would have passed under ARM 2 and the second layer would have been unwitnessed while looking
guarded.

### 3.3 Three forms per needle, and the fourth that is not needed

A secret does not always reach a log line as itself: percent-encoded when it travelled in a URL,
base64-encoded when it travelled in a `Basic` credential. Both are needles.

**JSON escaping is deliberately not a fourth**, and this is the one place the implementation
departs from both out-of-family reviews, which each raised it independently. They are right that a
token containing a quote appears in the *serialised* document as `\"` and would survive a needle
search over the finished bytes. The scrub does not search the finished bytes — it walks the value
tree before serialisation, where every string is still unescaped. Scrubbing earlier removes the
whole class rather than enumerating its members.

### 3.4 The needle floor — this item's version of the vacuity rule

An `env` value of `1`, `true` or `dev` used as a scrub needle deletes every occurrence of that text
from every log line in the bundle: the timestamps, the ports, the word `device`. **The result reads
as thorough redaction and is a corrupted document, and nobody looking at it can tell which.**

So a value below 8 characters is not used as a needle, is named in `unscrubbable` with the reason,
and is still withheld by layer 1. Naming it is not a disclosure — "shorter than 8 characters" is
the whole of it — and a reader about to send the bundle on is entitled to know which values were
not swept out of the free text.

**Both reviewers proposed an entropy filter on top of the floor**, so a value like `production`
would not scrub that word out of the logs. Declined, and the reason is the direction of the error:
an over-redaction announces itself in place as `<redacted:MODE>` and a reader sees exactly what
happened; an under-redaction is silent. A second exclusion rule tuned by entropy moves values from
the first class to the second on a judgement nobody can audit from the bundle.

### 3.5 A bucket, not a character count

A withheld value is reported as `empty`, `short` or `present`.

**This deliberately differs from `ControlTokenStore.redacted`, which renders a secret as
`<39 chars>`.** That rendering is right where it is used: a log line stays on this machine, and a
length is the difference between "the token is there" and "the token is empty", which is the whole
diagnostic value a token has.

A bundle is different in the one way that matters — it is built expressly to be sent to somebody
else. An exact length is a fingerprint of the credential's *family*: 40 characters is a GitHub
classic token, 51 an OpenAI key. That tells a reader which vendor to attack and narrows nothing for
the person debugging.

### 3.6 No new optional dependency

`GET /caches`, `GET /upstreams/health`, `GET /harnesses` and the `/extensions` family each answer
503 when their one dependency is nil, because each needs a capability the handler cannot otherwise
reach. **This one needs nothing new** — the config, pool, usage store, manifest and filesystem are
all already on `ControlDeps`.

Adding an optional `diagnostics:` member for symmetry would manufacture `D-p1-a`'s exact shape — a
dependency nil in the one process that ships, invisible to every unit test — for no capability
gained. `ControlDiff` supplies its own scratch config and never drives a declared divergence, so
there is nothing to protect it from either.

## 4. The wire

Two routes, both Swift-only, both declared in `planning/parity/surface.tsv` at `c28f946ea56b06986ab008310d26c888fac15052` (historical source) as `div-r22-preview`
and `div-r22-bundle`. `src/control.ts` claims neither path in `isControlPath`, so both fall through
to `/mcp` and answer 404; there is nothing to compare bytes with, which is why the rows read
`proven-by-suite` rather than `proven`.

- **`POST /diagnostics/bundle`** — the export. **It mutates nothing and the verb is not describing
  a mutation.** Stage 2 of `ControlHandler.handle` gates the token on `POST`/`DELETE`/`PATCH` only;
  `GET` is deliberately ungated, matching the reference, and recorded there as a ported defect. So
  the verb is the only thing deciding whether this router hands its whole diagnostic corpus — log
  lines included — to any unauthenticated caller that can open the loopback port, which per
  `ControlToken` includes a web page the user merely visits. CASE-0275 pins all three answers so a
  later tidy-up that makes the verb "correct" goes red instead of silently opening the route.
- **`GET /diagnostics`** — the preview the brief's confirmation step reads. Being a GET it is
  ungated, so it is written to one rule: **it discloses nothing `GET /servers` does not already
  disclose.** Category names, counts, key names, the redaction plan. No log line, no argument, no
  value, and not even a value shape.

`/diagnostics` and `/diagnostics/bundle` are exact matches in `ControlPaths` with no prefix arm,
following R31's two: the family is closed, so `/diagnostics/anything-else` is not a route this
router answers and claiming it would turn a typo into a 405 that reads as "the method is wrong".

An unreadable log is reported as `available: false` with the reason rather than as an empty array.
A router that logged nothing and a router whose log could not be read produce the same document
otherwise, and only one of them means what the reader will take it to mean.

## 5. Evidence

| | |
|---|---|
| `ControlDiagnosticsTests` | 12 tests through `ControlHandler.handle` — the six cases plus URL sanitisation, the absent log, home elision, needle ordering, the control token, and the redaction block itself |
| `scripts/acceptance/r22-diagnostics.sh` | 23 assertions over the daemon's own socket against a credential literal planted in a real `servers.json` and a real `router.log`; enrolled in `acceptance-lanes.sh` |
| `planning/test-campaign/bin/arm-r22-diagnostics.sh` | eight arms, each watched red with the reddened cases named, plus a green baseline and a byte-identical restore |
| `planning/test-campaign/evidence/runs/r22-diagnostics-lane.log` | the lane's verdict lines with the producing command in the header |
| `planning/test-campaign/evidence/arming/r22-diagnostics.log` | the arming pass's own record |

**The socket lane is the load-bearing one**, and the reason is that the unit suite structurally
cannot be. `ControlDiagnosticsTests` drives `ControlHandler.handle` and reads the value it returns.
That is the right place to prove the redaction logic and it is one process boundary short of the
claim: the claim is about bytes that left the router over a socket, and between the handler's
return and those bytes sit the response writer, the HTTP framing, and the daemon's own wiring —
which has shipped nil twice in this repository with a green suite (`GET /registry/search` answered
502 in the only process that ships; `POST /servers/:name/auth` answered 405 until P7).

**Three things make the lane's absences mean anything**, and without all three "no secret in the
output" is satisfied by an empty file. The input is proved to contain the plant, on disk, in three
forms, before the daemon is started — a run that failed to write it would otherwise report a clean
bundle. The output is proved to be the bundle, by a public canary and the key names that must be
present. And the scrubber is proved to have had something to do, by `occurrencesRemoved` being
non-zero.

## 6. What this does not close, stated rather than implied

- **A credential written into an env KEY, or into a server's name, is covered — but only
  because the redaction block is scrubbed too.** It was not, in the first draft: the block is built
  after the document has been scrubbed, so a key path in `unscrubbable` carried the literal
  straight out, reopening at the last line of `bundleValue` the hole the pass exists to close. That
  is Gemini's vector D arriving by a route neither of us was looking at. `R22-f` fails when the
  block is appended raw, and `ARM 8` is what found it.
- **A token minted after the config was written has no needle.** `AuthStore` exposes `hasTokens`
  and `authorizedAt` and no way to read a value, so an OAuth access token the router obtained this
  morning is not in the needle set. Layer 1 still covers it — the bundle never reads the auth
  directory — so the residual is narrow and specific: an upstream that quotes a *runtime* token
  back inside an error string. Gemini raised this as vector F and it is the one item from either
  review left open rather than built.
- **Truncated tokens.** A JWT cut at a ring-buffer boundary does not match its own needle. Prefix
  matching was proposed and declined: a 16-character prefix match over a bundle redacts
  non-secrets, and this repository refuses heuristics that make a report disagree with the file.
- **`GET /servers` publishes argv whole.** Filed as **DEF-070**, not fixed. That route is
  reference-diffed and its ungated GET is itself a ported defect; redacting args there moves a
  surface R4 compares byte for byte, so closing it means changing both routers or declaring a
  divergence, and that is the owner's call. Within this item's own document, args go through the
  value scrub.
- **The lane is the portable floor.** It greps bytes off a socket. It does not observe the
  filesystem read at the kernel boundary, and no case here claims to.
