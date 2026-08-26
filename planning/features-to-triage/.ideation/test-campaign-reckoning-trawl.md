# Ideation Log: Test-Campaign & Reckoning Findings

- [kept] Upstream Server Health Probe and Failure Notification Policies — settings companion to configure retry and trip thresholds before marking servers offline.
- [kept] Local Network Device Discovery and Mutual Pairing Handshake — onboarding companion implementing secure mutual exchange for Mac and iOS clients.
- [kept] Portable Server Profile Export and Safe Secret Redaction — sharing companion to export upstream definitions without leaking plaintext credentials.
- [dropped] Local Fallback Response Queue for Offline Tool Invocations — dropped because buffering non-idempotent tool mutations creates silent state divergence.
- [kept] Desktop Alert on Upstream Authentication Expiry or Rate Limit — notifications companion to warn operators when OAuth tokens expire before tool calls fail.
- [dropped] Synthetic Latency Graphs on Server Cards — dropped because fabricating unobserved rolling averages violates the project honesty guardrail.
- [kept] Background Daemon and Status Popover Interactive Testability Hook — harness companion enabling headless verification of background menu bar states.
