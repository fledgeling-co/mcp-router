# Router Gateway Log Retention and Diagnostic Rotation Settings

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Developers and system administrators monitoring long-running router instances
- platforms: mac
- proposed-by-ai: true

## What and why
Operators can configure log retention limits and automated rotation policies for the router gateway log in application settings. Long-running router instances can accumulate extensive request logs over time, consuming local disk space and slowing diagnostic queries. Providing configurable rotation thresholds ensures logs remain bounded while preserving sufficient recent activity for debugging.

## Acceptance sketch
- Application settings provide controls for maximum log size thresholds and retained archive count.
- The router gateway automatically rotates the active log when it reaches the specified file size limit.
- Rotated log archives are compressed or pruned according to the configured retention policy.
- An explicit Clear Logs action allows operators to purge historical log files on demand with confirmation.

## Assumptions made writing this
- Assuming log rotation defaults to an eight megabyte size boundary with up to five archived logs retained.
- Assuming log purging prompts for explicit confirmation before permanently deleting historical files.
