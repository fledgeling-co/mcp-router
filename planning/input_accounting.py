"""The contract a reader satisfies when it can account for its own raw input.

`reader-accounting.py` is the gate; this is the thing a reader uses to pass it. One class, because
the contract is one sentence: a reader is handed N items, keeps M, and can name the N - M it did
not keep and why.

The convention already existed here. `ledger-reconcile.py` prints

    H examined 85 rows with a status cell; skipped 21 with fewer cells than their header (#, …)

and that second clause is the reason three of the eight instances in
`G4-assertions-that-do-not-read-their-own-quantity.md` were ever found — each time by someone
reading the skip list while attacking something else. What it is not is a mechanism: the count and
the list are assembled by hand at each site, so the next reader written in that file starts at zero
again, and six of the nine readers in it drop something they never name.

A `Tally` makes the drop the cheap path rather than the diligent one. `drop(item, reason)` is
shorter than `continue`, and what it buys is a line the reader can print that says what happened to
every item it was given.

Nothing here enforces anything at run time on its own. A tally the caller never prints is the same
silent drop with an extra step, and it is the static gate that requires the tally to be returned,
printed or yielded — see `reader-accounting.py`'s `escapes`.
"""

from collections import Counter


class Tally:
    """What one reader was handed, what it kept, and every item it dropped, with the reason.

    Reasons are grouped rather than listed one per item: a file with 341 lines that are not table
    rows should produce one clause saying so, not 341. The items themselves are kept for the
    reasons that matter — `named()` returns the dropped items under a given reason, which is what
    turns "21 rows skipped" into the list that made check H's drop findable.
    """

    def __init__(self, subject: str, source: str = ""):
        self.subject = subject
        self.source = source
        self.kept: list = []
        self.dropped: list[tuple[object, str]] = []

    def keep(self, item):
        self.kept.append(item)
        return item

    def drop(self, item, reason: str) -> None:
        self.dropped.append((item, reason))

    @property
    def total(self) -> int:
        return len(self.kept) + len(self.dropped)

    def reasons(self) -> Counter:
        return Counter(reason for _, reason in self.dropped)

    def named(self, reason: str) -> list:
        """The dropped items under one reason, for a skip list somebody can act on."""
        return [item for item, why in self.dropped if why == reason]

    def line(self) -> str:
        """One line naming the whole of this reader's input. Printed on every run, pass or fail.

        `no findings` over an unstated subset is the failure this exists to make impossible to
        report by accident, so the total comes first and the drops are never summarised away.
        """
        where = f" of {self.source}" if self.source else ""
        head = f"{self.subject} read {self.total} item{'' if self.total == 1 else 's'}{where}; " \
               f"kept {len(self.kept)}"
        if not self.dropped:
            return head + "; dropped none"
        clauses = "; ".join(f"{reason} {count}" for reason, count in self.reasons().most_common())
        return f"{head}; dropped {len(self.dropped)} ({clauses})"

    def measured_nothing(self) -> bool:
        """True when this reader was handed nothing at all — never a pass, always a broken reader.

        A reader whose input went to zero reports every downstream check clean over an empty set.
        `make test`'s zero-test guard, `no-raw-design-values.sh`'s empty-file-list guard and the
        reconciler's `examined == 0` usage errors are all this same check written three times.
        """
        return self.total == 0
