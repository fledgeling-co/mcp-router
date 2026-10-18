# Specification — WIN21: The Windows keyboard model

- status: ready-for-ai
- origin: planning/features-to-triage/WIN21-windows-keyboard-model.md
- platforms: windows

## 1. Objective and Keyboard Model

1. Replaces macOS Command shortcuts with Windows 11 platform-idiomatic equivalents (Ctrl+1..9, Ctrl+,).
2. Access keys (Alt+Letter) for fast navigation without pointer interaction.
3. F6 pane cycling between sidebar and active board.
4. Full keyboard reachability for all 10 destinations and actions.

## 2. Architecture & Data Model

- `KeyboardModels`: `KeyboardShortcut`, `WindowsKeyboardModel`.
- `KeyboardPresentation`: Shortcut lookups and pane cycling descriptions.

## 3. Test Coverage

- `KeyboardPresentationTests`: Tests shortcuts for all 10 destinations, access keys, and F6 mapping.
