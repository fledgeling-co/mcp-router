# Upstream Server Disable and Pause Action

- origin: test-campaign and reckoning findings · 2026-08-25
- audience: Developers managing multiple upstream tool providers and local MCP servers
- platforms: mac, iphone, ipad
- proposed-by-ai: false

## What and why
Users can temporarily pause or disable an upstream server without deleting its registered configuration, arguments, or authentication credentials. Currently, stopping an upstream from being exposed to connected AI clients requires removing the server entirely and re-entering its configuration later. Providing an explicit active or disabled toggle allows operators to troubleshoot flaky servers or isolate tools during testing without losing saved configuration.

## Acceptance sketch
- Each server listed in the management view displays an active or paused toggle state alongside its status.
- Disabling a server immediately hides its tools from connected clients without terminating active client sessions.
- Re-enabling a disabled server restores its tools to the active catalog without requiring re-entry of tokens or environment variables.
- Disabled servers remain visible in the configuration list with a distinct paused indicator.
- Clients attempting to call a tool from a disabled server receive an informative refusal indicating the server is paused.

## Assumptions made writing this
- Assuming paused servers retain their credentials securely at rest rather than purging secrets on disable.
- Assuming disabled status is persistent across application restarts rather than resetting to active.
