# Brief template — and the one line that decides whether this brief can ever be retired

`reckon` ignores every file whose name starts with `BRIEF-TEMPLATE`, so this file is not itself a
brief and is not counted as work. Copy the frontmatter block below into a new brief; the prose
sections after it are the shape the queue already uses.

## The frontmatter

```yaml
---
status: to-triage
found-by: <who or what found this, and when>
reckon-sources: [DEF-043, CASE-0184]
---
```

`reckon-sources` is the whole of it. It is a list of registry ids — `REQ-`, `CASE-`, `DEF-`,
`SURF-`, `FLOW-`, `COMP-` — naming **what in the campaign registry would settle this brief**.
`reckon` unions that list straight into its cited set at confidence 1.0, which is the only channel
that ties a brief to evidence at all: every join edge this repository holds is a citation somebody
typed, and a brief that types none can never leave the remaining set however much ships.

**Write it on one line.** `reckon`'s frontmatter parser is line-based and splits on the first
colon, so a YAML block list —

```yaml
reckon-sources:
  - DEF-043
```

— leaves the value empty and the ids are read by nothing. The gate agrees with `reckon` here rather
than being more generous than it, so a brief in that shape reads `UNDECLARED` and blocks, which is
the failure surfacing where you can see it rather than at the next reckoning.

Three things it is not:

- **It is not a claim that the work is done.** It names what would answer the question. If the
  target is a failing case or an open defect, the brief classes `broken` — which is the registry
  telling you the work is real, and is what you wanted the field to be able to say.
- **It is not a form to satisfy.** An id you have not read is worse than no id: `reckon` reads a
  cited id the registry does not hold as evidence that the thing is *absent from the product*, so a
  wrong one manufactures a finding. `planning/brief-target-gate.py` refuses a declared id no
  registry holds, and that refusal is held at zero rather than ratcheted.
- **It does not have to be in the frontmatter.** A registry id written in the brief's prose joins
  just as well, as long as it is not inside a fenced block, an HTML comment or a struck-through
  span — `reckon` blanks all three before it scans, and so does the gate.

## When nothing in the registry answers to it yet

Say so, in the frontmatter, with the reason. This is a different fact from "nobody has looked at
this", and it is the fact a reader can act on:

```yaml
---
status: to-triage
registry-target: none
no-target-reason: <why no case, requirement or defect covers this yet>
---
```

The reason has to be a sentence — the gate holds it to 24 characters — because an escape hatch
that costs nothing becomes the cheapest class and the field stops meaning anything.

## The body

```markdown
# <one sentence naming the defect or the change, not the area>

- origin: <where this came from, and when>
- audience: <who is worse off until this lands>
- platforms: <mac / ios / router / n a>

## What and why

<The measurement. Numbers with their denominators, and the mechanism stated precisely enough that
somebody could disagree with it.>

## Acceptance sketch

- <what is true when this is done, in terms somebody can check>

## Assumptions made writing this

- <every reading you took that another reader might not>
```

## The gate

`python3 planning/brief-target-gate.py` runs in `make lint` and partitions every brief by how it
names its target. A brief file the ratchet does not already name has a floor of zero, so a new
brief that declares nothing turns `make lint` red until it declares something — one of the two
blocks above. `--list UNDECLARED` prints the existing backlog; `--agree` cross-tabulates the gate's
classes against `reckon`'s over the real queue.
