# Vendored campaign instrument

`test-campaign` **0.20.1** is copied without modifications from
[`fledgeling-co/fledgeling-plugins`](https://github.com/fledgeling-co/fledgeling-plugins),
commit `a9e30330e013b8c9ecf903e5a5ba544b13c4429e`, directory `plugins/test-campaign/`.
The release was published on 20 October 2026. This replaces the 0.9.2 pin.

`test-campaign.pin.json` records the upstream commit, 168 file digests and the tree checksum:
`6667067af04f16c0db78dfc6674e67043d67e1579d56f7f147e9b828388b4515`.
The checksum hashes sorted lines containing each file's SHA-256, two spaces, its
`./`-prefixed relative path and a newline. Generated Python bytecode is outside the archive.

Check the copy and its negative controls:

```sh
python3 scripts/check-test-campaign-pin.py
python3 scripts/check-test-campaign-pin.py --selftest
```

The archive comes from Git, rather than a working tree or plugin cache:

```sh
git -C /path/to/fledgeling-plugins archive \
  a9e30330e013b8c9ecf903e5a5ba544b13c4429e plugins/test-campaign
```

Changes to the instrument belong upstream. A later update must copy another complete
committed release and replace the pin in the same change. The two repository guards that
read the instrument's effect vocabulary and mock-exclusion expressions also pin their source
files. Their digests were updated after confirming both rules are unchanged.

Run the instrument's own regression suite:

```sh
bash vendor/test-campaign/tests/run.sh
```

The suite includes one upstream monorepo catalogue test. In a router clone that test
reports a missing `plugins/test-campaign/` or `site/lib/catalogue.json`; it needs the
upstream release layout. Do not fabricate a catalogue row to clear it.

Run the campaign gates from this copy:

```sh
S=vendor/test-campaign/skills/test-campaign/scripts
python3 "$S/campaign.py" check planning/test-campaign
python3 "$S/strict-check.py" planning/test-campaign
python3 "$S/capture-lineage.py" planning/test-campaign --gate
python3 "$S/vacuity-check.py" planning/test-campaign --tests app
```

The newer instrument requires a judge identity before counting a historical visual verdict
as judged. A newly red gate is an evidence finding; this upgrade does not rewrite cases,
requirements, verdicts, brief joins or ratchet snapshots. The remaining non-test-function and
assertion-position limits of the Swift blind scanner remain recorded in the upstream changelog.

Invoking the installed skill still loads its installed package. The vendored scripts and this
pin establish what a clone can reproduce; they do not establish which installed skill a runner
invoked. The old `.claude/plugins` submodule is a separate historical artifact and is unchanged.
