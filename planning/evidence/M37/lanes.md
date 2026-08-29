# M37 — lane availability, measured 2026-08-29

| Lane | Command | Result |
|---|---|---|
| `grok-4.6 --effort xhigh` | as `referral-grok.md` | answered, 2560 bytes, on subject |
| `claude-fable-5 --effort high` | as `referral-fable.md` | answered, 3122 bytes, on subject |
| `agy --new-project --model gemini-3.7-flash-high` | same prompt, from `/tmp` | **zero-byte output file, exit 0** — recorded as a lane failure, not as agreement |
| `codex exec` | not probed | ORCHESTRATOR records the account-level usage limit; not spent |

The zero-byte file is the tell this repository already relies on: an empty `-o` target is
the real failure signal, and an exit code of 0 from these CLIs is not one. Recorded here
rather than left as silence, so the referral reads as two lanes and one down.
