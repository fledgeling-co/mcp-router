# Specification — WIN22: Windows toast notifications for waiting decisions

- status: ready-for-ai
- origin: planning/features-to-triage/WIN22-windows-toast-notifications-for-waiting-decisions.md
- platforms: windows

## 1. Objective and Safety Rule

1. Queued items trigger Windows Action Center toast notifications when the app is in the background.
2. Safety Rule: Toast actions only open the in-app review sheet; no toast action installs or grants capabilities directly.
3. Bounded notification frequency to avoid notification spam.

## 2. Architecture & Data Model

- `NotificationModels`: `ToastNotificationPayload`, `ToastActionKind`.
- `NotificationPresentation`: Toast text builders and safety assertions.

## 3. Test Coverage

- `NotificationPresentationTests`: Payload generation and safety rule verification.
