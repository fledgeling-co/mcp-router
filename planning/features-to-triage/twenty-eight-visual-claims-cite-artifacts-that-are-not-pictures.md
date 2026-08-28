---
status: to-triage
found-by: `campaign.py check` (test-campaign 0.14.1, full scope), 2026-08-29
---

# Twenty-eight visual claims stand on artifacts that are not pictures

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever reads the evidence wall and takes a visual claim to mean somebody saw it
- platforms: n/a
- proposed-by-ai: true

## What and why

The raster-visual rung is the campaign's claim that pixels were looked at. Three findings from one
run say the rung is not carrying that meaning, and they are the same contract broken three ways.

**Twenty-eight raster-visual claims cite an artifact that is not a usable capture.** CASE-0161,
CASE-0163, CASE-0165, CASE-0171, CASE-0173 and CASE-0175 cite `evidence/shots/captures.json`, which
is a manifest listing captures rather than an image of anything. CASE-0161 and CASE-0171 also cite
`evidence/runs/mac-glass-capture.log`. CASE-0185 cites `evidence/g17-document/verdicts.json` and the
same manifest. A visual claim whose artifact is JSON is a structural assertion wearing the strongest
rung's badge: it may well be true, and nobody has seen the thing it is about.

**Three raster-visual cases publish one artifact, byte for byte.** CASE-0185, CASE-0186 and
CASE-0187 all stand on `evidence/g17-document/readme.served.png`. One screenshot cannot be evidence
for three different assertions — at most one of them is what the shutter was open for, and nothing
records which.

**Five pixel claims state no origin.** CASE-0185, CASE-0186, CASE-0187, CASE-0191 and CASE-0192 name
no capture method, so nothing says the pixels came off a display server rather than out of a
renderer, a mock, or a previous run.

The three overlap by case id, which is the tell that they are one cause rather than three: the rung
accepts a claim without demanding a distinct image, from a named channel, of the thing being
claimed. Until it does, a raster-visual count is a count of labels.

## Acceptance sketch

- Every case claiming pixels cites an image a reader can open, and a case citing a manifest or a log
  for a pixel claim fails the check rather than counting toward the rung.
- No two cases asserting different things stand on the same bytes; each claim's capture depicts the
  thing that claim is about.
- Every pixel claim names how it was taken and what it was taken off, so a reader can tell a
  screenshot of a running window from an image produced any other way.
- Claims among the twenty-eight that were never really visual are re-labelled down to the rung they
  actually stand on, and the rung's total falls accordingly rather than being preserved.
- Seeding a manifest path onto a raster-visual case, or pointing two cases at one file, turns the
  check red.

## Assumptions made writing this

- Assuming some of the twenty-eight are mislabelled structural assertions and should be demoted
  rather than re-shot, since manufacturing captures for claims nobody meant visually adds pictures
  no one will look at.
- Assuming the three sharing one capture are separated by re-shooting per assertion rather than by
  collapsing them into a single case, because three assertions were worth stating.
- Assuming the check gains its teeth in the same pass as the cleanup, since a rung repaired by hand
  is a rung that fills up again.
