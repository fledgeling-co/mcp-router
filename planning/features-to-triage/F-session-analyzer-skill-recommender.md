# Session Analyzer and Multi-Harness Skill Recommender

- origin: user turn 1 directive · 2026-08-24
- audience: developers using multiple AI harnesses (Claude Code, Cursor, Codex, Grok) who want intelligent skill/server suggestions based on workflow patterns
- platforms: mac, web
- proposed-by-ai: false

## What and why
Analyzes user coding sessions across configured AI harnesses using each harness's designated lightweight model (Claude Haiku, Cursor Composer, Grok 4.6 medium, ChatGPT/Codex GPT-5.6-luna low) with user-selected primary and fallback channels. Identifies missing tool patterns, repetitive task patterns, and recommended plugins, skills, or MCP servers from the central marketplace, presenting recommendations via local macOS notifications and the in-app Inbox/Insights boards.

## Acceptance sketch
- Scans recent session transcripts across active harnesses (Claude `~/.claude/sessions/`, Cursor, Grok, Codex).
- Runs session analysis prompt using the configured primary CLI model, falling back to secondary if primary is unreachable.
- Synthesizes actionable recommendations matched against the Discover marketplace registry.
- Dispatches macOS local notification when high-confidence skill/server suggestions are identified.
- Displays recommendation cards in the Mac app's Inbox and Insights boards with one-click review and install.

## Assumptions made writing this
- Assuming transcript scanning respects privacy by running strictly on local CLI models without telemetry egress.
- Assuming analysis runs periodically on an idle cadence or background schedule rather than on every prompt.
