# Plan: the phone-to-Inbox route

Status: plan only, no code. Owner decision 2026-10-19: build it.
Tree for every citation: `ba0674b8`.
Sources: `planning/plans/plan-pairing-handshake.md` (the transport this builds on),
`planning/specs/spec-M6.md` (the Mac Inbox and its accept path), `planning/specs/spec-I3.md`
(the phone queue), `planning/specs/spec-I6.md` (the arrival banner), `planning/features-to-triage/WIN10-windows-inbox-board-and-review-sheet.md`,
`planning/features-to-triage/WIN22-windows-toast-notifications-for-waiting-decisions.md`, `DESIGN.md` §9.

## Outcome

A phone that has paired with the router sends its queued picks over the pairing listener. Each
send is signed by the phone's own key. The router stores what arrives, resolves each pick against
its own registry, and holds it in a 0600 file until the Mac or Windows Inbox reviews it. An accept
is a human click at the Mac or Windows, and it is the only way a server gets declared. The phone
never triggers an install, and nothing in the submit path can declare one.

Today the route has no live end at either side:

| Layer | Today | Anchor |
|---|---|---|
| Phone commit | Writes to a local file only. No network send. | `app/Sources/MCPRouterUI/Phone/Discover/DiscoverModel.swift:152` at `ba0674b8` reads `public func enqueue(_ entry: RegistryEntry) async -> Bool {` |
| Phone queue store | Local JSON in Application Support, atomic write | `app/Sources/MCPRouterKit/Discover/CapabilityQueue.swift:97` at `ba0674b8` reads `public actor FileCapabilityQueueWriter` |
| Router pairing listener | Live: started by the router when `pairing.enabled` is set | `src/router.ts:552` at `ba0674b8` reads `pairingListener = await startPairing(cfg.pairing` |
| Mac Inbox, Release | No transport. Always empty and unpairable. | `app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift:87` at `ba0674b8` reads `case .noTransport: NoTransportInboxService()` |
| Windows Inbox | Sample data only | `app/windows/MCPRouter.Shell.Model/Inbox/InboxBoardModel.cs:22` at `ba0674b8` reads `public void PopulateSampleData()` |

The phone's transport is not missing. `NetworkPairingTransport` and `LivePairingService` exist
and the Release phone uses them (`app/MCPRouterIOS/MCPRouterIOSApp.swift:42` at `ba0674b8` reads
`private let pairing: any PairingService = PhonePairingFactory.makeService(`). The acceptance
lane's header says the production transport "is B5 and is not merged". That line is stale, and
it is listed in section 10.

## 1. Transport: how a phone submits a pick

**Recommendation: a second frame set on the existing pairing listener, on a new connection,
authenticated by a challenge the phone signs with its pairing key.** No new port, no new
listener, no unauthenticated route.

### 1.1 Why the existing channel, and why it is not enough alone

The TLS pin is server authentication only. The router holds a self-signed certificate and has no
client certificate, so TLS tells the router nothing about which phone is connected. The phone's
identity comes from the signature it makes, not from the socket. The listener already keeps the
confirmed phone's public key in `paired-phones.json` (`src/paired-phones.ts:27` at `ba0674b8`
reads `export function appendPairedPhone(dir: string, phone: PairedPhone): void {`), and the
phone already holds the private half in the Keychain (`app/Sources/MCPRouterKit/Pairing/PhoneKeyStore.swift:56`
at `ba0674b8` reads `query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
Both halves exist. The submit is the first thing to use them after pairing.

Pending phones (accepted but not yet acked) hold no key on the router side. They never reach
`paired-phones.json`, so a pending phone cannot submit.

### 1.2 Frames

This plan amends the closed message set in `plan-pairing-handshake.md` §2.4. That section says
"Nothing else is accepted on this listener". After this plan, the listener accepts four more types,
and only as described here. The pairing frames keep their 4096-byte cap. The inbox frames take a
separate cap, `INBOX_FRAME_MAX`, because a batch of picks does not fit in 4096 bytes.

| Frame | Direction | Fields | Rule |
|---|---|---|---|
| `inbox.hello` | phone → router | `type`, `v`, `phoneId` | `phoneId` must name a confirmed phone. Otherwise `inbox.refused` with `unknownPhone`. |
| `inbox.nonce` | router → phone | `type`, `v`, `nonce` | 32 random bytes, base64url. Single use, valid 60 seconds, bound to this connection. |
| `inbox.submit` | phone → router | `type`, `v`, `phoneId`, `nonce`, `items`, `sig` | `items` is a **string** holding the JSON array, so the signature covers the exact bytes. `sig` is ECDSA P-256 SHA-256, DER, base64, over the signed string in 1.3. |
| `inbox.receipt` | router → phone | `type`, `v`, `received` | One entry per item: `{ id, state }`, where `state` is `waiting` for a new row and `duplicate` for a row already held. |
| `inbox.refused` | router → phone | `type`, `v`, `reason` | `unknownPhone`, `badSignature`, `staleNonce`, `badRequest`, `tooManyItems`, `frameTooLarge`, `unsupportedVersion`. |

Limits, all checked before the body is read where the frame allows it: `INBOX_FRAME_MAX` 65536
bytes; at most 50 items per submit; `id` and `displayName` at most 200 characters; `queuedAt` a
valid instant. A connection is held for at most `PAIRING_IDLE_MS` (`src/pairing-listener.ts:37`
at `ba0674b8` reads `export const PAIRING_IDLE_MS = 15_000;`), and the same idle reset applies here.

### 1.3 The signed string

```
mcp-router-inbox-v1 \n <nonce> \n <phoneId> \n <sha256-hex of the UTF-8 bytes of items>
```

The router rebuilds this string from the frame it received and verifies `sig` with the phone's
stored SPKI key. The phone signs the same string. Both sides' vectors live in
`planning/pairing/wire-vectors.json`, which is the file §2.4 already names, so a change to the
string changes the vector and both sides' tests together.

### 1.4 What the router does with a valid submit

Verification comes first, then the store write, then the receipt. The store write is what makes
the receipt true: a receipt is sent only after `inbox.json` has been written, so a dropped receipt
means the phone re-sends and the router answers `duplicate`. Nothing is declared on this path.

## 2. Router side

### 2.1 The store

`ROUTER_HOME/inbox.json`, mode 0600, written through a temporary file and renamed, the same
discipline `appendPairedPhone` uses (`src/paired-phones.ts:27` at `ba0674b8` reads `export function appendPairedPhone(dir: string, phone: PairedPhone): void {`). `ROUTER_HOME` is defined at
`src/config.ts:111` at `ba0674b8`, reads `export const ROUTER_HOME = process.env.MCP_ROUTER_HOME || join(homedir(), '.claude', 'mcp-router');`.

One row per pick:

| Field | Source |
|---|---|
| `id` | The phone's `QueuedCapability.id`, which is the registry entry id and the dedup key |
| `phoneId`, `deviceName` | The confirmed phone that sent it |
| `queuedAt`, `receivedAt` | The phone's queue time and the router's receipt time |
| `state` | `waiting`, `accepted` or `declined` |
| `resolved` | The router's registry entry for `id`, or `null` (a Partial row) |
| `reviewDigest` | SHA-256 of the canonical JSON of `resolved`, or of nothing for a Partial row |

Dedup is on `id`. A second submit of the same `id` returns `duplicate` and keeps the first row,
including its first `resolved`. That is the same rule `CapabilityQueue.swift` applies to a second
tap (`app/Sources/MCPRouterKit/Discover/CapabilityQueue.swift:123` at `ba0674b8` reads the comment
"Idempotent on id: re-queueing an entry keeps the original"). The reviewer therefore
sees one row, and the first snapshot is the one they reviewed.

### 2.2 Resolution

The router resolves `id` against its own registry, not against anything the phone said. The phone
sends only the coordinate, which is the rule in `app/Sources/MCPRouterKit/Inbox/InboxModels.swift:19` at `ba0674b8` reads "A
coordinate, never a description". The registry is an upstream index, so resolution is a live
lookup at submit time.

There is no by-id lookup today. `/registry/search` is the only registry route
(`src/control.ts:1039` at `ba0674b8` reads `if (p === '/registry/search' && req.method === 'GET') {`),
and it searches by query. Build item IB3 adds `lookupRegistryEntry(id)` beside `RegistryEntry`
(`src/registry.ts:39` at `ba0674b8` reads `export interface RegistryEntry {`). If the lookup fails,
the row is stored with `resolved: null`. That is the Partial state the Mac already draws
(`app/Sources/MCPRouterKit/Inbox/InboxService.swift:37` at `ba0674b8` reads "Items arrive
resolved.").

### 2.3 Routes for the Mac and Windows

All are on the loopback control API, behind the control token. Every method is gated, GET
included, because the list names what is waiting. This is the same rule the pairing routes use
(`src/control.ts:530` at `ba0674b8` reads `if (mutating || p.startsWith('/pairing/')) {`).

| Route | Effect |
|---|---|
| `GET /inbox` | The rows: `id`, `deviceName`, `queuedAt`, `state`, `resolved`, `reviewDigest`. Never a key, never a phone id beyond `deviceName`. |
| `POST /inbox/:id/accept` | Body `{ reviewDigest }`. Declares the server, then sets `accepted`. Section 2.4. |
| `POST /inbox/:id/decline` | Sets `declined`. Nothing is declared. |
| `POST /inbox/:id/restore` | Sets `waiting` again. Undo for a decline. |
| `DELETE /pairing/phones/:phoneId` | Removes a confirmed phone and its key. **Required before the listener serves inbox frames.** See section 7. |

Undo for an accept is `DELETE /servers/<name>`, which already exists (`src/control.ts:633` at
`ba0674b8`, `if (!sub && req.method === 'DELETE') {`). `planning/specs/spec-M6.md:221` at `ba0674b8`
reads "Declining returns the item to the queue", and the next line says accepting removes the
server that was added, so the undo is already the M6 design.

### 2.4 What accept does

This is the part the owner's brief describes as "QUEUES an install for review". My reading, and
the one this plan builds, is that the Mac or Windows reviewer's accept is the human decision. It
is not a second queue. The existing Mac accept already works this way: it calls
`ControlAPIClient.add(_ server: NewServer, force: false)` once, after the reviewer has seen the
capability statement (`planning/specs/spec-M6.md:205` at `ba0674b8` reads "Accepting calls").
The alternative, a second Mac step that applies an approved item, is decision D6.

Accept runs in this order, and every refusal leaves `inbox.json` unchanged:

1. The token is checked (401 otherwise).
2. The row must be `waiting` (409 `notWaiting` otherwise).
3. `resolved` must not be `null`. A Partial row cannot be accepted (422 `unresolved`).
4. The body's `reviewDigest` must equal the stored one (409 `reviewChanged`). This is the check
   that the reviewer accepted what is stored, and it catches a row that was replaced between
   view and accept.
5. The declaration is built from `resolved.install` and must need no credentials (D8). Otherwise
   422 `needsCredentials`.
6. The server is declared through the same code path as `POST /servers`
   (`src/control.ts:577` at `ba0674b8` reads `if (p === '/servers' && req.method === 'POST') {`).
   It is called **in-process**, not over HTTP. A name that already exists answers 409, and that
   is returned as `alreadyDeclared` (422 is wrong for this, it is 409).
7. Only after step 6 succeeds is the row set to `accepted`. If the write after the declaration
   fails, the next accept finds the server already declared and reconciles the row to
   `accepted`. That is safe because a second declaration is refused.

The declaration is built on the router, not in Swift. D7 explains why.

## 3. Phone side

### 3.1 The submitter

A new `InboxSubmitter` in `MCPRouterKit`, not in the UI. It reads the queue through
`CapabilityQueueReader.all()` (`app/Sources/MCPRouterKit/Discover/CapabilityQueue.swift:97` at `ba0674b8` reads `public actor FileCapabilityQueueWriter`, the
actor that conforms to it), takes the pairing record from `KeychainPairingStore`, and opens a
connection with `NetworkPairingTransport.connect(host:port:expecting:)`
(`app/Sources/MCPRouterKit/Pairing/NetworkPairingTransport.swift:16` at `ba0674b8` reads
`public func connect(`). The transport is the pinned one, so an identity mismatch ends the
submit exactly as it ends pairing.

The signing key comes from `PhoneKeyStore` through the same `loadOrCreate()` call the pairing
exchange already makes (`app/Sources/MCPRouterKit/Pairing/LivePairingService.swift:98` at
`ba0674b8` reads `key = try await keys.loadOrCreate()`). A submit uses the key that pairing
registered. If the key is gone, the phone cannot sign, and it says so. It does not re-pair
silently.

### 3.2 Retries and receipts

- The queue keeps every item until a `received` entry names it. Only then does the item get a
  `receiptAt`. The field is `Date?`, so a v1 queue file decodes unchanged, because a synthesised
  `Decodable` reads an absent optional as nil.
- A failed submit (no connection, a refused frame, a dropped connection) leaves the queue as it
  was. The next attempt re-sends the whole list. The router's dedup on `id` makes that safe.
- Retry is on the next foreground, on a queue change, and on a 60-second timer while the queue
  holds an unreceipted item. No exponential back-off is needed for a handful of picks. If the
  queue grows, the timer is the place to add it.
- A `refused` frame is shown. It is not retried, because a `badSignature` or `unknownPhone`
  will not change on retry. The phone shows the reason and the remedy: re-pair.

### 3.3 What the phone shows

The Queue screen (`app/Sources/MCPRouterUI/Phone/Queue/QueueScreen.swift:77` at `ba0674b8` reads `try await queue.enqueue(item)`, the writer it calls)
shows an item as "Sent, waiting on your Mac" once it has a receipt, and as "Queued" before that.
The phone does not claim the Mac accepted anything. It learns nothing about the Mac's decision in
v1. D9 covers that.

## 4. Mac and Windows boards, and notifications

### 4.1 Mac

- A `RouterInboxService: InboxService` conforms to the protocol at
  `app/Sources/MCPRouterKit/Inbox/InboxService.swift:41` at `ba0674b8` reads `public protocol InboxService: Sendable {`. Its `snapshot()` reads `GET /inbox` over
  loopback and returns `InboxSnapshot` (`InboxService.swift` declares `InboxSnapshot` beside the protocol).
  Its `availability()` returns `.available` only when the router reports the listener is up.
- `ShellPairingFactory` selects it for Release in place of `NoTransportInboxService`
  (`app/Sources/MCPRouterUI/Shell/ShellPairingFactory.swift:87` at `ba0674b8` reads `case .noTransport: NoTransportInboxService()`). The fixture stays Debug-only.
  `NoTransportInboxService` stays in the tree for a router that has no pairing configured.
- Accept and decline call the routes in 2.3. The accept button sends the `reviewDigest` it
  displayed. The row's `resolved` is what the sheet renders, through `RegistryCapability.statement(for:)`,
  so the sheet still derives the capability text from the entry the router resolved.
- The review sheet keeps the existing provenance line and the `Decline` action (`planning/specs/spec-M6.md:195`
  at `ba0674b8` reads "The review sheet").

### 4.2 Windows

- A `RouterInboxService` in `app/windows/MCPRouter.Shell.Model/Inbox/` uses the control client
  that already exists for the checks (`app/windows/MCPRouter.Checks.Model/ControlClient.cs`). It
  replaces `PopulateSampleData` in release builds. The sample data stays behind a debug flag, the
  way the Mac's fixture does.
- `PairedDeviceName` (`app/windows/MCPRouter.Shell.Model/Inbox/InboxBoardModel.cs:12` at
  `ba0674b8` reads `public string? PairedDeviceName { get; set; } = "Luke's iPhone";`) comes from
  the router's `deviceName`, not from a default. The Mac already refuses a default name
  (`app/Sources/MCPRouterKit/Inbox/InboxService.swift:18` at `ba0674b8` reads "Not a default string"), and Windows should match it.

### 4.3 Notifications

No new notification path. The Mac's arrival banner is driven by `InboxArrival`, which computes a
delta between two snapshots (`app/Sources/MCPRouterKit/Inbox/InboxArrival.swift`). The app-lifetime
poll that already runs (`planning/specs/spec-I6.md`, "app-lifetime poll") feeds it. Windows
toasts (WIN22, `status: completed`) take the same delta rule: one toast per delta, never one per
item, as `spec-I6.md` states for the Mac (line 238, "One notification per delta"). The banner
names the device and the capability statement, and `spec-I6.md` already requires that the
statement come from the resolved entry, not from the phone's text.

## 5. Test plan

Each test is written first and watched fail on a mutant before the code it tests exists. A
mutant that stays green is a finding, not a pass.

**TypeScript (`npm test`).**

- `test/inbox-store.test.ts` (new): the file is written 0600; a re-submit keeps the first
  `resolved`; a write that fails leaves the previous file whole; Partial rows are stored and
  refused on accept.
- `test/pairing-listener.test.ts` (extended): an unsigned submit, a submit signed by a pending
  phone, a submit with a stale or replayed nonce, a tampered `items` string, and an oversized
  frame are each refused with the named reason. A valid submit gets a receipt only after the
  store write.
- `test/inbox-routes.test.ts` (new): every `/inbox` route refuses without the token; accept
  refuses on `reviewDigest` mismatch, on a Partial row and on a duplicate name; accept with a
  valid digest declares once; decline and restore never touch `servers.json`.
- Mutants, each must go red: (a) the submit verifies no signature; (b) the submit calls the
  declaration; (c) accept skips the digest check; (d) the store is written 0644; (e) the receipt
  is sent before the store write.

**Swift (`swift test -j 4`, filtered to the new suites).**

- Codec: the signed string and the frame encoding match `wire-vectors.json` byte for byte.
- `InboxSubmitterTests` against an in-memory transport (the same seam the pairing tests use):
  a refused submit leaves the queue unchanged; a dropped receipt re-sends and leaves one row; a
  receipt sets `receiptAt` and nothing else; an absent key fails visibly.
- Mutants: (a) send before sign; (b) clear the queue before the receipt arrives. Both must go red.
- `RouterInboxServiceTests` against a recording control client: `snapshot()` maps rows to
  `InboxItem`, and an unreachable router produces the `failed` state, not an empty inbox.
  This is the mutant that matters most. An empty result on failure would read as "nothing
  waiting".

**Windows (`dotnet test`).** `InboxBoardModelTests` and `InboxPresentationTests` against a fake
control client. The release path must not construct `PopulateSampleData`.

**Acceptance lane.** Extend `scripts/acceptance/pairing-loopback.sh` (and its driver
`scripts/acceptance/pairing-loopback.mjs`) with a submit round trip. After the existing pairing
checks:

1. The phone submits two picks, one of them unknown to the registry.
2. `GET /inbox` shows two rows, one Partial, with the file at mode 0600.
3. `servers.json` is unchanged after the submit (this is the no-install proof).
4. A token-holder accept declares the resolved row once; a second accept gets 409 and no second server.
5. A submit signed by a revoked phone is refused.

Mutants run by hand, as `PAIRING_LOOPBACK_MUTANT` already does: `skip-sig` and `declare-on-submit`.
Both must go red. The lane's header describes its phone as a Node stand-in. That stays. A second
run with the Swift `LivePairingService` on the macOS host, against the same loopback router, is the
proof that the production phone speaks the frames, and it runs as a host test, not in the enrolled set.

**What the lanes do not prove.** The LAN, Bonjour, the iOS binary and the Windows client over a
real network. Those need a second device, as `plan-pairing-handshake.md` §7 already says.

## 6. Build items

Each item merges on its own. Sizes are S or M. Dependencies are the items that must land first.

| # | Size | Item | Depends on |
|---|---|---|---|
| IB1 | S | Router inbox store (`inbox.json`, 0600) and `GET /inbox`, token-gated, no submit path yet. | — |
| IB2 | S | `DELETE /pairing/phones/:phoneId`: revoke a confirmed phone and its key. Blocks IB3 by design. | — |
| IB3 | M | `lookupRegistryEntry(id)` in `src/registry.ts`. Partial row when the lookup fails. | IB1 |
| IB4 | M | Listener inbox frames: hello, nonce, submit, receipt, refused. Signature check, limits, dedup, store-then-receipt. Wire vectors extended. | IB1, IB2, IB3 |
| IB5 | M | Phone `InboxSubmitter`: codec, signing, retry, `receiptAt`, "Sent" state on Queue. Host-tested against an in-memory transport. | IB4 (vectors) |
| IB6 | M | Router accept, decline, restore routes; the declaration built from `resolved.install`; digest check; `alreadyDeclared`. | IB1, IB3, D6, D8 |
| IB7 | M | Mac `RouterInboxService` replaces `NoTransportInboxService` in Release. Board and arrival banner unchanged. | IB1, IB6 |
| IB8 | M | Windows live Inbox source and toasts. Sample data behind a debug flag. | IB1, IB6 |
| IB9 | S | `pairing-loopback.sh` submit round trip and mutants (section 5). | IB4, IB5, IB6 |
| IB10 | S | Phone decision status (D9), only if D9 says yes. | IB6 |

IB1 and IB2 can run in parallel. IB5 can start as soon as the vectors from IB4 are drafted, since
the vectors are the contract. IB9 is the gate on any claim that the route works end to end.

## 7. Security notes

- **Every submit is signed by the phone's key, over a nonce the router issued on that connection.**
  TLS does not authenticate the phone, so the signature is the only client authentication, and a
  submit with no valid signature is refused before any row is written.
- **Replay.** A nonce is single use and expires after 60 seconds. A captured frame cannot be
  replayed on another connection, and a re-send of a captured frame after its nonce is spent is
  `staleNonce`. A re-send of an *accepted* submit returns `duplicate`, so it cannot declare anything.
- **No install on the submit path.** The submit handler never calls the declaration code. Mutant
  (b) in section 5 proves the handler does not reach it. This is the enforcement of REQ-006,
  which says "no path from the phone or a notification can put a server on the Mac without
  explicit human review on the Mac" (`planning/test-campaign/inventory.json:1554` at `ba0674b8` reads `"text": "The phone queues; it never installs.`).
- **Accept needs the token.** The control token is a 0600 file (`src/control.ts`, `controlToken`).
  The phone cannot reach the control API, because the listener serves inbox and pairing frames
  only, and the control API is bound to loopback. A local process that can read the token can
  accept on the user's behalf, as it can today. That is an existing residual, not one this plan
  adds.
- **Revocation does not exist today.** `src/control.ts` has no route that removes a paired phone,
  and `paired-phones.json` is append-only. A lost phone stays able to submit until its key is gone
  from the router. IB2 adds the revoke route, and it lands before the listener serves inbox frames.
- **Limits against a LAN attacker.** The listener is off by default (`pairing.enabled: false`).
  When on, it accepts TLS handshakes from anyone on the network, which costs the router a handshake
  each. Caps: 8 concurrent connections, 15-second idle, 64 KiB frames, 50 items. A phone that sends
  three bad signatures in a row is refused for 10 minutes. The handshake cost is a residual this
  plan records and does not solve.
- **Storage.** `inbox.json` holds public registry metadata, phone ids and device names. It holds no
  keys, no tokens and no credentials. A copy of it submits nothing and accepts nothing.
- **Credentials.** No credential travels in any frame or route in v1. Entries that need one are
  refused (D8). If that changes, the value goes to Warden, not the loopback body, per the Warden
  rule in the operator's CLAUDE.md.
- **The phone's key is per device.** A restored or migrated phone cannot sign, because the Keychain
  item is `ThisDeviceOnly`. It re-pairs. It does not inherit a key.

## 8. Decisions

**Owner decisions**

- **D6, accept semantics.** Option (a): accept declares the server at once, as the Mac does today,
  and undo removes it. Option (b): accept marks the row approved, and a second Mac action applies
  it. My lean is (a). It keeps the human decision in one click, it is reversible through the undo
  `spec-M6.md` already specifies, and every refusal in 2.4 still runs before the declaration.
  Option (b) buys a second look at the declaration after the reviewer has
  already read the statement. That is the trade-off `planning/features-to-triage/I4-phone-direct-install.md`
  recorded as open ("whether a second confirmation on the Mac survives"). It is yours to make.
  Lane: I read the owner brief and the M6 spec, and I did not refer this to another model, because
  the call is about how much friction the owner wants, not a technical fact.
- **D8, credential-bearing entries.** Lean: refuse them in v1 with `needsCredentials`. The
  alternative is to accept a credential value over the loopback body, which puts a secret in a
  request that exists only to decide whether to declare. Option (b) would make some entries
  installable today, and that is the cost of refusing them. Yours to decide, because it is a policy on secrets.
- **D9, does the phone learn the decision.** Lean: no, not in v1. The phone shows "Sent, waiting on
  your Mac" and stops there. A status read would be a new signed route from the phone to the
  router. Option (b) would tell the phone user an item was declined, which the lean withholds.

**Technical decisions (taken here, not asked)**

- **D7, the router builds the declaration.** The Swift `RegistryCapability.declaration(for:values:)`
  (`app/Sources/MCPRouterKit/Registry/RegistryCapability.swift:247` at `ba0674b8` reads
  `public static func declaration(`) is Mac-only. Windows has no port. Building the declaration on
  the router gives one implementation for both boards. The cost is a second copy of the
  no-credential mapping in TypeScript, which D8 keeps small. A parity test pins the two.
- **D10, retention.** Keep at most 200 decided rows. Drop the oldest decided row first. Waiting
  rows are never dropped. A reviewer can always see what is waiting.
- **D11, the digest guard.** The reviewer's accept carries the digest of the row it displayed. A
  submit of an already-held `id` does not replace `resolved`. Those two rules together mean the row
  the reviewer accepts is the row they read.

## 9. Out of scope

- A relay, or any path that is not the local network. The brief's assumption is local mutual
  authorisation.
- Remote approval of a tool surface from the phone. `planning/features-to-triage/M38-phone-cannot-approve-a-tool-surface.md`
  is the standing refusal for that, and this plan does not reopen it.
- The typed-code path. It is blocked on SPAKE2 (`plan-pairing-handshake.md` B8, D2), and this plan
  uses the scan-paired phone only.
- The capability-delta gate for a new version of an installed server. Accept refuses a name that
  already exists (`alreadyDeclared`). The held-change path (`spec-M18.md`, `capability-delta`)
  owns versions. This plan does not change it.
- Any change to "the phone queues; it never installs". This plan keeps it. Section 2.4 is the
  reason it holds, and DESIGN.md §9 (`DESIGN.md:793` at `ba0674b8`, anchor `The phone queues; it never installs.`)
  stays as written. `planning/features-to-triage/LEDGER.md:150` at `ba0674b8` reads "any change there must amend that line in the open first". None is proposed here.

## 10. Stale references found while planning

These are not fixed by this plan. Each needs its own correction.

- **REQ-006 cites DESIGN.md lines 348-351.** Those lines now hold the sidebar readout card text.
  The boundary is at line 793. The inventory row (`planning/test-campaign/inventory.json:1552` at `ba0674b8` reads `"id": "REQ-006",`)
  should be re-pointed by the register, not by this plan.
- **The pairing acceptance lane's header says the production transport "is B5 and is not
  merged".** `NetworkPairingTransport` and `LivePairingService` exist, and the Release phone builds
  them through `PhonePairingFactory`. The header describes the state before B5 merged.
- **`plan-pairing-handshake.md` §2.4 says "Nothing else is accepted on this listener".** Section 1.2
  amends that sentence. The plan should be edited when IB4 lands, not before.

## 11. Verification for this plan

This change is a plan file only. No code, no test and no configuration is changed, so `npm test`,
`npx tsc`, `swift test` and `make test` were not run for it. The gates that apply to a plan are
`planning/citation-gate.py` and `planning/instrument-census.py`, and their output is quoted in the
report that accompanies this commit.
