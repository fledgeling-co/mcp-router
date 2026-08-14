# P2 — The `import` verb and the `~/.claude.json` rewrite

**Source:** `cutover` = `finish-first`.

R2-R shipped the Swift CLI and proved 8 of 10 verbs. `import` and the `~/.claude.json` rewrite it
performs remain. Registered as `D-k`. **Blocks 3 parity rows.**

Two things already known about this surface, both to be honoured rather than rediscovered:

- `ImportVerb.swift:22` uses `NSHomeDirectory()` where the reference honours `$HOME` (`D-w2`). It is
  currently unreached because `cli-import` passes `--from`, so it diverges the moment anything calls
  it without one. Fix it here.
- The rewrite is a **cross-process** write. The watcher, the daemon and the control API all write the
  same files, and R2-W built a sidecar flock for exactly this. Use it; do not invent a second scheme.

**Done means:** `import` implemented, the three parity rows proven, and the `$HOME` divergence closed.
