---
status: retired
shipped-by: 2481e05
---

# R14 — a client's Authenticate action succeeds, and says what still needs authorising

**Status:** Untriaged
**Raised by:** the owner, 2026-08-21, from a live failure
**Category:** router

## The failure

An MCP client's "Authenticate" action against `http://127.0.0.1:8879/mcp` reports:

```
SDK auth failed: Dynamic Client Registration rejected (HTTP 404):
{"error":"not found; MCP endpoint is /mcp"}
```

It cannot succeed. The router never sends `WWW-Authenticate`, serves no
`/.well-known/oauth-protected-resource`, no `/.well-known/oauth-authorization-server` and no
`/register` — every match for that header in this codebase is the router acting as an OAuth
**client** to its upstreams. So the client runs discovery, 404s on every path, falls back to
`POST <origin>/register`, and reports the router's own catch-all 404 body.

The owner's requirement: **people will expect that auth to succeed.**

## Why a clearer error is not the fix

The obvious cheap option — keep serving no OAuth and make the 404 legible — was ruled out on
review rather than on taste. OAuth defines exactly two terminal states for a flow a client has
initiated: a token response, or an error response. There is no compliant way to answer a
user-initiated authorization request with "this resource needs no authorization" that the
client treats as success. A better-worded failure is still a failure, and the user still sees
their Authenticate action fail.

## What to build

A minimal local authorization server on the router — metadata, DCR, `/authorize`, `/token` —
that authenticates nobody and issues an opaque token. The router protects no client-facing
secret and stays loopback-bound, so the token asserts nothing it should not. Issuing an opaque
token that stands for "anonymous loopback caller" is compliant: access tokens are minted and
validated entirely by the issuing resource server.

**On success, report which upstreams still need authorising and how to fix each.**

## Surfacing — ranked, because most of these reach nobody

| rank | surface | what actually happens |
|---|---|---|
| 1 | **the `/authorize` page itself, as an interstitial** | **guaranteed human eyes.** Note the correction: the "you can close this window" callback page belongs to the *client's* loopback listener, not to us. The page the router owns is `/authorize`, so the status renders there, with a Continue that then redirects with the code |
| 2 | `initialize`'s `instructions` field | reaches the **model**, not the human — injected into the host's prompt, so "why can't you use X" gets answered correctly |
| 3 | synthetic stub tools in `tools/list` | visible in UI tool-pickers and to the model during selection |
| 4 | `notifications/message` | routed to a log file by essentially every GUI client. Not a user-facing surface |
| 5 | the `/token` response body | **discarded.** Standard OAuth libraries parse the standard fields and drop custom ones |

Use 1 and 2. The browser page is the requirement; `instructions` is nearly free and is what
makes the assistant able to answer the question rather than guess.

## The message must distinguish three states, because they are not one

Measured on this machine, 2026-08-21. 13 upstreams configured, **8 serving tools**:

| upstream | auth record | tokens | serving | what it needs |
|---|---|---|---|---|
| `mobbin` | yes | **yes**, `authorizedAt` 2026-08-20T10:56:39Z, `expires_in` 3600 | **no** | not an auth prompt — it holds a refresh token and still serves nothing |
| `pocketsmith` | yes | **no** `tokens` object, no `authorizedAt` | no | flow started, browser leg never returned. Re-run it |
| 3 others | **none** | — | no | never attempted, or failing for a non-auth reason |

A message that says "these need authorising" would be **wrong for `mobbin`** — it is
authorised, its token expired ~23 hours ago, it has a refresh token, and it is still
contributing zero tools. That is a different defect and telling the user to re-auth will not
fix it. It would also be **silent about the three** with no auth record at all.

So the report reads the actual state per upstream and names the state, not a guess:
never-authorised, half-authorised, authorised-but-not-serving, and not-an-auth-problem.

## Give the command *and* the button

The owner asked for the commands to type. Do that — a command survives the page being closed
and can be pasted later. But the browser is **already open** at that moment and the router
already owns a complete OAuth client stack (`OAuthClient`, `OAuthPKCE`, `CallbackListener`,
`AuthPages`), so the same page can carry a control per upstream that starts that upstream's
authorisation immediately. Telling someone to switch to a terminal when the machinery to do it
is already running and already in front of them is friction with no purchase.

Note the command to type is not fixed: `mcpr` is a shell function wrapping
`node ~/Dev/mcp-router/dist/index.js`, so the page should print the verb the installed entry
point actually exposes rather than assume an alias exists.

## Security requirements, concrete

**The Host check does not cover the browser threat, and the brief's first draft said it did.**
It covers DNS rebinding only. A page on `attacker.com` calling
`fetch("http://127.0.0.1:8879/...")` sends the *correct* `Host`. What protects the router today
is that MCP's JSON content-type forces a CORS preflight the router never answers — and **OAuth
removes that protection**, because `/token` and `/register` take form-encoded POSTs, which are
CORS *simple requests*: no preflight, the request executes even though the response is
unreadable. `/authorize` is a top-level navigation any page can trigger.

In importance order:

1. **Loopback-only `redirect_uri`**, enforced at registration *and* at authorize time —
   `http://127.0.0.1:*`, `http://localhost:*`, plus an explicit allowlist of app schemes if
   needed, never a remote `https` destination. This is the one that matters: without it a page
   navigates the user to `/authorize?redirect_uri=https://attacker.com/cb`, the auto-approve
   fires, and the attacker holds a code.
2. **Reject any request bearing a non-self `Origin`** on `/register`, `/token` and `/authorize`
   POSTs. Browsers attach `Origin` to cross-origin POSTs and MCP clients do not send one, so
   this closes the simple-request hole without touching CORS at all.
3. **PKCE S256 required; codes single-use, ~60s, bound to `client_id` + `redirect_uri` +
   challenge.**
4. **`X-Frame-Options: DENY` / `frame-ancestors 'none'` on `/authorize`** so it cannot be
   silently framed. Keep the existing no-`Access-Control-Allow-Origin`, never-answer-preflight
   posture on every new route.
5. **Keep the Host check on the new routes**, exact-matched against the bound authority. It is
   still what stops rebinding; it is just not the whole story.
6. **The token confers zero privilege** — `/mcp` treats bearer and bare requests identically,
   so a leaked token is worth exactly what unauthenticated loopback access is already worth.
7. `AuthPages.page(title:detail:)` interpolates into HTML and its own doc records that. Escape
   every upstream name and reason placed on the page.
8. Bound `/register` state so a looping page cannot fill the disk.

**The pre-existing exposure is larger than the new one, and should be written down rather than
introduced quietly.** Another local user or process can already POST to `/mcp` with no auth and
drive all 13 upstreams *using the stored upstream tokens*. The new authorization server adds
nothing they do not already have. The "authenticates nobody" design is sound on a single-user
machine and should say so in the docs, with `~/.claude/mcp-router/auth/` held at 0700/0600.

**The router will play two OAuth roles on one machine** — authorization server to clients, and
client to upstreams, each with a loopback callback listener. Keep the endpoint sets
unambiguous, by distinct paths exact-matched or distinct ports, so a request to one can never
be read by the other.

## Statelessness — the router has no user database

**The invariant: `/mcp` never returns 401.** A token lost to a restart must never break
connectivity, or this has built a worse failure than the dead-end it fixes.

Go fully stateless off one persisted secret (`~/.claude/mcp-router/auth/issuer.key`, 0600):

1. **`client_id` is a self-encoded signed blob** — redirect_uris inside, HMAC over the whole —
   so registrations survive restarts with no store and re-registration is idempotent.
2. **Access and refresh tokens are HMAC-signed with expiry embedded**, so a token minted before
   a restart still validates after it.
3. **Implement `grant_type=refresh_token` and actually validate the presented token.** The two
   review lanes split here: one advised minting a fresh token for any refresh request, the
   other that *an issuer accepting arbitrary garbage on refresh is the lie*. Take the second —
   validating costs nothing once tokens are signed, and the token stays truthful about what it
   means: the local user completed a loopback flow against this router. If refresh tokens
   rotate, accept the predecessor for a grace window, because clients crash between rotating
   and storing.
4. `/mcp` keeps serving whether `Authorization` is absent, empty, or carries a pre-restart
   token. **Only `/token` ever distinguishes valid from invalid.**
5. Echo the requested `scope` rather than rejecting it; derive `issuer` and the endpoint URLs
   from the port actually bound.

**Serving protected-resource metadata changes client behaviour, including for clients that are
happy today.** A spec-following client that currently connects with no auth may start acquiring
a token before connecting, or on every reconnect. That is tolerable only because the flow is
zero-interaction — so verify against real clients that it does not open a browser tab per
reconnect. Long-lived tokens plus a working refresh is the mitigation.

## The spec tension, recorded rather than resolved

The xAI lane raised a constraint the other two did not, and it cuts at the design:

> If you advertise an AS, the spec then says the MCP server **MUST** validate tokens — so
> either stay non-protected (ignore Bearer, never `401`) or actually protect `/mcp`. Do not
> mix them.

The decided design does mix them: advertise an authorization server so the client's button
succeeds, and keep `/mcp` ignoring Bearer so nothing breaks. That is knowingly outside the
letter of the spec, and it should be taken as a decision rather than discovered later as a bug.
The lane's own framing of why the button exists at all is that it is client UX — a client
assuming OAuth for every HTTP server — rather than anything the server asked for.

The honest alternatives are: accept the deviation and document it; or actually protect `/mcp`,
which means a loopback relay starts rejecting requests and every existing client breaks until
it re-authenticates. The second is a much larger change and a worse product. **Recorded as the
owner's call, not settled here.**

Three further constraints from the same lane, all cheap:

- Do not send `Access-Control-Allow-Private-Network`, and add no `OPTIONS` handler that
  blesses a web origin.
- Do not fetch a client-metadata `client_id` URL — that is an SSRF the router would perform on
  request.
- Do not put the issued token in a cookie.
- `[::1]` belongs in the loopback set alongside `127.0.0.1` and `localhost`, any port per
  RFC 8252.

Its CORS decomposition is also sharper than the second lane's and corrects it: **DCR does not
have the simple-request hole** — it is `POST application/json`, which preflights, and the
router answers no preflight. `/token` is a form POST that a page can send but cannot read.
**`/authorize` is a navigation, not a CORS request at all, and is the one that matters.**

And a concrete failure mode for the stateless design: an in-memory authorization server forgets
registrations, so after a restart the next `refresh_token` grant returns `invalid_client`, and
*some clients mark the server logged-out and stop sending tools*. That is the R14 bug returning
by another route, which is the argument for the signed-blob `client_id` above.

## Acceptance

1. A client's Authenticate action against `http://127.0.0.1:8879/mcp` completes successfully.
2. `/mcp` behaves identically before and after, with and without an `Authorization` header, and
   with a token minted before a router restart.
3. The browser page names every non-serving upstream, in the correct one of the four states,
   with the command for each — and `mobbin`'s row does **not** say "needs authorising".
4. `initialize` carries `instructions` naming the same set.
5. A request with a non-loopback `Host` is refused on every new route, proven by the same arm
   that proves it for `/mcp`.
6. A `redirect_uri` pointing at an external origin is refused.
7. The three states are derived from measurement, not from the presence of a file: a token that
   exists and does not work is not "authorised". **Staleness comes from a live probe or a stored
   expiry timestamp**, never from cached status, or the message lies in both directions.
8. A cross-origin form POST to `/token` and to `/register`, carrying a browser `Origin`, is
   refused — the route CORS preflight does not protect.
9. Reconnecting a real client repeatedly does not open a browser tab per reconnect.
10. When an upstream's authorisation lands, the router sends `tools/list_changed` so its tools
    appear without a reconnect.

## Open

Whether the `mobbin` case — a valid refresh token, no tools served — is a refresh that never
fires, an upstream that fails for another reason, or a relay defect. It is the reason state 3
exists in the table above, and it wants its own investigation rather than being folded in here.
