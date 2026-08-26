# Single Action Router Daemon Diagnostics Bundle Export

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Developers and support engineers troubleshooting upstream connections
- platforms: mac
- proposed-by-ai: true

## What and why
Users can export a sanitized diagnostic archive containing recent activity logs, process execution status, and listener state with one click. When an upstream server hangs or fails to route requests, diagnosing the root cause requires manually gathering logs, checking process tables, and inspecting socket bindings across different terminal tools. Packaging diagnostic facts into a structured export simplifies reporting connection issues while protecting private request contents.

## Acceptance sketch
- The application menu and settings view provide an Export Diagnostics action.
- The exported archive includes recent router logs, active upstream statuses, and process execution summaries.
- All sensitive parameter values, authorization tokens, and personal file paths are automatically redacted.
- Generating the bundle takes less than two seconds and prompts the user to save a single zip archive.
- The user can preview the gathered diagnostic categories and confirmed redactions before writing the file.

## Assumptions made writing this
- Assuming diagnostic archives redact all payload arguments by default rather than offering unredacted export modes.
- Assuming the export operates entirely locally without sending data to external external services.
