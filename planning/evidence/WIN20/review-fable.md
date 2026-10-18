# WIN20 — in-family adversarial review: NOT-RUN

Attempted 2026-08-30 against `claude-fable-5` from this worktree. The CLI
returned:

```
API Error: 400 {"error":"no binding for request","code":"no_binding"}
```

That is not a review. The file previously held only that error body, which
a later reader could take as a completed artefact. It is not.

Cross-family review (`codex` / `agy` / `grok`) was also unavailable on this
machine. Neither is a pass.

The live automation lane (90 passed / 0 failed / 2 unoracled) and the 26
selftest arms are independent of this review and are not offered as a
substitute for it.
