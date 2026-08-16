I'll ground the verdict in the shipped approval path and the I4 brief, then answer the four questions directly.The I4 brief and DESIGN.md treat Mac approval as the pairing boundary; I'll read that threat model next, then judge the launch text against it.**1. No.** Removing Mac-side approval so a phone can install arbitrary-code MCP servers is not a sound thing to ship in an open-source tool other people will run. I disagree with the original `allow-install` choice.

The shipped boundary is load-bearing, not a UX leftover. `DESIGN.md` §9, the Inbox review sheet, and the pairing specs all say the same thing: pairing lets a remote party *propose* executable code; a human at the Mac is the only thing that may put it on the machine. I4 deletes that. “See and revoke” is incident response after third-party code may already have run. That is not a substitute for consent.

What would make an *optional* version responsible, and only then:

- Queue-and-approve stays the default for everyone else.
- Install privilege is a Mac-granted elevation on a *named pairing*, off by default, never implied by pairing itself.
- Visible on Settings, the pairing list, and an install history (what, when, which device, registry identity).
- Revocable on the Mac in one action; revocation kills in-flight and future installs.
- Pairing proven end to end, plus envelope versioning (`D-m6-b`), *before* any of this exists.
- No spawn while the Mac is locked; local auth if you want belt-and-braces.
- Phone commit requires the phone unlocked / biometrics.

That is still a worse threat model than today. It is the minimum if the owner insists on one-tap from the phone.

The design that gives him what he actually wants without removing approval: **faster Mac consent, not unattended install.** The questionnaire treated “second confirmation” as “most of the benefit gone.” That is only true if confirmation means walking to the laptop and opening Inbox. A notification or the menu-bar inbox band (`D-m6-d`) is couch-install with the security boundary intact. The page offered a false binary. The unused option, `decide-after-use`, is still the correct one: the phone has never left the simulator, and the pairing round trip has never been proven.

**2. Yes — two bad instructions, neither of them a jailbreak.**

The text is ordinary product work. It does not ask for exploits or to attack anything. The pairing-first stop, and “visible and revocable, not silent,” are good.

What a careful reviewer flags:

- It **closes the question I4’s own brief left open.** `I4-phone-direct-install.md` says if the design lands on a second Mac confirmation, *say so and let the owner decide* rather than ship a slower queue. The launch text says “so build it” and treats `allow-install` as implementation authority. That is the defect in the brief.
- It **binds an unproven transport to privilege removal in one runner.** A green pairing proof automatically becomes “now delete the approval step,” with no pause. Those are different jobs.
- “THIS IS THE OWNER’S OWN CHOICE… so build it” forbids the runner from concluding the design is wrong. I4.md reserved that conclusion. Owner appetite is not a reason to silence it.

**3. (d) — redesign the thing being built.** Not (a): parking leaves the next wave free to relaunch the same brief. Not (b): queue-only as the *default* should stand, but the couch-install want is real. Not (c) alone: the owner already decided, and sending the same fork back is a stall.

The replacement:

1. Split `D-m6-a` out. Prove the phone↔Mac round trip as its own item. Stop there. An unproven transport is the finding.
2. Kill I4 as specified (phone install, no Mac approval).
3. New item: faster Mac approval — notification plus popover inbox band. That is the owner’s want without the threat-model change.
4. Only after that has been used on real hardware: if he still wants one-tap from the phone, a Mac-granted, off-by-default, visible, revocable install privilege on a specific pairing. Pairing does not imply install.

**4. Refusing a third launch is right.** One retry after a transient label is the ceiling. A second denial that names the retry as routing around a denial is a hard stop on that brief. Another launch, or a reword that keeps the same work, is the thing the second denial already described.

Standing rule for the orchestrator:

- Transient first denial → one identical retry.
- Any later denial, or a denial that cites circumvention → that brief is dead. Do not rewrite it to sneak past. Do not launch it in the next wave.
- The classifier is a halt on *this execution path*, not a product verdict.
- Escalate with the blocked text, the denial count, and a disposition that is not “try again.”
- If the work is still wanted, change the feature or the owner does it themselves.

Leaving I4 as “STOPPED pending the owner’s word” is the remaining hole: the next fleet will read that as a green light to relaunch the same text. Mark the brief retired.
grok exit: 0
