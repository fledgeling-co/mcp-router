I'll attack the claim from the repo and the experiment's actual surfaces, not from the write-up. First I'm mapping pairing, inbox, and transport code plus anything a TCP tap on localhost would miss.The grep already says the shipping phone is wired to a fixture. Next I’ll read the probe, tap, pairing types, and Mac launch path for anything that could still move bytes.The phone probe is an XCTest calling the fixture, not the shipping app. I'm checking whether the Mac side still binds lazily, or whether the real app process does I/O the suite never reaches.The Mac pairing sheet is never opened. Next I’m checking whether the phone already talks to the Mac on some other channel, and whether the app process has children or non-TCP sockets the tap would miss.The conclusion is true of this tree. This method does not prove it. It proves a narrower thing, then writes the broader sentence.

What actually survives: **in this repository there is no implemented pairing transport, so a phone-to-Mac pairing exchange cannot occur.** That is a source fact. The tap is consistent with it. The tap is not what makes it true.

---

**1. The phone half measured the mock, not the product.**

`testPairingAttemptAgainstALiveEndpoint` constructs `FixturePairingService()` and calls `pair(using:)`. It does not launch the iOS UI, does not go through `PairingFlowModel.submit`, does not scan, does not type, and does not touch the `PhoneShell` instance `@main` built.

`FixturePairingService.pair` is a local switch. It copies `host`/`port`/`fp` onto a `PairedMac` and returns `.paired`. There is no socket in that function. Pointing a live tap at it and counting zero extra connects is what you get from reading forty lines of Swift.

The composition grep (`pairing: FixturePairingService()` in `MCPRouterIOSApp.swift`, no `#if DEBUG`) is doing almost all of the product-level work. The tap is confirmatory theater around a type whose contract is “do not talk to anyone.”

That is the (c) answer: **yes, driving the fixture type directly substantially weakens the claim as a claim about the shipping product’s runtime.** It is a strong claim about this type. It becomes a product claim only by joining it to a source grep.

**2. They also skipped the only Mac action that would ever bind, if anything did.**

A pairing listener in this design would be created in `PairingSessionModel.open()`, not at process start. `open()` is reached from File → Pair iPhone…, the inbox header button, or the empty-state button. The I5 script never clicks any of them. `phase` therefore stays `.noEndpoint` for the whole measurement. No QR is encoded. No code is on screen.

The script then says the Mac was “displaying a pairing code” / “advertising a pairing endpoint.” That is false of the process they measured. They launched a Debug app with `MCPROUTER_PAIRING=paired` and counted sockets on the idle window.

So “0 listening sockets after a 3s settle” is a measurement of **startup, not pairing.** A lazy bind on sheet-open is exactly the path this method would miss. In *this* tree `open()` still does not bind — it calls `MacPairing.issue` / `encode` against `FixtureInboxService.fixtureEndpoint` (`192.168.1.24:7333`, invented). The hole is in the method, not in a hidden listener.

**3. “Richest fixture” is the worst place to look for a real socket.**

`MCPROUTER_PAIRING=paired` selects `FixtureInboxService`, whose job is to *pretend* there is an endpoint without binding one. Release is `NoTransportInboxService` and ignores the environment. There is no live `InboxService`. Measuring the faker and concluding “if anything were going to listen, it would listen here” is backwards: this is the path written specifically so the UI can lie without a port.

**4. Channel by channel, what the method can miss.**

| Channel | Would this method see it? | Is it happening here? |
|---|---|---|
| TCP to the payload’s `host:port` | Yes. Calibrations A/B/phone-reachability, mutation B. | No. Fixture never connects. |
| Connection open-and-close faster than the log | No miss. `CONNECT` is written at `accept()`, line-buffered. Mutation B. | — |
| TCP to somewhere else (`192.168.1.24:7333`, control `127.0.0.1:8879`, a hardcoded port) | **Miss.** Tap only sees its own port. | Pairing/Inbox contain no `socket`/`NWConnection`/`URLSession`. Release phone *does* call `LiveControlAPIClient` at `http://127.0.0.1:8879` — the **phone’s** loopback, a different seam, documented Offline. Not pairing, and this experiment never launched that path (Debug `PhoneClientFactory` defaults to a fixture; the probe never constructed a `PhoneShell`). |
| Outbound from the Mac, no listen | **Miss** on the `lsof -sTCP:LISTEN` check. The TCP dump might show `ESTABLISHED` if they looked. | Debug + `MCPROUTER_SCENARIO=populated` is also a fixture control client. No pairing outbound exists. |
| IPv6 `::1` | **Miss.** Tap binds `127.0.0.1` only. A client that Happy-Eyeballs to `localhost` → `::1` never arrives. | Nothing connects. |
| UDP | **Miss.** Tap is `SOCK_STREAM`. `lsof -iTCP` will not see it. | None in Pairing/Inbox. |
| Bonjour / mDNS | **Miss.** Advertisement is UDP 5353 via `mDNSResponder`, usually XPC from the app, not a TCP LISTEN on the app pid. | No `NetService` / `NWBrowser` / `NWListener` in either app. `RouterCore` is not linked by either app target. |
| Unix domain sockets | **Miss.** `lsof -iTCP` ignores `AF_UNIX`. | None. |
| XPC / a helper / the router daemon | **Miss.** `lsof -p $app_pid` is that pid only. `MCPRouterCLI` and `node dist/index.js` can listen; neither was this experiment’s subject, and `src/` has no pairing/inbox routes. | App does not spawn a pairing helper. `decide()` is never called from production code (only tests). Incoming bytes would have no consumer even if they arrived. |
| Shared files / App Group | **Miss.** | No app group. |
| Pasteboard / Universal Clipboard | **Miss.** | No pasteboard pairing. The designed QR path is visual, one-way, and they never opened the sheet anyway. |
| iCloud / CloudKit | **Miss.** | iOS entitlements file is empty. Pairing record is Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — it is specified *not* to leave the device, including via backup. |
| Lazy listener after UI | **Miss.** See (2). | `open()` still does not bind. |
| `reachability(of:)` after a stored pairing | **Miss.** They never called it. Settings `.task` would, if they had driven the app and a record existed. | Fixture `reachability` is also a local switch. |

None of those missed channels is implemented for pairing in this tree. Several of them are channels **this method cannot rule out**. The write-up treats silence on one TCP port as “the round trip does not happen at all.”

**5. The 3s settle is not safe as stated, and load 76.9 makes the instrument worse, not better.**

Same answer at load 12.2 and 76.9 is unsurprising if the app never binds. It is not evidence the wait was long enough for a bind that starts after first paint.

Worse: `listening_sockets` is

```bash
lsof -nP -p "$1" -a -iTCP -sTCP:LISTEN 2>/dev/null | grep -c LISTEN || true
```

A failed `lsof` (timeout, permission, process in an awkward state under load 76) is discarded, `grep -c` on empty input prints `0`, `|| true` swallows the miss. Calibration 2 proves the enumerator can read `1` **for the tap, before the app is launched.** Mutation A proves the same, still against the tap’s pid. Neither proves `lsof` succeeded against the **app** pid. `lsof -p $PID -a -iTCP` with no sockets and `lsof` failing are the same empty dump.

They also never checked that `open --env MCPROUTER_PAIRING=paired` actually arrived. This fleet already burned one I5 run on “env did not reach the simulator.” The Mac side uses a different handoff and has no equivalent calibration (no AX assertion that a code or a fixture inbox row is on screen).

**6. Other overstatements.**

- **Release phones get the fixture** is a source claim, and it is true (`MCPRouterIOSApp` has no configuration branch). They ran a Debug `xcodebuild`. They did not measure a Release iOS binary.
- The composition guard is evadable: it requires the literal `pairing: FixturePairingService()` and forbids the literal `#if DEBUG`. `#if !DEBUG`, `#if targetEnvironment(simulator)`, or a factory sitting next to the fixture line would still pass. There is still only one `PairingService` conformance, so this is a future-proofing hole, not a current one.
- They never called `reachability`. The Settings surface does, on every load, against whatever Keychain holds. Irrelevant today; not the “complete pairing attempt” the comment claims.
- Wave 6’s gate was **inbox** delivery, not just pairing. `FixtureInboxService.snapshot()` reads bundled JSON. That second half of “phone → Mac inbox round-trip” was not on this tap at all.
- `PairingSessionModel.decide` / `markPaired` have **no production callers**. The Mac cannot accept a pairing request because nothing in the shipped app invokes the function that would. That is a stronger fact than “0 LISTEN sockets,” and the experiment does not use it.

**7. What the calibrations and mutations actually buy.**

They buy a lot, for one question: *if this process had opened a TCP connection to this port during `FixturePairingService.pair`, would we have seen it?* Yes. Host calibration, phone reachability from the same process, mutation B, assertion-count BLOCKED on the skipped run — that family is closed.

They do not buy: user-driven shipping UI, Mac pairing sheet, any non-TCP channel, any other destination, a successful `lsof` of the app, or the env actually selecting the fixture they named.

---

The conclusion survives in this scope and no wider:

**This product has no pairing transport. The phone’s only `PairingService` is a local fixture that reports `.paired` without I/O, and that is what Release iOS composes. The Mac’s inbox/pairing implementations do not bind a port; Release cannot be talked into the fake endpoint; nothing in production consumes an incoming code. A phone-to-Mac pairing round trip therefore does not happen, because neither side implemented it.**

It does not survive as: “we watched the shipping pairing flow against a live endpoint and the wire was silent,” nor as “every channel a pairing exchange could use was empty.” Those were not measured.
