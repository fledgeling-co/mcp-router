# Local Network Device Discovery and Mutual Pairing Handshake

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Mobile and desktop users connecting their phone companion to the desktop router
- platforms: mac, iphone, ipad
- proposed-by-ai: true

## What and why
Users can securely pair their mobile device with their desktop router over the local network using zero-configuration discovery and a temporary pairing code. Currently, the mobile pairing sheet refuses pairing because no secure local network transport is implemented between the phone and the desktop application. Establishing a mutual pairing handshake allows phone users to review incoming tool actions and manage their router remotely across the local network.

## Acceptance sketch
- The desktop application displays a short-lived pairing code and visual QR code during the pairing flow.
- The mobile application discovers the local desktop router automatically or via manual pairing code entry.
- Completing the handshake creates an authenticated pairing session listed under connected devices in settings.
- Either device can revoke the pairing authorization at any time to immediately disconnect the remote session.
- If the local network cannot route traffic between devices, both apps provide clear diagnostic guidance rather than silent timeouts.

## Assumptions made writing this
- Assuming pairing uses secure local mutual authorization rather than relying on an external cloud relay service.
- Assuming pairing codes expire after a short time window rather than remaining permanently valid.
