# Proactive Desktop Notification for Upstream Authentication Expiry

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Developers relying on authenticated upstream services with expiring tokens
- platforms: mac
- proposed-by-ai: true

## What and why
The router notifies the user when an upstream server's authentication token or OAuth session has expired or requires renewal, before an agent tool call fails in active use. Currently, token expiration is discovered only when an agent tool call receives an authentication error, breaking automated workflows mid-execution. Proactive alerts give developers early notice to re-authenticate upstream providers before invoking tools.

## Acceptance sketch
- When an upstream server reports an authentication failure or impending token expiry, a desktop notification alert is delivered.
- Clicking the notification opens the specific server's management view directly with a re-authentication action.
- Resolving authentication immediately clears the warning status and updates the server status indicator to active.
- Notification alerts are throttled so an offline or recurring auth error does not generate repetitive alert spam.

## Assumptions made writing this
- Assuming notifications are delivered through the standard operating system notification center rather than custom floating modal dialogs.
- Assuming re-authentication can be initiated directly from the server detail view rather than requiring server re-registration.
