# Upstream: a verification probe reports a present file as missing

- origin: tailings run over this session · 2026-08-26
- audience: Maintainers of the shared verification tooling
- platforms: n/a
- proposed-by-ai: false

## What and why
A probe that checks whether cited evidence still exists reported that a specification file "exists
nowhere in the repository or its history". The file is present, tracked, twenty-one thousand bytes long,
and the two lines cited carry exactly the text claimed. The probe appears to take a citation written as
a path with a line number, keep only the filename, and look for it at the top of the repository rather
than where the citation points.

This matters more than an ordinary false alarm because of what the probe is for. It is one of the checks
that decides whether a record's evidence can still be found, and it is ranked at the highest severity,
so a reader is invited to act on it first. A check that reports present evidence as missing spends
exactly the attention it was built to save — and, worse, teaches a reader to discount its whole class.

## Acceptance sketch
- A citation naming a path with a line number is resolved at that path, not by filename alone.
- A file that is present and tracked is never reported as absent.
- A genuinely missing cited file is still reported.
- The check's own tests include a present-file case and a missing-file case, so it is known to
  distinguish them.

## Assumptions made writing this
- Assuming this is fixed in the shared tooling and then re-pulled, following the decision already taken
  for two earlier findings of the same shape, rather than patched locally.
- Assuming the local copy keeps reporting this until the re-pull, so runs in the meantime must say so.
