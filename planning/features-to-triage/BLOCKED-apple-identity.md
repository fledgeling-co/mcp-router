# BLOCKED — the Apple developer identity. Not scheduled, not acted on.

**Source:** `mcp-router-status-answers.json`, question `apple-identity`.

**State: `as-found`.** The page pre-selected "Give me the team ID and certificate" as a
recommendation and **it was never confirmed**. Per the export's own contract, an as-found answer is a
proposal nobody clicked, not a decision. It is also flagged `blocksAutomation: true`. So this is
recorded and left alone rather than worked.

The note attached to it, verbatim:

> Use 1password rhodes-family account in Dossier vault for App Store connect api key.
> mcp-relay.fledgeling.app is the bundle id.

Two reasons no work starts from that note:

1. **It points at a credential store.** Reaching into a 1Password vault for an App Store Connect API
   key is exactly the kind of action `blocksAutomation` exists to stop, and nothing here should fetch
   it without the owner saying so directly.
2. **The bundle id is ambiguous and it matters.** `mcp-relay.fledgeling.app` is domain-shaped, not
   reverse-DNS. A bundle identifier for that domain would normally be `app.fledgeling.mcp-relay`. The
   project currently assumes `app.fledgeling.mcprouter`, so this is also a **rename**, and a bundle id
   is noisy to change once an App Store Connect record exists. Guessing which of the three was meant
   would bake the guess into the signing identity, the entitlements and the App Store record.

**What unblocks it:** the team ID and signing certificate, plus one line saying which exact bundle
identifier string to use for the Mac app and which for the phone.

**What it is holding:** signing and notarisation entirely, the phone app leaving the simulator, and
therefore `D-e` and the pairing round trip that `I4` depends on.
