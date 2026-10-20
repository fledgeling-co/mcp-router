# Plan: typed-code pairing via SPAKE2

Status: plan only, no code. Owner decision: build it now (B8 in `plan-pairing-handshake.md` §8).
Sources: `planning/plans/plan-pairing-handshake.md` §2.3 (typed path), §2.4 (wire contract), §8 (B8), §11 (D2); `planning/pairing/wire-vectors.json`; `src/pairing.ts`; `src/pairing-listener.ts`.

## Outcome

Build typed entry as SPAKE2 from RFC 9382, using the **edwards25519** row of its Table 1 (SHA-256, HKDF, HMAC) on both sides. Each side's TLS 1.3 exporter goes into the key-confirmation keys, so a relayed session fails confirmation. The router uses `@noble/curves` and `@noble/hashes`, both exact-pinned at 2.4.0. The phone uses CryptoKit for SHA-256, HMAC and HKDF, and libsodium 1.0.22 through `swift-sodium` 0.11.0's `Clibsodium` product for the group operations. Neither side writes curve arithmetic.

Two consequences the owner needs to see. First, no vetted Swift library exposes P-256 point arithmetic, so the phone cannot run the P-256 suite that RFC 9382's published vectors use. Second, the edwards25519 suite has no published vectors in the RFC, so the test gate is split in two (§4). The open risk is that I could not locate a third-party audit report for libsodium (§1, D6).

## 1. Library choice

| Side | Candidate | What I found | Verdict |
|---|---|---|---|
| Node | `@noble/curves` 2.4.0 | MIT, published 2026-08-27, one runtime dependency (`@noble/hashes`). The repo's `audit/` holds a Trail of Bits 2023-01 report (curves) and a Cure53 2024-09 report (ed25519 in scope). The README also claims a Trail of Bits audit at 2.3.0 (Aug 2026), and that report is not in `audit/`. | **Use.** Pin exact. Read the 2.3.0 claim against its report before relying on it. |
| Node | `@noble/hashes` 2.4.0 | MIT, no dependencies, same audit family. | **Use.** |
| Node | `spake2` 1.0.2 (blocksq) | Last modified 2022-05-18. Depends on `elliptic` and `bn.js`. Claims SPAKE2 and SPAKE2+; I could not verify RFC 9382 conformance. | Reject: stale, unverified against the RFC. |
| Node | `cpace-ts` 0.1.6 | MIT, one maintainer, built on noble. No audit found. CPace is not an RFC. | Reject for now. |
| Node | `@cipherman/pake-js` 0.1.1 | MIT, first published 2026-04, one maintainer, no audit found. | Reject: too new. |
| Node | `@cloudflare/opaque-ts` 0.7.5 | BSD-3-Clause, Cloudflare-maintained. OPAQUE is augmented: the server holds per-user registration state. The typed code is a one-time shared secret, not a registered password. | Reject: wrong protocol shape. |
| Swift | CryptoKit (SHA-256, HMAC, HKDF) | Apple. No point arithmetic. | **Use** for hashes and MAC only. |
| Swift | swift-crypto 5.0.1 | Apache-2.0, pushed 2026-10-16. Its P-256 point operations (`EllipticCurvePoint`, and `OpenSSLCurvePoint` behind `ECToolbox`) are `package`-scoped or lack `public`. | Reject for point arithmetic: no public surface. |
| Swift | `swift-sodium` 0.11.0 with libsodium 1.0.22 | ISC for both, pushed 2026-05-04. The bundled headers declare `crypto_core_ed25519_add`, `crypto_core_ed25519_sub`, `crypto_scalarmult_ed25519_noclamp`, `crypto_core_ed25519_is_valid_point` and the scalar functions. I found no third-party audit report for libsodium. | **Use** for edwards25519 group operations. Owner decision D6. |
| Swift | P-256 point arithmetic from a binary OpenSSL or BoringSSL package | I found no maintained Swift package that exposes it publicly. | Not chosen. Fallback only (§8). |
| Either | Hand-written curve arithmetic | — | Rejected: the item rules it out. |

Reference only, not dependencies. MIT krb5's SPAKE plugin (`src/plugins/preauth/spake/groups.c`, the `SEED_M` and `SEED_N` lines) derives the edwards25519 M and N from the RFC seed strings. Its transcript is Kerberos-specific, so it cross-checks the group constants and nothing on the wire. `warner/python-spake2` is a second reference; its licence is reported as "Other".

CPace is the smallest safe alternative. `jedisct1/cpace` (C, BSD-2) was last pushed 2020-12-31. `1Password/cpace` (Rust, Apache-2.0) was pushed 2026-06-04. CPace is still a CFRG draft and does not appear in the RFC index. It is not chosen because the owner's spec names RFC 9382, which is the source of the published vectors this plan relies on. If the libsodium route fails §4's gates, the fallback is CPace over ristretto255, using noble's ristretto255 and libsodium's ristretto255 operations: the same two libraries. The draft's test vectors are not checked.

### What was checked

Commands ran in a scratch directory outside the repository. The scripts are not committed; build item S1 commits the vectors.

1. `node -e "require('node:tls').TLSSocket.prototype.exportKeyingMaterial"` on Node 22.23.1: `function`. The exporter exists on the Node side.
2. `node p256-rfc9382-check.mjs`. The script parses the four RFC 9382 Appendix B P-256 vectors verbatim and runs them through `@noble/curves` `p256` and `@noble/hashes`. It checks pA, pB, K from both sides, TT, HASH(TT), Ke, Ka, KcA, KcB, and both confirmation MACs. Last lines: `PASS [/] B conf` then `ALL CHECKS PASS (4 vectors)`, 48 checks in all. The transcript and key schedule are correct on the Node side.
3. `@noble/curves` `ed25519.Point.fromHex` decodes the RFC's edwards25519 M and N. Both are `isTorsionFree()`, M differs from N, and M round-trips to the RFC hex.
4. The libsodium headers bundled in `swift-sodium` 0.11.0 declare the ed25519 functions in §1, and `SODIUM_VERSION_STRING` is `1.0.22`.
5. swift-crypto's `ECToolbox` declares its `Group` and `GroupElement` protocols without `public`.

Not checked. The developer.apple.com page for `sec_protocol_metadata_create_secret` returned 404, so the Network.framework exporter call is unverified. The only evidence is community forum threads, which disagree about TLS 1.2. E1 settles it. I did not verify that krb5's seed derivation reproduces the RFC constants; §6 asks the reviewer to.

## 2. Protocol

### 2.1 Group, constants and identities

- **Group.** edwards25519, base point P, prime order L, cofactor h = 8. Points are 32-byte compressed RFC 8032 encodings, as RFC 9382 §6 requires for Ed25519.
- **M and N.** The fixed Table 1 points: M = `d048032c6ea0b6d697ddc2e86bda85a33adac920f1bf18e1b0c6d166a5cecdaf`, N = `d3bfb518f44f3430f29d0c92af503865a1ed3281dc69b35dd868ba85f886c4ab`. The per-user variant in RFC 9382 §5 is not used. It needs RFC 9380 hash-to-curve. I have not confirmed that libsodium's `crypto_core_ed25519_from_hash` matches RFC 9380; E1 checks that. Fixed points carry the risk §5 names: one solved discrete-log relation between M and N would break authentication for every exchange. §6 asks the reviewer to weigh it.
- **w.** The typed string is normalised to canonical form first: uppercase, Crockford substitutions, hyphens and spaces removed. The result is eight characters. Then w is a 64-byte scrypt output (RFC 7914) over the canonical code with a fixed salt, reduced mod L. The phone uses libsodium's `crypto_pwhash_scryptsalsa208sha256_ll`; the router uses `@noble/hashes`' scrypt. RFC 9382 §3.2 says the hash SHOULD be memory-hard, so the choice is not silent. Scrypt's work is a second layer, because the 40-bit code is protected by the attempt limit (§2.5). Parameters are chosen by measurement on the phone in P1, not here.
- **Encoding in TT.** w is big-endian, padded to 32 bytes (RFC 9382 §3.3). Lengths are 8-byte little-endian.
- **Identities.** A is the phone's SPKI DER key, the 91 bytes that `phoneKey` carries. B is the ASCII string `mcp-router`, fixed in B8. Both are in TT. RFC 9382 §3.3 allows an empty identity only when identities are implicit, and here they are not. Putting `phoneKey` in TT means a substituted key breaks `pake.confirm`.
- **AAD.** `"pair.typed.v1" || E || phoneName`, where E is the TLS exporter output (§2.2) and `phoneName` is the UTF-8 name. Both sides build it from the same bytes.

### 2.2 TLS exporter binding

After the TLS 1.3 handshake, each side computes E = the exporter with label `EXPORTER-mcp-router-pair-typed-v1`, no context, 32 bytes (RFC 8446 §7.5). On Node this is `socket.exportKeyingMaterial(32, label)`. On the phone it is the Network.framework equivalent, which E1 must confirm. Both sides set the minimum TLS version to 1.3, so the exporter is the RFC 8446 one and not a TLS 1.2 variant.

The binding matters because of the relay. A relay that terminates TLS on both legs and forwards each frame unchanged gives both ends the same pA, pB, K, TT and Ka. Without E in the confirmation keys, the relay would pass. With E, the phone's leg exporter and the router's leg exporter differ, so KcA and KcB differ and confirmation fails. On the typed path the phone does not pin a certificate, since the code carries no `fp` (`plan-pairing-handshake.md` §2.3). So E is the only binding there is.

### 2.3 Key schedule

Unchanged from RFC 9382 §3.3 and §4, with AAD as §2.1 defines it:

- TT = len(A) ‖ A ‖ len(B) ‖ B ‖ len(pA) ‖ pA ‖ len(pB) ‖ pB ‖ len(K) ‖ K ‖ len(w) ‖ w
- Ke ‖ Ka = SHA-256(TT). Ke is not used in v1. The typed path's only output is a confirmed exchange.
- KcA ‖ KcB = HKDF-SHA256(salt empty, IKM Ka, info `"ConfirmationKeys" ‖ AAD`, 32 bytes)
- cA = HMAC-SHA256(KcA, TT), cB = HMAC-SHA256(KcB, TT)

The published vectors use nil AAD, so they do not exercise the AAD path. Generated vectors cover it (§3).

### 2.4 Message flow

Runs after TLS, on the typed path only:

1. **Phone → router `pake.start`**: pA = x·P + w·M, with x uniform in [1, L) and fresh for each exchange.
2. **Router.** Checks that the code is live and unspent (§2.5). Decodes pA and rejects an identity, a small-order point, or a point outside the prime-order subgroup. A rejected pA spends no attempt. Otherwise it picks y, computes pB = y·P + w·N and K = h·y·(pA − w·M), computes cB, and replies `pake.reply`.
3. **Phone.** Checks that pB is a valid group element. Computes K = h·x·(pB − w·N), then KcB, and compares cB in constant time. On a mismatch it closes without sending anything and reports `notRecognised`. On a match it sends `pake.confirm` with cA.
4. **Router.** Verifies cA. On a mismatch it sends `pair.refused` with `notRecognised` and closes. On a match it consumes the code, issues the phoneId, and sends `pair.ok`, as §2.4 of the handshake plan already defines.
5. **Phone.** Writes its pending record and sends `pair.ack`, unchanged from `plan-pairing-handshake.md` §2.2 steps 4 and 5.

The order matters. cB goes out first, so the phone sends nothing that proves anything about the code until it has checked the router's MAC. Only the router checks cA.

### 2.5 Burn-after-3 and the code's entropy

- **Entropy.** Eight Crockford characters carry 40 bits. Each exchange gives an attacker one guess: the guess is embedded once in pA, and the router's response depends on it only through K. A passive eavesdropper has no offline test, because K needs x or y, and neither crosses the wire (RFC 9382 §3.3, §7). Online guessing is the whole attack surface.
- **Attempt accounting changes.** The router cannot see a wrong code, because it never receives the code. So the typed path counts exchanges started with a valid pA, not wrong codes. The third started exchange is the last allowed. A success consumes the code at once, and a concurrent exchange that completes afterwards gets `alreadyUsed`. The bound is three guesses per code regardless of how many connections are open. Today `submit` counts wrong codes (`src/pairing.ts:138` at `ba0674b8` reads `submit(code: string, version: number)`, and the count runs to line 150), against `PAIRING_MAX_WRONG_ATTEMPTS` (`src/pairing.ts:21` at `ba0674b8` reads `export const PAIRING_MAX_WRONG_ATTEMPTS = 3;`). The scan path keeps that count. The typed path gets a separate begin and complete pair.
- **Probability.** Three guesses against 2^40 gives 3 / 2^40, about 2.7 × 10⁻¹² per code. The 5-minute window (`src/pairing.ts:18` at `ba0674b8` reads `export const PAIRING_LIFETIME_MS = 300_000;`) still applies. The router rechecks liveness at step 4, since a code can expire between steps 2 and 4.
- **Cost.** A LAN attacker that reaches the listener can spend a visible code with three valid `pake.start` frames. The phone's remedy is the one it has today: ask the Mac for a new code. That is a denial, not a compromise. Whether to accept it is an owner decision (D7).

### 2.6 Wire additions to §2.4

The version stays at 1. The existing `request.wrongVersion` vector uses v = 2 as the unsupported value, and bumping the version would change it. A pre-B8 router closes the socket on an unknown frame type. The phone should map that to `unreachable`, and P1 sets the mapping.

`pair.request` with `entry: "typed"` is unchanged and still refused with `typedEntryUnavailable`. The typed path is the three `pake.*` frames:

| Frame | Sender | Fields | Rules |
|---|---|---|---|
| `pake.start` | phone | `type`, `v`, `entry` = `"typed"`, `phoneName`, `phoneKey`, `pA` | `phoneName` and `phoneKey` as `pair.request` defines them. `pA` is standard base64 of 32 bytes. Anything else is `badRequest`, and no attempt is spent. |
| `pake.reply` | router | `type`, `v`, `pB`, `cB` | Both standard base64 of 32 bytes. |
| `pake.confirm` | phone | `type`, `v`, `cA` | Standard base64 of 32 bytes. |

`pair.refused` can answer `pake.start` with `notRecognised`, `expired`, `alreadyUsed`, `badRequest`, `frameTooLarge` or `unsupportedVersion`, and can answer `pake.confirm` with `notRecognised` only. The reason list in §2.4 gains no new values. Any frame that does not fit the current state closes the connection, as §2.4 already requires.

## 3. Vectors

- **`planning/pairing/spake2-rfc9382-vectors.json`** (new). The four Appendix B P-256 vectors, verbatim: w, x, y, pA, pB, K, TT, HASH(TT), Ke, Ka, KcA, KcB, both confirmations, and the identities. The transcript and key-schedule code on both sides takes these as input bytes and does not care about the point encoding, so the P-256 points never need to be computed on the phone.
- **`planning/pairing/spake2-edwards25519-vectors.json`** (new). Generated by noble from fixed x, y, code, identities, phoneName and a fixed exporter value. A non-empty AAD case covers §2.1. Cross-checked by libsodium in Swift.
- **`planning/pairing/wire-vectors.json`** (extended). New entries: `pake.start.valid` (router replies `pake.reply`), `pake.start.offCurve`, `pake.start.smallOrder`, `pake.start.wrongEntry` (`badRequest`), `pake.confirm.wrong` (router refuses `notRecognised`), `pake.confirm.right` (router replies `pair.ok`), `pake.reply.badCB` (phone reports `notRecognised`), and `pake.reply.badLength`. Live exchanges take x, y and w as fixed inputs through a test-only seam, with `exporter` fixed in the vector. `request.typed` stays as it is.

## 4. Test plan

Each gate has a mutation that must go red before the gate is trusted.

- **G1, transcript and key schedule, both sides.** Node: the RFC vectors through the shipping module. The spike's 48 checks pass with noble; the build repeats them through the module. Swift: the same four vectors through CryptoKit. Mutation: change one length prefix in TT. Both sides go red.
- **G2, group layer, edwards25519.** Node: M and N equal the RFC constants and are torsion-free. K from A equals K from B. Identity, small-order, off-curve and non-canonical encodings are rejected. Swift: the same generated vectors give the same pA, pB and K from the same x, y and w. Mutation: remove the h multiplication. The vectors go red.
- **G3, exporter binding.** E1 first: a loopback TLS 1.3 connection from NWConnection to Node, asserting that both ends export equal bytes, and a second connection with a different server certificate, asserting that they differ. Then the relay test: a Node relay terminates TLS on both legs and forwards frames unchanged, and the exchange must fail at `pake.confirm`. Mutation: remove E from AAD. The relay test must then pass, which shows the test can see the binding. Restoring E must turn it red again.
- **G4, attempt accounting, TypeScript unit.** Three started exchanges, and a fourth is refused. A success consumes the code. A concurrent second completion gets `alreadyUsed`. A malformed pA spends no attempt. Expiry between steps 2 and 4 refuses.
- **G5, loopback lane (extends B6).** `scripts/acceptance/pairing-loopback.sh` gains a typed mode. The router listens on an ephemeral 127.0.0.1 port. A correct typed run pairs and records both sides. Three wrong codes burn the code, and a fourth is refused. A relay in the middle is refused. The I5 connection count has a control with no attempt, which must show zero. Mutation: skip `pake.confirm`. The router stays pending and the script goes red.
- **G6, regression.** The scan-path tests, the existing wire vectors, and the Release-branch assertion are unchanged. `request.typed` still expects `typedEntryUnavailable`.

Builds run `npx tsc -p tsconfig.json --noEmit`, `npm test`, `swift test -j 4`, `swiftlint lint --strict` and `swiftformat --lint` on touched files, and `make test` once at the end.

Not covered, and listed in `plan-pairing-handshake.md` §7 as needing a second device: the LAN path, Bonjour, the iOS binary and the firewall prompt.

## 5. Build items

Sizes are estimates: S is about half a day, M is one to two days.

| # | Size | Item | Depends on |
|---|---|---|---|
| E1 | S | TLS exporter spike. Node to Node and NWConnection to Node exporter equality on TLS 1.3, plus the Apple function's signature read from the installed SDK header. Also checks whether libsodium's `from_hash` matches RFC 9380. Finding only, no product code. | — |
| S1 | S | TypeScript transcript and key schedule, with G1 on Node. | — |
| S2 | S | Swift transcript and key schedule, with G1 on Swift. | — |
| G1 | M | TypeScript edwards25519 group layer on noble, with the generated vectors and G2 on Node. | S1 |
| G2 | M | Swift group layer on libsodium through `swift-sodium`, with G2 on Swift. Adds the dependency, so D6 is answered first. | S2, E1 |
| R1 | M | Router: `pake.*` frames, the begin and complete accounting that replaces `submit` for the typed path only, the state machine, and G4. | G1, B2 |
| P1 | M | Phone: the typed path in `LivePairingService`, typed-code normalisation, scrypt parameters measured on device. Pending-record ordering stays as it is. | G2, S2, B4 |
| V1 | S | Vector extension, with the Swift and TypeScript decoders checked against it. | R1, P1 |
| A1 | M | Loopback typed lane, relay test, and mutation runs (G3, G5). | R1, P1, E1 |

Total is about nine and a half worker-days in sequence. The critical path is about five days, because E1, S1 and S2 run first and in parallel. That fits the owner's "several days".

## 6. Review needed

An outside reviewer should check these, against the RFC text and not against this plan or the code. The reviewer should be neither the author nor the same model family.

1. M and N against RFC 9382 §6.
2. The TT field order, the 8-byte little-endian lengths, big-endian w padded to 32 bytes, and the identities.
3. The KDF input `"ConfirmationKeys" ‖ AAD`, and that AAD carries each leg's own exporter.
4. The exporter label, the 32-byte length, and the TLS 1.3 minimum.
5. Point validation for pA and pB: identity, small-order, off-curve, and off-subgroup points are rejected, the h multiplication is present, and K is not the identity.
6. x and y are uniform in [1, L), fresh for each exchange, and drawn from a CSPRNG with rejection sampling. The Swift side uses `crypto_core_ed25519_scalar_random`.
7. Constant-time behaviour. The cB and cA comparisons must be constant time. noble documents that its field operations are not constant-time, and the router performs scalar multiplication on the secret x and y. A timing signal needs one exchange, so the reviewer decides whether that is acceptable.
8. Attempt accounting under concurrency (G4).
9. Fixed M and N against the per-user variant (§2.1). This is the trade in §5 of the RFC.
10. The Apple exporter call, read from the installed SDK header, not from documentation.
11. Dependency audit status. noble's Trail of Bits 2023 and Cure53 2024 reports are in its repository. Its 2.3.0 Aug 2026 report is claimed but not in `audit/`. libsodium has no third-party report I could locate.

## 7. Decisions

- **D6, owner. Libsodium on the phone.** The phone takes libsodium 1.0.22 as its group-operation dependency, and I found no third-party audit of it. The options are: accept it with a pinned version and the §6 review; require an audit before B8 merges; or keep typed entry refused on the phone, which is the D2 default. Lean: accept, pinned, with the review. This is a risk call, so it is the owner's.
- **D7, owner. Burn denial.** A LAN attacker can spend a visible code by sending three `pake.start` frames (§2.5). Lean: accept. The attacker gains a denial, not a pairing.
- **D8, reviewer. Fixed or per-user M and N.** Lean: fixed, the Table 1 points. If E1 shows libsodium's `from_hash` matches RFC 9380, switch to the §5 variant and remove the trade in §2.1.

## 8. Fallbacks

If E1 or G2 fails on the phone, there are two options. Use CPace over ristretto255 (§1), after its draft's vectors are checked. Or keep typed entry refused under D2. The scan path loses nothing either way. A P-256 suite would need a binary OpenSSL or BoringSSL package, which is heavier and whose package I have not verified.

## 9. Out of scope

The Windows client (B9), any change to the scan path, and the Swift router (D1) are not part of this plan.
