# E1: TLS exporter and libsodium's edwards25519 maps

Plan: `planning/plans/plan-pairing-typed-spake2.md`, §5 (E1), §1, §6 item 10 and D8 in §7. This is a finding, not product code. Reproduce it from this directory with `swift build -j 4 && node run-e1.mjs`.

## Answers

1. **The exporter binding holds on TLS 1.3.** A Network.framework client and a Node server derive the same 32 bytes for the label `EXPORTER-mcp-router-pair-typed-v1`, on both of two test certificates. TLS 1.3 was negotiated on every leg. Both sides require TLS 1.3, so the TLS 1.2 disagreement in plan §1 does not arise.
2. **The Apple call has no context argument.** Read from the installed SDK header, not from documentation (plan §6 item 10):

   ```
   sec_protocol_metadata_create_secret(sec_protocol_metadata_t metadata, size_t label_len,
                                       const char *label, size_t exporter_length);
   ```

   It returns `dispatch_data_t`. The macOS 27.0 and iPhoneOS 27.1 headers declare it identically. The exporter itself was measured on macOS only.
3. **libsodium's `from_hash` does not match RFC 9380.** On the five RFC 9380 Appendix J.5.1 vectors, libsodium 1.0.22's `from_hash(u0 || u1)` equals the RFC's P on 0 of 5, and its y-coordinate matches on 0 of 5. D8's condition is "if E1 shows libsodium's `from_hash` matches RFC 9380". That condition is not met, so the default stands: fixed M and N from RFC 9382 Table 1.
4. **The map functions are deprecated.** The libsodium 1.0.22 header says of `crypto_core_ed25519_from_uniform`: "undocumented and has been marked as deprecated since 2019. It will be removed. Bindings should not refer to it." `crypto_core_ed25519_from_hash` carries `__attribute__((deprecated))` in both the macOS and iOS slices. The §5 per-user variant would rest on both, so it is not a route. `crypto_core_ed25519_add`, `crypto_core_ed25519_is_valid_point` and the scalar functions are not marked deprecated. G2 uses those.

## Evidence

Final run, exit 0:

```
PASS  SDK declares sec_protocol_metadata_create_secret with no context argument  (MacOSX27.0.sdk)
PASS  cert A: Node client <-> Node server negotiated TLS 1.3 on both ends  (client TLSv1.3, server TLSv1.3)
PASS  cert A: Node client <-> Node server exporter is 32 bytes on both ends  (32/32)
PASS  cert A: Node client <-> Node server both ends export equal bytes
PASS  cert A: Network.framework client <-> Node server negotiated TLS 1.3 on both ends  (client TLSv1.3, server TLSv1.3)
PASS  cert A: Network.framework client <-> Node server exporter is 32 bytes on both ends  (32/32)
PASS  cert A: Network.framework client <-> Node server both ends export equal bytes
PASS  cert B: Node client <-> Node server negotiated TLS 1.3 on both ends  (client TLSv1.3, server TLSv1.3)
PASS  cert B: Node client <-> Node server exporter is 32 bytes on both ends  (32/32)
PASS  cert B: Node client <-> Node server both ends export equal bytes
PASS  cert B: Network.framework client <-> Node server negotiated TLS 1.3 on both ends  (client TLSv1.3, server TLSv1.3)
PASS  cert B: Network.framework client <-> Node server exporter is 32 bytes on both ends  (32/32)
PASS  cert B: Network.framework client <-> Node server both ends export equal bytes
PASS  Network.framework client refuses a server whose certificate is not its anchor
PASS  two server certificates give different exporters (the exporter is not constant)
PASS  libsodium is the pinned 1.0.22  (1.0.22)
PASS  control: RFC P encodings are valid points and round-trip through add(P, identity)
FIND  from_uniform(u0) equals RFC 9380 Q0 on 0/5; y-coordinate alone on 0/5
FIND  from_uniform(u1) equals RFC 9380 Q1 on 0/5; y-coordinate alone on 0/5
FIND  from_hash(u0 || u1) equals RFC 9380 P on 0/5; y-coordinate alone on 0/5
FIND  from_hash equals 8 * (from_uniform(u0) + from_uniform(u1)) on 0/5; the uncleared sum on 0/5
FIND  libsodium's own outputs are valid points: from_uniform(u0) 5/5, from_uniform(u1) 5/5, from_hash 5/5
FIND  RFC Q0 and Q1 as libsodium sees them: valid 0/5 and 1/5; round-trip 5/5 and 5/5
PASS  negative controls do not match (the comparison can fail)  (from_uniform(u0) = Q1 on 0/5, from_hash = Q0 on 0/5)
E1: 18/18 gates hold
```

Mutation: `E1_MUTANT=nw-label node run-e1.mjs` gives the Network.framework side a different label. It exits 1, both `Network.framework client <-> Node server both ends export equal bytes` gates FAIL, and the run reports `E1: 16/18 gates hold`.

The libsodium comparison has two controls. The RFC points must decode and round-trip in libsodium, which they do, so the encoder is not the cause of the mismatch. The negative controls, which pair each output with the wrong RFC point, must not match, and they do not. A big-endian `u0` gives 0 of 5 as well, so byte order is not the cause. That probe was run outside the repository.

## Corrections made during the spike

- The first run failed on the Network.framework leg. Trust evaluation refused the test server with TLS alert 46 and `-9808 bad certificate format`. The cause was the certificate. `openssl req -x509` makes a `CA:TRUE` leaf with no `serverAuth`, and an RSA variant failed the same way. The test certificates now carry `CA:FALSE`, `digitalSignature` and `serverAuth`, as the product identity does (`src/pairing-identity.ts:55` at `2a1da246` reads `new x509.BasicConstraintsExtension(false, undefined, true),`).
- An early version compared exporters from different connections. Those gates failed, correctly, because a TLS exporter belongs to one session. They were removed. Each leg now compares its two ends within one connection.
- An early verify block accepted every certificate. It now evaluates trust against one anchor, and the refusal gate shows a client refuses a server whose certificate is not that anchor.
- The libsodium vectors in `rfc9380-j51.json` were extracted from the RFC text by a parser kept outside the repository. They can be re-derived from RFC 9380 Appendix J.5.1.

## What this means for the plan

- **Typed-path verify block (P1, A1).** Default system trust does not accept the Mac's self-signed certificate. The typed path does not pin a certificate (plan §2.2), so the phone's verify block has to accept the peer without a trust decision, and the exporter binding carries the authentication. Plan §2.2 argues this but does not state the verify block. The scan path pins the fingerprint in its verify block (`app/Sources/MCPRouterKit/Pairing/NetworkPairingTransport.swift:76` at `2a1da246` reads `sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in`). The owner or reviewer should see this before P1 is built.
- **D8.** Fixed M and N stand. The per-user variant needs a `from_hash` that matches RFC 9380, and this libsodium does not provide one.

## Open

- libsodium's C source is not in the tree. swift-sodium vendors headers and the xcframework only, so the spike reports observed output, not the cause of the mismatch.
- Not run: the iOS `NWConnection` path. No device or simulator was booted, per the lane rules, so the exporter is measured on macOS only. The iOS SDK header matches.
- Not run: TLS 1.2. Both sides require TLS 1.3, so it is outside this configuration.
- Not run: RFC 9380's `expand_message_xmd` and `hash_to_field` steps. The mismatch at the map step already answers D8, so those steps were not needed.
