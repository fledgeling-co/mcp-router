# Skill Version Usage History, Visualizations and Telemetry

- origin: user turn 1 directive · 2026-08-24
- audience: developers and team leads who need granular visibility into which skills, plugins, and MCP servers were invoked, their exact version at invocation time, and historical trend charts
- platforms: mac, web
- proposed-by-ai: false

## What and why
Provides historical tracking and rich visual analytics of skills, plugins, and MCP server invocations across all configured AI harnesses. Parses session transcripts and usage logs to record the exact version of each tool at the moment it was executed, displaying time-series charts, invocation breakdown by harness, and tool reliability metrics in the Insights board.

## Acceptance sketch
- Telemetry parser scans harness session transcripts and usage store to extract tool invocation events with timestamps and active version stamps.
- Historical invocation events are recorded in the router usage store (`usage.db`/`usage.log`).
- Insights board renders interactive charts: invocations over time (hourly/daily), usage distribution across harnesses, and most frequently used skills.
- Tool detail view shows chronological invocation history with the version used at each execution.
- Export functionality allows exporting usage history as JSON/CSV for team reporting.

## Assumptions made writing this
- Assuming transcript grepping/parsing runs locally without sending raw prompt content or sensitive data to external analytics.
- Assuming version resolution falls back to "unversioned" or plugin git commit hash when explicit semantic versions are absent.
