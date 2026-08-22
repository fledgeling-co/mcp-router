# vendor/

`test-campaign` 0.9.2 lives here, pinned to one upstream commit, so the gates
`planning/test-campaign/` reports can be re-run from a clone of this repository rather than from
whatever version happens to be installed on the machine.

## The pin

| | |
|---|---|
| Package | `test-campaign` |
| Version | **0.9.2** |
| Upstream | `https://github.com/fledgeling-co/fledgeling-plugins` |
| Commit | `28ecd6753386ff6d480a98d6646a5b73c62dc299` — 2026-08-20, *"fix(test-campaign): 0.9.2 — the blind-mutation check was measuring itself"* |
| Vendored | 2026-08-22, from `plugins/test-campaign/` at that commit, unmodified |
| Size | 85 files, 9.0 MB. `assets/` is 8.2 MB of it: the plugin's own icon and audit imagery, which no gate reads. `skills/` — the scripts and references the gates use — is 456 KB. |
| Tree checksum | `b9acf61682d9757616c6e0cc15924e4137c5839c13d6a749d8093e3065977ce9` |

Nothing under `vendor/test-campaign/` is edited here. A change to the instrument belongs upstream,
because a script that behaves one way in this repository and another way everywhere else stops
being evidence of anything. The provenance above is what makes the copy checkable, and an edit
without a matching upstream release breaks it.

## Checking the pin

The checksum is a SHA-256 over the sorted per-file digests:

```sh
cd vendor/test-campaign && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256
```

Against upstream, given a clone of `fledgeling-plugins` at `$UP`:

```sh
git -C "$UP" archive 28ecd6753386ff6d480a98d6646a5b73c62dc299 plugins/test-campaign \
  | tar -x -C /tmp/tc-check --strip-components=2
diff -r /tmp/tc-check vendor/test-campaign
```

## Running the gates

Four scripts produce the numbers `planning/test-campaign/RUN-2026-08-20.md` quotes. Each takes the
campaign directory as its first argument and writes nothing without an explicit `--set-ratchet`:

```sh
S=vendor/test-campaign/skills/test-campaign/scripts
python3 $S/campaign.py check planning/test-campaign        # case accounting, arming, oracle rungs
python3 $S/strict-check.py planning/test-campaign          # checked-vs-unchecked, against the ratchet
python3 $S/capture-lineage.py planning/test-campaign --gate # every published capture names its subject
python3 $S/vacuity-check.py planning/test-campaign         # guarantees asserted over absent capabilities
```

`SKILL.md` and `references/` under `skills/test-campaign/` carry what each gate means and why it
exists.

## What this does not do

**Invoking the `test-campaign` skill still loads from the machine's plugin cache.** A skill
resolves its own `scripts/` directory relative to wherever the harness loaded it, so an agent that
runs the campaign runs the installed version and not this one. The copy here is for running the
gates by hand, or from a wrapper this repository owns — that wrapper is `G5-C1`, and it does not
exist yet.

**The other skills the pipeline uses are not vendored.** `mockup-fidelity`, `mac-craft`,
`design-craft` and `ux-craft` exist only in the `.claude/plugins/fledgeling-plugins` submodule,
which every worktree in this fleet leaves uninitialised on purpose — 546 MB of plugin skills where
Claude Code loads them kills the runner on context. In practice they are machine dependencies.
