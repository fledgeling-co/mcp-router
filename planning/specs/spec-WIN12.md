# Specification — WIN12: Pairing an iPhone to the Windows client

- status: ready-for-ai
- origin: planning/features-to-triage/WIN12-windows-pairing-sheet.md
- surface: Windows Pairing sheet (SURF-010 parity target)
- platforms: windows

## 1. Objective and Security Commitments

1. Pair an iPhone with the Windows client to receive queued capabilities.
2. Store pairing secrets securely in Windows Credential Manager (DPAPI), never in plaintext config files or logs.
3. Display pairing code and expiration countdown.
4. Distinguish failure states: wrong code, expired code, already paired, firewall blocked.
5. Provide actionable guidance if Windows Defender Firewall blocks the incoming pairing port.

## 2. Architecture & Data Model

- `PairingModels`: `PairingPhase`, `PairingRefusalReason`, `PairingSessionState`.
- `PairingPresentation`: User guidance copy, expiration formatting, and refusal messages.
- `PairingSessionModel`: Tracks pairing lifecycle and state transitions.
- `PairingDialog`: WinUI 3 XAML view displaying pairing code and expiration countdown.

## 3. Test Coverage

- `PairingPresentationTests`: Expiration countdown formatting and refusal messages.
- `PairingSessionModelTests`: Initial code generation and pairing completion.
