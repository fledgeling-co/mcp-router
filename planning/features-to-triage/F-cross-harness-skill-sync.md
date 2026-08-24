# Cross-Harness Skill and Plugin Profile Synchronization

- origin: ideation past the ask (turn 1 multi-harness thesis) · 2026-08-24
- audience: developers switching between Cursor, Claude Code, Codex, and Grok who want consistent skills and configurations without manual duplication
- platforms: mac, web
- proposed-by-ai: true

## What and why
Allows users to define shared skill and MCP server profiles that automatically propagate across all installed AI harnesses (Claude Code, Cursor, Codex, Grok). When a new skill or MCP tool is installed or updated in the central marketplace, the router synchronizes configuration adapters for each harness according to user-selected preferences.

## Acceptance sketch
- Profile manager in Mac app allows creating and toggling skill bundles (e.g. "Frontend Dev", "Security Audit").
- Reconciles harness configuration files (`~/.claude.json`, Cursor configs, Grok settings) to match active profile.
- Detects configuration drift between harnesses and alerts the user with a visual diff.
- Supports single-click sync to align all harnesses with the central MCP router catalog.

## Assumptions made writing this
- Assuming synchronization modifies harness configuration files only when explicitly triggered or confirmed by the user.
- Assuming harness-specific syntax or features are adapted cleanly by the router's harness reconciliation layer.
