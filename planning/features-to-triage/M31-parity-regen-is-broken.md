# M31 — `make parity-regen` cannot run, so the vectors are unverifiable against the reference

**Raised by:** M30's build, 2026-08-26, from a measured failure rather than a design idea.
**Depends on:** nothing. **Blocks:** any claim that the committed vectors match the reference.

## The measurement

`scripts/parity/generate-vectors.mjs` throws before it finishes, on `main` at `03c34c3` and in a
worktree alike, with a freshly built `dist/`:

```
TypeError: opts.commit is not a function
    at Module.buildManifest (dist/manifest.js:291:30)
    at async atFixedTime (scripts/parity/generate-vectors.mjs:321:16)
```

The generator calls `buildManifest` without the `commit` option that function now requires. It
produces `manifest-parse` and `manifest-missing`, then dies — so the twenty-odd vector files after
that point are never rewritten by a run of the script that produced them.

## Why it matters more than a broken script

`make parity-regen`'s whole reason, in its own words in the Makefile, is that *"the committed
vectors are what the TypeScript reference produces today, not what it produced whenever they were
last written by hand."* That target cannot run, so nothing currently checks that claim. The
vectors still compare Swift against a recorded expectation, and `make parity` is green — what is
missing is the check that the recorded expectation is still the reference's.

This is the shape the repo already treats as worse than a red: a check that reports nothing is
indistinguishable from a check that passed. `parity-regen` is deliberately out of `make all`
because it needs node and a built `dist/`, which is exactly the condition under which nobody
notices it has stopped working.

## What M30 did about it, and what it did not

M30 needed three new vector files generated from the reference and could not use the generator's
own entry point. Its sections live in `scripts/parity/generate-document-vectors.mjs`, imported by
`generate-vectors.mjs` and runnable on its own:

```
MCP_ROUTER_DIST="$PWD/dist" node scripts/parity/generate-document-vectors.mjs
```

That is a way round the break for one item's vectors, not a fix. Every other vector file still has
no working regeneration path.

## What would close it

Repair the `buildManifest` call in `generate-vectors.mjs` — supply the `commit` option the way
`src/control.ts`'s `indexOne` does, or give the generator a committer that writes into its own
scratch — then run `make parity-regen` and record what changed. **A regeneration that changes a
committed vector is the finding**, not a nuisance: it would mean a recorded expectation had drifted
from the reference and nothing had noticed.

Worth doing in the same change: give `parity-regen` a path into a target that runs, or a note in
`parity-selftest` that announces its absence loudly, so the next break is visible rather than
silent. `parity-lane-selftest` already carries that pattern — it prints `SKIPPED — this is a skip,
not a pass` rather than exiting 0 quietly.
