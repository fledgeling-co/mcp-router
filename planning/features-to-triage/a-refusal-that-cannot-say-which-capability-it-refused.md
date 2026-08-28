---
status: to-triage
found-by: reckon 1.7.0, 2026-08-29
---

# A too-large refusal names the file and the cap but never the capability

- origin: reckon 1.7.0, `DEF-060` · 2026-08-29
- audience: someone who opens a capability's documentation and is told no
- platforms: mac
- proposed-by-ai: true

## What and why

When a capability's documentation is too large to display, the refusal names the file and the size cap
and never the capability. The panel's other refusals do identify themselves — a missing package,
an unreadable package and a not-found document all say which server they are talking about — so this
one state is the outlier rather than the house style.

Two costs, and the second is the one that makes it worth a row. For a person, a refusal that does not
name its subject is a dead end in a window that may be showing any of several servers. For the
campaign, a photograph of that state is tied to the capability it refuses **by its manifest row
alone** — which is precisely the dependency the capture-lineage rule exists to remove, since a picture
that cannot corroborate its own row is a picture whose filename is the only witness.

## Acceptance sketch

- Every refusal state in the documentation panel names the capability it is refusing, including the
  too-large one.
- The panel's titlebar identifies the capability even when no document was loaded, rather than falling
  back to a generic word.
- A screenshot of any refusal state can be tied to its subject from the pixels, without reading the
  manifest row that filed it.
- The set of frames that cannot corroborate their own row is empty, and a check fails if it is not.

## Assumptions made writing this

- Assuming the capability's identity comes from what was asked for rather than from the document that
  failed to load, since the failure is exactly when no document exists to name it.
- Assuming the file name and the cap stay in the message; the ask is that the capability joins them.
