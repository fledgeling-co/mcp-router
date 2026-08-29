# M37 — referral, in family

Produced by: `perl -e 'alarm shift @ARGV; exec @ARGV' 480 claude --model claude-fable-5 --effort high -p "$(cat prompt.md)"`
Run 2026-08-29. In family, and recorded as such: it is a second reading, not a second family.

---

🫥 **Pick (A): a third `ToggleRow` in "Behaviour", staying on the word "disabled".**

**Why A.** Disabling is defined by M29 as reversible and lossless — manifest, digest, credentials and approved tools all survive, and `PATCH` flips it back. Your own rule ("undo over confirm; friction scales to blast radius only for genuinely destructive acts") therefore classifies it as an ordinary behaviour setting, not a dangerous act, and "Behaviour" is the inspector's designated writable section. A `ToggleRow` gives you exactly the furniture the state needs: a switch that reads current state at a glance, a quiet sentence to say what's kept ("Tools stop being served; configuration, credentials and the approved tool list are kept"), and `disabledReason` if you ever need to gate it. Critically, the inspector is reachable for *every* server, so A works for the brief's actual use case — a flaky server that is tripped or holding a change still has a path to disable, which C structurally cannot offer.

One phrasing note: an off-by-default toggle titled "Disable this server" is a negative toggle (switch on = server off). Consider titling it with the state it controls — e.g. the switch on = serving, row reads "disabled by you" styling when off — but whatever you choose, draw the word from the same source as the table cell.

**What the losers are genuinely better at:**

- **(B) Danger section** is better at signalling consequence — "this stops all 41 tools" lands harder next to Remove, and it matches the mock's destructive-red styling on the sheet. But that styling was contextual to a sheet about discarding a held change; importing it here miscommunicates blast radius and buries a routine troubleshooting control in the section operators are trained to avoid.
- **(C) table row slot** is better at speed and symmetry — one click, and it mirrors where `Enable` already lives. But the precedence chain means the slot is occupied precisely for the servers you most want to pause (tripped, held, unauthorised), so the affordance would vanish exactly when the brief needs it. Fine as a *later addition* for healthy idle servers; wrong as the home.
- **(D) header action row** is better at matching the design of record's eventual shape. But two of its three drawn buttons have no backing API, the menu contents are explicitly undrawn and deferred, and building speculative chrome to host one real action inverts the cost. When wake/trip land, disable can migrate into that menu; A doesn't block that.

**Secondary: stay on "disabled".** The rule "one name per state, from one source" is binding, and the state already has three shipped spellings of *disable* — the wire field, "disabled by you" in the row, "Disable mobbin" on the sheet. "Paused" is genuinely better at conveying temporariness and operator intent (which is why the brief reached for it), but introducing it now means two names for one state across UI and wire, which is the exact failure the rule exists to prevent. If "paused" is ever preferred, that's a rename of the whole state in one pass, not a fourth surface with a second word.
