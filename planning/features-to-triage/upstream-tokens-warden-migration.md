# Upstream Authentication Token Migration to System Secrets Broker

- origin: reckoning unmeasured findings and secrets inventory audit · 2026-08-25
- audience: Developers and security administrators configuring upstream tools
- platforms: mac
- proposed-by-ai: false

## What and why
Authentication tokens and bearer credentials stored in router configuration files are automatically migrated to the system secrets broker. Storing sensitive API tokens in plaintext configuration files leaves credentials vulnerable to accidental exposure during repository commits or environment backups. Migrating credentials behind the system broker ensures keys are retrieved dynamically with session-scoped authorization and user consent.

## Acceptance sketch
- The router detects plaintext authentication tokens upon startup and offers a single-click migration action.
- Completing migration moves credentials securely to the secrets broker and replaces configuration values with reference identifiers.
- Upstream requests retrieve required credentials dynamically through authorized broker sessions without user disruption.
- Stored configuration files on disk retain zero plaintext API keys or private tokens following migration.
- If the secrets broker is unreachable, the router presents a clear credential entry prompt rather than failing silently.

## Assumptions made writing this
- Assuming token migration runs with explicit user confirmation rather than silently modifying configuration files in the background.
- Assuming existing environment variables can still be used for headless automation environments where no interactive broker is present.
