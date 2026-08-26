# Mobile Companion Pairing QR Code Presentation and Expiry Countdown

- origin: test-campaign visual differential and reckoning broken findings · 2026-08-25
- audience: Mobile and desktop users connecting their phone companion
- platforms: mac, iphone, ipad
- proposed-by-ai: false

## What and why
The desktop pairing sheet displays an interactive QR code and visual countdown ring that reflects pairing token validity. Currently, the pairing sheet displays a placeholder refusal indicating that pairing transport is unavailable. Rendering an active QR code with clear expiration countdowns enables mobile users to establish secure companion connections quickly.

## Acceptance sketch
- Initiating a pairing session displays a high-contrast QR code alongside the alphanumeric pairing string.
- A visual progress ring indicates remaining validity time before the pairing code expires.
- Expired codes automatically refresh with an updated token upon user request.
- The pairing view provides clear fallback instructions for manual alphanumeric entry if the camera cannot scan.

## Assumptions made writing this
- Assuming pairing tokens expire after a fixed time window of several minutes rather than remaining open indefinitely.
- Assuming QR code rendering uses local vector generation without making external network requests.
