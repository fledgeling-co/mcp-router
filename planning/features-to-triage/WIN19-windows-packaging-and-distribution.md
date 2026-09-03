---
status: to-triage
found-by: intake divergent pass, from the macOS signing and notarisation work having no Windows counterpart · 2026-08-30
reckon-sources: [SURF-047, REQ-037]
target-note: SURF-047 `The MSIX package - pack, validate, install, uninstall` and REQ-037, which states the MSIX identity and the uninstall contract this brief asks for, both name WIN19; neither existed when the `none` was declared on 2026-08-30.
---
# How the Windows client reaches a user's machine, signed

- origin: intake divergent pass, 2026-08-30
- audience: anyone who would install the Windows client without building it themselves
- platforms: windows
- proposed-by-ai: true

## What and why

The Mac side has an entire blocked brief about developer identity, signing and notarisation, because
an unsigned macOS app is effectively undistributable. Windows has the same problem with a different
shape and no brief at all, so it would be discovered at the end rather than planned for.

An unsigned Windows executable triggers SmartScreen's "Windows protected your PC" dialog, which most
users read as malware. That is a distribution blocker in the same way notarisation is on macOS, and
it is worth knowing that the check that reassures is not the check that decides: a signature can
verify under `Get-AuthenticodeSignature` and SmartScreen can still warn, because SmartScreen weighs
reputation as well as validity. A fresh certificate has no reputation.

`winget` is present on this machine and is the Windows-native distribution channel most comparable to
how a developer tool is expected to arrive. MSIX packaging gives clean install and uninstall and is
what the Windows App SDK expects; a plain installer is simpler and gives up the uninstall guarantees.

There is also a router-side question the Mac already answered its own way: the daemon currently
installs to a location and is supervised by launchd. How the daemon is installed and updated on
Windows, and whether it ships with the client or separately, is part of this rather than an
afterthought — and it connects to WIN23.

This brief deliberately does not ask for a certificate to be bought. It asks for the shape to be
decided and the unsigned path to be honest about what the user will see.

## Acceptance sketch

- A build produces an installable artifact, and installing it on a clean Windows 11 machine yields a working client.
- Uninstall removes the client and states what it leaves behind, including whether router state and credentials are kept or removed.
- The signing position is recorded: what is signed, what is not, and exactly what an unsigned install shows the user.
- The distribution channel is chosen, with what the alternatives would have been better at.
- The router daemon's installation and update path on Windows is decided alongside the client's.
- No credential or signing secret is committed, and nothing in the packaging reads one from a config file.

## Assumptions made writing this

- Assuming distribution is wanted eventually; if the Windows client is only ever built from source by its owner, this brief reduces to a build artifact and the signing question goes away.
- Assuming an EV certificate is out of scope for now, so the near-term answer is an honest unsigned path rather than a purchase.
- Assuming this is separable from WIN1, since all three framework candidates can be packaged, though the packaging details differ.
