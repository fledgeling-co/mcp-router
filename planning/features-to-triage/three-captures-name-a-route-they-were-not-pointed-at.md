---
status: in-progress
merged-as: e70ac76
found-by: `capture-lineage.py --gate` on `main`, 2026-08-27
---

# Three captures name a route they were not pointed at, and one manifest was written after the shutter

- origin: session investigation, gate run on `main` at `0d59545` · 2026-08-27
- audience: whoever reads the evidence wall and needs a picture to depict what it is filed under
- platforms: n/a
- proposed-by-ai: false

## What and why

`capture-lineage.py --gate` exits 2. Setting aside the forty-nine unaccounted files, which
`campaign-capture-catalog-audit` already covers, four findings remain and they are of two different
kinds.

**Untied — the recorded target does not resolve to the subject's route.** Three, and they need
separating rather than fixing as one:

| subject | target the channel recorded | the subject's route |
|---|---|---|
| `SURF-011` | `app://mac/insights` | `app://mac/settings` |
| `SURF-001` | `app://mac/shell` | `app://mac/servers` |
| `SURF-028` | `app://mac/servers/g17-capability/document` | `app://mac/servers/{server}/document` |

`SURF-011` is the serious one and it is the exact shape of the measured failure this gate exists to
find: a picture of the Insights board published as Settings. `SURF-001` is a surface-definition
disagreement rather than a misaimed camera — the shot is of the shell and the surface's route says
servers. `SURF-028` is a template against an instance, `{server}` against `g17-capability`, and
reporting that as a wrong subject would be the detector misreading its own input.

**Reconstructed — the manifest disagrees with the bytes.** `SURF-028`'s
`evidence/g17-document/readme.served.png` carries a recorded sha256 that does not match the file on
disk. That means the manifest entry was written after the capture rather than during it, and a
manifest written after the fact records what somebody believed rather than what the channel did.
This one landed with this afternoon's G17 merge, so it is the newest capture in the campaign and the
one whose provenance is weakest.

The gate itself is sound and was watched to fail while this was written: swapping two subjects'
manifest entries produced `seed-swap CAUGHT — swapping SURF-002 and SURF-003 produced 5 hard
failure(s)`. So the three untied findings are the gate reading correctly, not a detector defect.

Separately, `attach-shots` reports twelve attachments resting on the filename alone, `SURF-001`
through `SURF-011` plus `SURF-022`, because `captures.json` holds no entry naming what the channel
was pointed at for any of them.

## Acceptance sketch

- `SURF-011`'s published capture depicts Settings, or the surface it does depict is the one it is
  filed under.
- `SURF-001`'s route and its capture agree about which surface it is.
- A capture of a parameterised route ties to its subject without the instance being read as a
  different address.
- `SURF-028`'s manifest entry is written by the capture step as it shoots, so its recorded digest
  matches the bytes it recorded.
- No published capture is bound to its subject by filename alone.
- The seeded swap still turns the tie pass red after the changes.

## Assumptions made writing this

- Assuming the `SURF-028` template mismatch is fixed by teaching the tie pass about parameterised
  routes rather than by writing a concrete route onto the surface, since the surface genuinely
  serves many servers.
- Assuming `SURF-001`'s disagreement is settled by deciding what that surface is, rather than by
  re-shooting it, because two different answers are currently recorded about the same board.
- Assuming the unaccounted files stay with `campaign-capture-catalog-audit` rather than being
  re-litigated here.

## What settled it

`status` is `in-progress` rather than `completed` deliberately, and `shipped-brief-gate.py` is the
reason: the four findings this brief names are closed and merged as `e70ac76`, but the gate refuses
the word while `CASE-0001`, `CASE-0016`, `CASE-0101` and `CASE-0111` are failing against this
brief's subject, because `reckon` reads a declared word ahead of the evidence and `completed` would
take four failing rows off the total. Those four are the SEPARATE illness that
`glass-evidence-outlives-the-build-it-was-taken-from.md` owns, and they need a macOS re-capture. The
word moves when they do.

**The three untied captures closed at `16b5ca9`, merged as `e70ac76`, three different ways, and the separation held.**
`SURF-011` was the misaimed camera this gate exists to find: the published frame was the Insights
board, its own manifest row said `target: app://mac/insights` all along, and the fix was to restore
the Settings frame AND its row together from `cef3729` — the last commit where those bytes and that
row agreed — rather than restamping a row against new bytes. The Insights frame kept its exhibit
under `DEF-059.insights-filed-as-SURF-011.png`. `SURF-001` was a surface-definition disagreement and
`inventory.json` was the half that was wrong: the old `app://mac/servers` was not the surface's
address but the board it was PHOTOGRAPHED on, which belongs in the capture's `derivedFrom` and was
already there. `SURF-028` was the detector misreading a route template against an instance; the
surface keeps the template and publishes nothing, the three served frames are published by the
FLOW-006 steps that rendered them, and the detector limit is `DEF-061`, open and upstream.

**The manifest-after-the-shutter finding had two halves and both are now checkable.** The derivation
half closed at `16b5ca9`: `evidence/shots/captures.json` is written by `bin/capture-manifest.py` from
the manifests the capture steps write, `--check` is in `make lint`, and a re-run of any lane moves
the gate's copy in the same movement as the frames. The ORDERING half is added here, as
`glass-build-gate.py`'s third pass and `CASE-0343`: a published capture must carry `capturedAt`, a
capture-time window-title readback and the CGWindowID the shutter used — none of which can be
recovered afterwards — or an explicit `provenanceGap` saying that it cannot. Watched to fail:
removing `capturedAt` from one row reddens that row and no other
(`evidence/runs/glass-build-gate.selftest.log`, arm 4).

`capture-lineage.py --gate` exits 0 on this tree over 21 published captures, and the seeded swap
still CAUGHT — `evidence/runs/capture-lineage.wa5.log`.

**Not settled.** `surf-022-consent-auth-states.png` still has no capture-time record anywhere and
carries a `provenanceGap` rather than an invented row; only a re-take closes it, and that re-take is
macOS work. `DEF-061` is open upstream. `DEF-054`'s twelve filename-only attachments are unchanged.
