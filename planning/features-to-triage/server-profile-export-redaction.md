# Server Configuration Profile Export with Safe Secret Redaction

- origin: test-campaign and reckoning ideation · 2026-08-25
- audience: Team leads and developers sharing tool configurations across workspaces
- platforms: mac, iphone, ipad, web
- proposed-by-ai: true

## What and why
Users can export their upstream server definitions and tool catalogs to shareable configuration profiles with automatic redaction of sensitive credentials. Sharing server setups between team members or across workstations currently requires manually copying configuration files and riskily exposing embedded bearer tokens and API keys. Safe export creates clean profiles that prompt recipient users for missing credentials upon import.

## Acceptance sketch
- The export action generates a portable configuration profile containing upstream definitions, names, and arguments.
- All sensitive tokens, secrets, and private environment variables are automatically stripped or replaced with placeholder prompts during export.
- Users can review the list of included servers and confirmed redactions before completing the export.
- Importing an exported profile into another router instance prompts the recipient to enter any required credentials.

## Assumptions made writing this
- Assuming exported profiles redact all credential fields by default rather than offering an option to export plaintext secrets.
- Assuming import validates structure compatibility and flags missing required keys before activating imported servers.
