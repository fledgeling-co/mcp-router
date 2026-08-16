# I5 — the pairing transport, measured

The wave-6 exit gate was *"Phone → Mac inbox round-trip works end to end"*. M6 reported it as **not
met** rather than claiming it, and argued the point from the source. This item settles it by
experiment.

**Finding: the round trip does not happen, because neither side implements it.** An unproven
transport was the suspicion; an unimplemented one is the measurement.

Reproduce with `./scripts/acceptance/i5-pairing-transport.sh` after `make build-mac`.

---

## What was run

Two real processes: the Mac app on macOS (`open -g`, bound by bundle path), and an XCTest suite on
an iPhone 16 Pro simulator. Between them, a python TCP wire tap on `127.0.0.1:<ephemeral>` that logs
every connection made to it.

| # | Measurement | Result |
|---|---|---|
| 1 | Tap records a connection from a separate host process | `CONNECT 1 / DATA 1 HOST-CALIBRATION` |
| 2 | Socket enumerator run against the tap's own pid | `1` |
| 3 | Pairing sheet driven open via the accessibility API | live code, countdown `expires in m:ss` |
| 4 | **Listening TCP sockets held by the Mac app, code on screen** | **0** |
| 5 | Callers of `MacPairing.decide` / `markPaired` outside `PairingSessionModel` | **0** |
| 6 | Tap records a connection from inside the phone process | `CONNECT 2 / DATA 2 PHONE-REACHABILITY` |
| 7 | Phone pairs against a payload naming the live tap | `.paired(PairedMac(name: "I5 Wire Tap", host: "127.0.0.1", port: <tap>, fingerprint: "SHA256:i5-probe"))` |
| 8 | **Connections the pairing call contributed** | **0** |

Rows 1, 2, 3 and 6 are calibrations, and they are the reason rows 4 and 8 mean anything. An absence
is trivial to manufacture by accident — an unreachable tap, a wrong port, a suite that never ran, a
simulator with no route to the host all produce exactly the evidence that "no transport" produces.
Row 6 is the load-bearing one: it is a connection made by the *same process* whose pairing call is
under test, to the *same port*, in the *same run*, and it was counted.

**Row 7 beside row 8 is the finding in one line: the phone stored a paired-Mac record for a Mac it
never contacted, at an address it demonstrably could reach.**

Runs: load 12.18 and 76.94 on the pre-remediation instrument, load 34.21 on the final one, all with
the same result. The low-load run is the authoritative one for row 4.

---

## Mutations — every assertion proved able to go red

A series of agreeing observations bounds an agreement rate; it cannot say what a term measures.

| | Mutation | Result |
|---|---|---|
| A | Aim the app's socket check at the tap's pid | reports `1`, FAILs "the Mac app IS listening on 1 socket(s)" |
| B | Phone process opens one extra connection during the pair call | tap logs 3, FAILs "recorded 3 connections where 2 were expected" |
| C | *(natural, run 1)* env var did not reach the simulator | 2 of 3 probes skipped, BLOCKED on the assertion count |
| D | `FixturePairingService(.notRecognised)` | FAILs "it did not (notRecognised)" |
| E | Composition guard searches for `LivePairingService()` | FAILs |
| F | `listening_sockets` against a dead pid | `unreadable`, not `0` |
| G | Launch under `MCPROUTER_PAIRING=none` | BLOCKED at the countdown precondition, exit 2 |
| H | Plant a `MacPairing.decide` call in another Sources file | `unexpected` goes 0 → 1, FAILs |
| I | Widen `supportedVersions` to `[1, 2, 7]` | both envelopes' version-mismatch tests go red |

Mutation B is the decisive one: **if the pairing call had connected, this experiment would have said
so.** Mutation C is not synthetic — it happened, and the harness reported BLOCKED rather than PASS
because it asserts on how many assertions ran rather than on an exit code.

---

## D-m6-b — envelope versioning already exists

The register says *"No version field, so a phone and a Mac on different builds cannot detect the
mismatch"*. That is **false against this tree**, and mutation I is the measurement rather than a
reading:

- `PairingPayload.supportedVersions: Set<Int> = [1]`, unknown → `.unsupportedVersion(found:)`
- `InboxEnvelope.supportedVersions: Set<Int> = [1]`, unknown → `.unsupportedVersion(found:)`
- `MacPairing.decide` → `.unsupportedVersion(found:)` → `PairingOutcome.versionMismatch`

Widening either set makes the corresponding test fail with *"an error was expected but none was
thrown"*, so the gate is enforced rather than decorative. **D-m6-b is closed as already-done, not
carried into the transport item.**

---

## Out-of-family review

`grok-4.6`, given the method and asked to attack the conclusion, upheld it and narrowed its scope. It
found four real holes, all closed here:

1. `listening_sockets` swallowed lsof's exit status, so "lsof failed" and "listens on nothing" were
   the same answer — and the second is the headline. Calibration row 2 proved the counter reads `1`
   for the *tap's* pid, which says nothing about whether it succeeded against the *app's*.
2. The pairing sheet was never opened. `PairingSessionModel.open()` is the only place this design
   would construct an endpoint, so a lazily-bound listener is exactly what a measurement taken three
   seconds after launch would miss.
3. The scenario environment was never checked as having arrived — the same class of failure as
   mutation C.
4. The closing text claimed more than the run measured.

It also supplied row 5, which outranks the socket count: the Mac has no consumer for an arriving
code at all.

## Scope — what this does NOT establish

- The phone half drives the production pairing **seam** (`FixturePairingService`, which is what the
  shipping `@main` composes, guarded by a test here), not the shipping UI end to end.
- Only TCP to this tap's port was watched. UDP, unix domain sockets, mDNS, XPC and IPv6 `::1` are
  ruled out by source inspection, not by this instrument.
- The iOS binary measured is Debug. No Release iOS build was run.
- The wave-6 gate also covered inbox **delivery**, which this experiment does not exercise.

## Left open for the owner, not acted on

The Mac guards its side hard: `ShellPairingFactory` ignores the environment in Release specifically
so a shipped build cannot draw a QR for an endpoint nothing answers on. **The phone has no
equivalent guard.** `MCPRouterIOSApp` passes `pairing: FixturePairingService()` with no
configuration branch, so a Release iPhone build pairs against a fixture that reports success without
I/O and writes the result to the Keychain.

Recorded as a finding. Changing it is not this item's to do, and it touches no privilege.
