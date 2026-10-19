# Plan: the phone-to-Mac pairing handshake

Status: plan only, no code. Owner decision: build it now.
Sources: `planning/features-to-triage/local-network-device-pairing-handshake.md`,
`planning/evidence/I5-transport-proof.md`, REQ-015 and REQ-016 and DEF-001 in
`planning/test-campaign/inventory.json`, DESIGN.md §6 and §9, `planning/specs/spec-WIN12.md`.

## Outcome

Today the phone stores a paired-Mac record for a Mac it never contacted. I5 measured it: the
pairing call made 0 connections while the same process made 2 to the same port in the same run
(`I5-transport-proof.md`, rows 6 to 8). Nothing in either app listens for a phone. This plan
makes the TypeScript router the listener, has the phone complete a TLS exchange before it writes
anything, and makes the Mac app a client of the router over loopback only.

Ten decisions below are recommendations. Four are the owner's (D1 to D4) and one is copy review
(D5). Build items are in section 6.

## 1. Which process listens: the TypeScript router

**Recommendation: the router (`src/`) listens. The Mac app does not.**

- The router is the only process that runs without a UI. The Mac app is a menu-bar surface and
  may be closed when a phone scans. A listener in the app would be unreachable at exactly the
  moment a phone needs it.
- The router is already the authority for control state. `MacPairing.decide` decides whether a
  code is live, spent or expired. If the app decided, a phone could only pair while the app was
  open, and the spent set would live in a process that can restart.
- The loopback-only rule governs the Mac app's path to the router: it talks to `127.0.0.1:8879`
  and nothing else. That rule still holds. The pairing listener is a second socket, bound to a
  LAN address, serving only pairing routes, and off by default (`pairing.enabled: false`). The
  control API stays bound to loopback (`src/config.ts:359` defaults `host` to `127.0.0.1`).
- The Mac app learns about pairing through loopback routes it calls on the control API: issue a
  code, revoke it when the sheet closes, and list phones in `pending` and `confirmed`. There is
  no pairing route in `src/control.ts` today. That is build item B1.

**Open conflict, and it blocks the end-to-end claim.** `README.md:65` says "The two launchd
agents run the Swift router", and `ORCHESTRATOR.md:1382` records that cutover was not performed.
The brief says the TypeScript router is the only router that runs. These cannot both be true.
If the agents still run Swift, a phone reaches a process that has no listener, and every item
below is built but unreachable. This is D1.

## 2. Transport and the exchange

### 2.1 Identity

The router holds a self-signed certificate (P-256). Its SHA-256 fingerprint is the `fp` field
that `PairingPayload` already carries (`PairingPayload.swift:28-44`). The QR carries `host`,
`port`, `fp`, `code` and `exp`. The fields already exist; nothing new goes in the QR.

### 2.2 Scan path (primary)

The QR is the out-of-band trust anchor: it is shown on the Mac's own screen and read by the
phone's camera. So the phone does not need a password exchange.

1. The phone opens TLS 1.3 to `host:port`. It accepts the server certificate only if its
   SHA-256 equals the QR's `fp`. There is no CA. A mismatch is a new outcome, `identityMismatch`
   (section 5).
2. The phone sends `pair.request`: `{v, code, phoneName, phoneKey}`. `phoneKey` is the public
   half of a P-256 key the phone generates and keeps in its Keychain.
3. The router runs `decide` on `code`. A refusal returns `pair.refused` with the reason. On
   success it writes a **pending** record for the phone and returns `pair.ok: {v, macName,
   phoneId}`.
4. The phone writes its own record (section 4), then sends `pair.ack: {phoneId}`.
5. The router moves the record from pending to **confirmed**. Only a confirmed record is listed
   as a paired device.

The record is written on the phone only after step 3 succeeds, and on the router only after
step 4 arrives. A phone that drops after step 3 leaves a pending record that expires with the
code. Nothing reports as paired on either side until the round trip has completed in both
directions.

### 2.3 Typed path (blocked on D2)

A typed code carries no `fp`, so the phone cannot pin. Discovery (Bonjour, section 3) would give
an address, not an identity, and an attacker on the same network could answer in the router's
place and capture the typed code.

**Recommendation: refuse typed entry with a named outcome until SPAKE2 lands** (RFC 9382, keyed
by the eight characters, with the TLS exporter bound into the transcript so a relayed session
fails the check). The eight characters are 40 bits. The window is 5 minutes (`MacPairing.lifetime`,
`MacPairing.swift:136`), and a dictionary attack on the handshake is only bounded by an attempt
limit, which `MacPairing.decide` does not enforce today. B1 adds it: the code burns after 3 wrong
attempts.

### 2.4 Wire format

Four-byte big-endian length, then UTF-8 JSON. The `v` field is checked against
`PairingPayload.supportedVersions` (`PairingPayload.swift:33`), so a version mismatch is a named
refusal and not a parse error. Frames over 4 KiB are refused. The message set is fixed:
`pair.request`, `pair.ok`, `pair.refused`, `pair.ack`. Nothing else is accepted on this listener,
so a request to any other route gets a closed socket.

## 3. Discovery

Bonjour service `_mcprouter-pair._tcp`. The TXT record carries the Mac's display name and nothing
secret. The scan path does not need discovery at all, since the QR carries the endpoint.

Discovery matters for two things the scan path does not cover: re-finding a stored Mac whose LAN
address has changed, and the typed path once D2 lands. The router needs an mDNS responder, and
Node has none built in (D4). The phone needs `NSBonjourServices` for this type (section 5).

## 4. Storage, on each side

| Side | What | Where | Why |
|---|---|---|---|
| Phone | P-256 private key | Keychain, `ThisDeviceOnly` | Never leaves the device, never restored to another. Written first. |
| Phone | `PairedMac` record | Keychain, existing `KeychainPairingStore` (`PairingRecordStore.swift:79`) | Already `ThisDeviceOnly`. Written after `pair.ok` and after the key is stored, so a record never exists without its key. |
| Router | TLS identity (key and cert) | `ROUTER_HOME`, mode 0600 | Same as `control.token`, which is written 0600 under the same directory (`src/control.ts:47,67`). |
| Router | Paired phones: id, name, `pairedAt`, public key, `pending`/`confirmed` | `ROUTER_HOME`, mode 0600 | The router stores public keys only. A stolen router file pairs nothing. |
| Mac app | nothing secret | — | Reads the phone list over the loopback control API. |

**Deviation from the brief, for D3.** The brief names Keychain on both Apple platforms. The
router is a Node process under launchd. It can reach Keychain only by shelling out to the
`security` CLI. The control token already sets the precedent of a 0600 file. The lean is the
0600 file for the router, with the public-key-only property above doing the work Keychain would
otherwise do.

## 5. Permission prompts and copy

**iOS.** `app/project.yml` declares only `NSCameraUsageDescription` (line 106). It needs
`NSLocalNetworkUsageDescription` and `NSBonjourServices` containing `_mcprouter-pair._tcp`.
iOS shows the local-network prompt on the first local connection or Bonjour browse. The app
cannot trigger it early. Proposed copy, to go through design review (D5):

> MCP Router uses your local network to connect to the Mac you pair with. It connects only to
> that Mac.

The camera copy at `project.yml:106` is the model: one narrow use, and what does not happen.

**macOS.** The router's first listen can trigger the application firewall dialog. That dialog
names the binary that listens. Under launchd that binary is `node`, not MCP Router, and the copy
cannot change the dialog's text. So the Mac's pairing sheet must say so before the code appears,
for example: "If macOS asks whether node may accept incoming connections, allow it. Your phone
connects to this Mac over your local network."

**Unmeasured:** whether macOS 15 and later raises its Local Network privacy prompt for a
launchd-run `node` at all, and under what name. This must be measured on this machine before the
Mac copy is final. It is not established here.

**Windows.** `spec-WIN12.md:14` already specifies firewall guidance for "the incoming pairing
port", which assumes the desktop listens. That matches section 1. The Windows pairing model
(`app/windows/MCPRouter.Shell.Model/Pairing/PairingSessionModel.cs`) has no listener and no
socket code. The same wire contract (section 2.4) should serve it. Out of this plan's build
items; see B9.

## 6. What replaces the false success on the phone

Today the phone's pairing is a fixture in Release:

- `MCPRouterIOSApp.swift:54` passes `FixturePairingService()` with no configuration branch,
  beside `KeychainPairingStore()` at line 55. A Release phone writes a fixture-paired Mac into
  the Keychain. This is the I5 open finding, confirmed in the file.
- `PhoneShell.swift:63` and `:183` default to the same fixture.
- `FixturePairingService.reachability` (`PairingService.swift:141`) answers `.reachable` for
  every scenario except two.

The replacement:

1. A `LivePairingService` conforms to `PairingService`. It opens the TLS connection (section 2)
   and returns `.paired` only after `pair.ok` and a successful key and record write.
2. A factory mirrors `ShellPairingFactory` (`ShellPairingFactory.swift`). Release always gets the
   live service. The fixture exists only in Debug, selected by an environment variable. A Release
   build cannot reach it, and a test asserts the Release branch from a Debug run.
3. `reachability` becomes a real probe: a TLS handshake to the stored endpoint. `.reachable` is
   reported only after one succeeds in this session.
4. A connection that cannot be made returns `.unreachable(macName:)`, which already exists and
   already names the three causes (`PairingModels.swift`, the `unreachable` case).
5. One new outcome, `identityMismatch`, for a certificate whose fingerprint differs from the QR.
   It needs copy and an entry in `PairingOutcomeCoverageTests`. The coverage test will fail until
   both exist, which is the intended guard.

## 7. Test plan

**Swift unit (host `swift test`, no simulator).** The phone's transport is a seam, so the
exchange runs against an in-memory transport:

- No store write on a transport failure, a refusal, an identity mismatch or a version mismatch.
- The record is written only after `pair.ok`. The ack is sent only after the record is written.
- Codec: length prefix, oversized frame, truncated frame, unknown message type, bad version.
- Mutation: move the record write before the round trip. The test must go red. This is written
  first and watched fail, as the standing rule requires.

**TypeScript unit (`npm test`).**

- Issue, burn-after-3, expiry and revoke through the loopback routes (B1).
- The listener is not bound while `pairing.enabled` is false. When enabled, it binds the
  configured address, and the control API stays on `127.0.0.1`.
- A phone record stays pending until `pair.ack`. A tampered fingerprint is refused.

**One loopback end-to-end test, no second device.** `scripts/acceptance/pairing-loopback.sh`:

1. Start the TypeScript router with pairing enabled on `127.0.0.1` at an ephemeral port. The
   test build sets the bind address to loopback. Production never does.
2. Issue a code through `POST /pairing/codes`.
3. Run the Swift `LivePairingService` on the macOS host against that port, with a QR payload
   naming the loopback endpoint and the router's fingerprint.
4. Assert `.paired`, a confirmed router-side record, and a phone-side record in the test store.
5. Count connections the way I5 does, with a calibration: a wire tap that must record one
   connection from a separate process. Run a control with no pairing attempt, which must show 0.
6. Mutation: skip the ack. The router record must stay pending and the script must go red.

Scope: this proves the protocol over loopback. It does not exercise the LAN, Bonjour, the iOS
binary, or the firewall prompt. Those need a second device and are listed as open in section 8.

## 8. Build items

Each one merges on its own. Sizes are S, M or L.

| # | Size | Item | Depends on |
|---|---|---|---|
| B1 | S | Router pairing routes on the loopback control API: `POST /pairing/codes`, `DELETE /pairing/codes`, `GET /pairing/state`. TypeScript port of `MacPairing.decide` with burn-after-3. No listener. | — |
| B2 | M | Router pairing listener: TLS identity, off by default, config key `pairing.enabled`, frames, `pair.request` to pending to `pair.ok`, `pair.ack` to confirmed. | B1, D3, D4 |
| B3 | S | Mac sheet asks the router for its code, not the fixture. Revoke on close. `ShellPairingFactory` reports no endpoint (`PairingAvailability.noEndpoint`) while pairing is disabled. | B1 |
| B4 | M | Phone: `LivePairingService`, transport seam, codec, Keychain key, record ordering. Host-tested, not wired. | — |
| B5 | S | Phone wiring: Release uses the live service, fixture Debug only (`MCPRouterIOSApp.swift:54`). Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` to `project.yml`. Add `identityMismatch` with copy, and extend the coverage test. | B4, D5 |
| B6 | M | `scripts/acceptance/pairing-loopback.sh` (section 7). | B2, B4 |
| B7 | M | Bonjour advertise and browse, and a reachability probe that rediscovers a moved Mac. | B2, D4 |
| B8 | L | Typed path via SPAKE2 (RFC 9382) bound to the TLS exporter. Until it lands, typed entry refuses with a named outcome. | B2, D2 |
| B9 | M | Windows client on the same wire contract. Out of this plan's scope: recorded so the Windows side is not left to drift. | B2 |

B1 to B3 can run in parallel with B4 and B5. B6 is the first point where the whole path is
exercised, so it is the gate on any claim that pairing works.

## 9. Decisions

- **D1, owner: is the Swift router retired?** `README.md:65` says the launchd agents run it.
  If they do, B6 cannot pass against the process a phone reaches. Blocks any end-to-end claim.
- **D2, owner: typed entry.** Lean: ship the scan path first, and refuse typed entry until
  SPAKE2 (B8) is vetted. The cost is that the typed path is absent for a while, and the security
  cost of shipping it unauthenticated is an attacker collecting the typed code.
- **D3, owner: router storage.** Lean: 0600 files under `ROUTER_HOME`, as `control.token` already
  does. The cost is that the brief's Keychain-on-both-sides is not met on the router.
- **D4, owner: Node dependencies.** Node has no built-in certificate generation and no mDNS
  responder. Lean: pinned npm packages, since the Windows router path needs the same ones. The
  alternative is shelling out to `openssl` and `dns-sd`, which is one fewer dependency and one
  more platform-specific path.
- **D5, owner and design review: copy.** The two permission strings, the firewall line, and the
  `identityMismatch` outcome all need wording approved under DESIGN.md §6.

## 10. Out of scope

- Remote pairing through any relay. The feature brief's assumption is local mutual
  authorisation only.
- Delivering queued items. `InboxService` has no live implementation either
  (`InboxService.swift`, header). The inbox is a separate item. This plan only covers pairing.
- REQ-016's status. It moves from vacuous only when B6 passes against the router and the
  inventory row is updated by the register, not by this plan.
