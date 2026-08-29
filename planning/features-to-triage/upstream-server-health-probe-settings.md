---
status: delivered-router-half
found-by: test-campaign and reckoning ideation, 2026-08-25; delivered as R27, 2026-08-29
reckon-sources: [REQ-029, CASE-0217, CASE-0218, CASE-0219, CASE-0220, CASE-0221, CASE-0222, DEF-063]
---

# Upstream Server Health Check and Timeout Configuration

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: System administrators and developers operating high-latency or remote upstream tools
- platforms: mac, iphone, ipad
- proposed-by-ai: true

## What and why
Operators can configure health probe intervals, request timeouts, and automatic retry limits for upstream server connections in application settings. Upstream servers that experience network interruptions or slow cold starts can cause client tool calls to hang indefinitely or trip immediately into an error state. Providing clear settings for connection health checks allows operators to balance responsiveness against tolerance for intermittent upstream latency.

## Acceptance sketch
- Settings provides adjustable controls for connection probe interval and invocation timeout thresholds.
- Upstreams exceeding the timeout threshold are flagged as degraded before being marked tripped.
- A manual re-probe action allows operators to test connection health on demand from the server detail view.
- Healthy upstreams recover automatically when subsequent health probes succeed.

## Assumptions made writing this
- Assuming timeout thresholds are configurable globally with per-server overrides rather than a single hardcoded system value.
- Assuming background health checks run passively during idle windows rather than issuing disruptive polling storms.
