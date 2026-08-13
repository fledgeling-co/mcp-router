# I1 — iPhone app: shell and pairing

**Depends on:** F2, F3, M6.

The companion's foundation. A tab bar (Discover / Triage / Queue / Library / Settings)
and the pairing flow that connects it to a Mac.

- Pairing by QR scan with a typed-code fallback, mirroring M6's Mac side and its expiry
  countdown.
- Connection state is always legible: paired to which Mac, reachable or not. A phone
  that silently fails to send is worse than one that says it cannot.
- **The phone queues; it never installs.** This is a deliberate narrowing of "remote
  install" and every surface must reflect it rather than implying otherwise.
- iOS-native grammar throughout — this is not the Mac app's chrome on a phone.

Deep link: `design/mocks/prototype.html?only=phone&pairing=1`.
