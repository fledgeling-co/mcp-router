# Specification — WIN9: The Windows Cleanup board

- status: ready-for-ai
- origin: planning/features-to-triage/WIN9-windows-cleanup-board.md
- surface: Windows Cleanup board (SURF-007 parity target)
- platforms: windows

## 1. Objective and Core Commitments

Cleanup answers "what is here that shouldn't be?" with explicit guardrails:
1. **Never calls anything rubbish:** No trash metaphors, no derogatory terms, no automatic culling.
2. **States its observation window:** The default 30-day window is prominently shown and explained.
3. **Explains why it might still matter:** Every row presents a legitimate operational reason why an unused capability might be retained.
4. **Non-default destructive removal:** Removal is confirmed in a dedicated dialog where Cancel is default.
5. **Explains disk vs schema:** An explainer card explains that unused servers cost only cached schema, not RAM or CPU.

## 2. Architecture & Data Model

- `CleanupPresentation`: Evaluates candidate status, returns candidacy state (`Candidate`, `NotACandidate`, `HeldOut`) and user-facing copy.
- `CleanupBoardModel`: Manages candidacy lists, selection state, and batch removal requests.
- `CleanupBoard`: WinUI 3 XAML view displaying the head, explainer card, never-called table, quiet table, and bottom action bar.

## 3. Test Coverage

- Unit tests in `CleanupPresentationTests` verifying candidacy evaluations for servers and skills.
- Unit tests in `CleanupBoardModelTests` testing selection and keep-all behaviors.
