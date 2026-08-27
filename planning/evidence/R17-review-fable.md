# R17 — the second reader, Fable

`claude --model claude-fable-5 --effort high`, one pass, run from `/tmp/r17-review` against the
same read-only copy on 2026-08-22. Same adversarial prompt as the agy lane. Same family as the
writer, so this is a second reader and not an out-of-family check.

This lane found F1, which was then reproduced empirically against the built router; the
reproduction and what was done with it are in `R17-acceptance.md`. The leading glyph is the
lane's own session marker, left in place because this is a verbatim capture.

Verbatim below.

---

🫥 I read all six files and tried to break the change along every axis in the brief. The keep-the-row decision itself survives — no reader in these files treats an error row as indexed — but the row being kept is a destructive one, and that opens a real hole. Findings in severity order.

## F1 — The kept row erases the digest, so one failed index resets the trust anchor and the next surface is auto-approved

The change enshrines the row `buildManifest`'s catch writes as "the record". That row is a fresh object — `manifest.servers[u.name] = {`, `manifest.ts:260-265` at `1004d10` writes `{hash, builtAt, tools: [], error}` and discards `prev` entirely: its `tools`, its `digest`, and any `pending` surface held for approval.

Sequence: server `foo` is healthy with approved digest D1 (`manifest.servers[u.name] = {`, `manifest.ts:237-243` at `1004d10`). A re-index runs (`refresh`, `index --force`, or the watcher after a staged-definition edit makes it stale) and `foo`'s `listTools` fails once — a crash the *server itself* can choose to have. The catch replaces the row; `digest` is now gone. On the next successful index, `manifest.ts:236` — `if (!prev?.digest || prev.digest === digest)` — takes the **first-sight-approves branch**, and whatever surface `foo` now advertises is served without the held-for-approval diff. The rug-pull attack that `toolsDigest`'s own comment (`This is the router's most load-bearing hash, because the cached tool list is both`, `manifest.ts:37-46` at `1004d10`) exists to stop is reachable by failing one `tools/list` and re-presenting. A held `pending` surface awaiting the user's decision is likewise silently discarded at failure time.

The old delete had the same hole on the watch route, so this is not a regression — but the fix's whole argument is "this row is the record", and the record destroys a more important record. The row should be `{...prev, hash, error, builtAt}`, preserving `digest`/`pending`/`tools`.

## F2 — The context's `unionTools` defense is actually the defeat of the placard design

CONTEXT.md lists "`unionTools` skips a zero-tool entry" as evidence no reader misbehaves. True, and it proves something worse: `placardFor` (`export function placardFor(`, `manifest.ts:301-308` at `1004d10`) exists to keep a broken server's tools listed as `INOPERATIVE — <reason>` instead of silently vanishing ("a tool that silently vanished is indistinguishable from one that never existed, so it improvises"). But no writer ever produces a row with *both* `error` and non-empty `tools` — the success branches clear `error`, the catch zeroes `tools` — so the `entry?.error` arm of `placardFor` is dead code, and a previously-good server that breaks drops off the client tool list with no placard. That is R17's silence class one surface up, and it follows from the same catch shape F1 names. Same fix: preserve `prev.tools` in the failure row.

## F3 — Paths that still leave no record

- **`const routerCfg = JSON.parse(readFileSync(DEFAULT_CONFIG_PATH, 'utf8')) as {`, `watch.ts:200` at `1004d10`** — `JSON.parse(readFileSync(DEFAULT_CONFIG_PATH))` is unguarded, in contrast to the careful guard for `~/.claude.json` at lines 164-169. A corrupt `servers.json` throws out of `cmdWatch` on every fire: no watchLog line, no state save, no manifest row, and the watcher dies silently forever. This is exactly the "failure outside the try block" the brief asked about.
- **`function candidateOf(name: string, s: RawServer, port: number): UpstreamConfig`, `watch.ts:148-156` at `1004d10`** — a staged entry that `parseServer` rejects, or a self-reference, gets one `watchLog` line and never reaches `buildManifest`. No manifest row, no `/servers` presence. Acceptance criterion 1 ("regardless of how it was configured or which branch the failure took") is unmet for this branch.
- **`try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)`, `WatchIndexing.swift:156` at `1004d10`** — `try? ManifestIO.save(...)` swallows a save failure. On disk-full or a permissions slip, the backoff still records the failure (the report is appended regardless) while the manifest row silently never lands: the original R17 asymmetry — reason in watch-state, nothing in the manifest — reborn on the save-error path, with no log line saying so.
- **"saveManifest(manifestPath, manifest);", `watch.ts:273` at `1004d10`** — the node side is worse than silent: if `saveManifest` throws, the exception propagates out of `cmdWatch` *before* any `saveState` call, so `failures` (and the backoff timestamp) are never persisted. The next fire — and `~/.claude.json` churns constantly — retries immediately. A persistent disk-full turns the 5-minute backoff into a spawn-per-fire hot loop.

## F4 — Rows are now permanent, and manifest keys are no longer a subset of router config

Nothing prunes manifest rows: `// A failure record for a server that is no longer staged is dead weight.`, `watch.ts:206-209` at `1004d10` prunes only the *state* `failures` for unstaged names, and `manifest.ts` has no removal path at all — the only deleter in the system was the code this change removed. Two consequences. First, `pocketsmith` (staged, OAuth-gated, plausibly never in router config) now gets a failure row written and rewritten every backoff expiry — a manifest row for a server that exists in no router config, permanently, even after the user unstages it. Growth is bounded by distinct names, so "unbounded" is technically no — but the manifest becomes append-only history. Second, and this is the live risk: before the change, the invariant "every persisted manifest key is a router upstream or a successfully-indexed adoptee" held. It no longer does. Any reader that enumerates `manifest.servers` keys rather than joining through config — a `status` verb, `import`, the Mac app's list — now sees phantom broken servers. None of the provided files does this; I could not verify the ones that aren't here.

Related, since the manifest is keyed by name alone: for a namecheap-shaped server (declared in both files) whose staged definition *differs* from the router's, the watcher's failed index overwrites the healthy serving row for the router's same-named upstream — the serve daemon hot-reloads (`ManifestStore`) and the tools vanish mid-session, with `/servers` now attributing the *staged* definition's error to the router's server. The delete wiped the surface too, so not a regression, but keeping the row adds misattribution the delete didn't have.

## F5 — Minor: `builtAt` and persisted error spellings

`builtAt` on a failed row is the timestamp of the failed attempt. No reader in these files consumes it (`isStale` doesn't; parity excludes it), so it misleads only a human or UI reading "last built" — worth renaming in spirit (`attemptedAt`) but not a defect I can anchor to a consumer. Separately, failure rows now persist implementation-specific error spellings (`MCP error -32000: …` vs `[-32000] …`) into a file that surface.tsv says the *fixture and state lanes* compare byte-for-byte; the cli lane's `fold_rpc_code` is scoped to the watch verb only, so if those lanes ever cover a failure fixture they will redden on punctuation the cli lane already declared as a divergence.

## Verdict and the single check

The core move — keep the row — is right, and I could not produce a reader that treats an error row as indexed. But the change is **insufficient as shipped**: the row it keeps is written by a catch that destroys `digest`, `pending`, and `tools` (F1/F2), and the no-record class it was built to close still has four open doors (F3).

The single check that would most change my confidence: **add a three-step test — index a server successfully (digest D1), fail one re-index, then index successfully with a changed tool surface — and assert the new surface is held as `pending` rather than served.** Today `prev.digest === digest) {`, `manifest.ts:236` at `1004d10` auto-approves it. That one test settles whether the kept row is genuinely "the record" or a record that quietly resets the router's only tamper detection.
