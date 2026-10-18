# Specification — WIN13: The Windows Settings board

- status: ready-for-ai
- origin: planning/features-to-triage/WIN13-windows-settings-board.md
- surface: Windows Settings board (SURF-011 parity target)
- platforms: windows

## 1. Objective

Provide user configuration across 7 sections using Windows 11 Fluent settings idioms:
1. Router settings (endpoint, background daemon, reaper, start on sign-in).
2. Security & confirmation settings (confirmation on destructive actions, unweakened defaults).
3. Ambient notification surface settings (toggle for notification area / flyout).
4. Honest governance messages for areas not yet built in this version (Harnesses, Analyst, Updates).

## 2. Architecture & Data Model

- `SettingsModels`: `SettingsSection`, `RouterSettingsState`.
- `SettingsPresentation`: Formats section titles and honest governance descriptions.
- `SettingsBoardModel`: State management and persistence.
- `SettingsBoard`: WinUI 3 XAML view using Fluent `ToggleSwitch` controls.

## 3. Test Coverage

- `SettingsPresentationTests`: Verifies all 7 section titles and governance strings.
- `SettingsBoardModelTests`: Verifies safe default configuration and toggle updates.
