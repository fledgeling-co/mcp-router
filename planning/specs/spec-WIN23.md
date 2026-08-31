# Specification — WIN23: Router lifecycle on Windows

- status: ready-for-ai
- origin: planning/features-to-triage/WIN23-router-lifecycle-on-windows.md
- platforms: windows, router

## 1. Objective and Lifecycle Model

1. Router daemon executes inside the interactive user session (required for OAuth browser launches and user-scoped harness configs).
2. Supervision model: User logon task or in-app supervision with automatic crash restart.
3. Live reload on manifest and config modifications.

## 2. Architecture & Data Model

- `LifecycleModels`: `DaemonSupervisionKind`, `DaemonProcessStatus`, `DaemonLifecycleConfig`.
- `LifecyclePresentation`: User session requirements and supervision mode descriptions.

## 3. Test Coverage

- `LifecyclePresentationTests`: Verifies mode descriptions and OAuth/user-session rationales.
