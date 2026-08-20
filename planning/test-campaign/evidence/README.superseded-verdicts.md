# witness-verdicts.superseded.json

One verdict lives here, and it is kept rather than deleted because a record that
loses its own false claims is not a record.

`SURF-007`, judged `fail` against `evidence/shots/SURF-007.build.png`, reported that
"the built board's rows carry no trailing controls at all". Photographed at the design
of record's own 1156pt window the same board carries `Inspect` and `Remove…` on every
row. The controls were outside the 980pt capture the verdict was written against; the
subject was right and the frame was wrong. DEF-044 records the mechanism.

It was moved out of `witness-verdicts.json` rather than edited in place because
`capture-lineage.py` keys a subject's verdict by `subject` alone, so a known-false
`fail` sitting beside its own correction reads to the gate as a live refutation.

The other seven Mac subjects carry two verdicts each, and both stay: one judges the
980pt capture structurally, the other judges the 1156pt capture as pixels. Two
captures, two questions, two answers — none of them overturned.
