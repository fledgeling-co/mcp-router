# MCP Router — Swift build entry point.
#
# CI runs these same targets rather than its own copy of the commands, so the two cannot drift.
# Everything builds unsigned: no developer account is wired up yet, and a build that requires a
# signing identity nobody has is a build nobody can run.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all

## G32 — one spelling of this directory, for every tool this file starts.
##
## `.worktrees` is a symlink onto another volume, so a worktree has two names for itself, and
## THIS FILE ALREADY HANDS OUT BOTH. Measured 2026-08-27 in one `make` run, no arguments:
##
##     CURDIR       = <volume>/Dev/mcp-router/.worktrees/G32   (make: getcwd, physical)
##     recipe $$PWD = <home>/Dev/mcp-router/.worktrees/G32     (inherited, logical)
##
## That matters because `swift-frontend` resolves a relative `-module-cache-path` against `$$PWD`
## rather than `getcwd()`. Measured the same day on a two-line `import Foundation` file with the
## cwd held constant and only `PWD` changed: the first spelling exits 0, the second exits 139
## (SIGSEGV) after `error: module '_DarwinFoundation1' is defined in both '…' and '…'` — where the
## two quoted paths are the SAME FILE, same hash directory, same name, differing only in spelling.
## A compiler segfault is the last thing anybody reads as a path problem, and it cost real time in
## Wave B twice.
##
## Pinning `PWD` to `CURDIR` gives every recipe, and every compiler under it, the physical
## spelling whichever way the runner cd'd in. In the main checkout the two are equal and this is a
## no-op. A cache filled under the OTHER spelling before this line existed is not fixed by it —
## `scripts/worktree-preflight.sh` refuses that build and says why.
export PWD := $(CURDIR)

APP_DIR    := app
PROJECT    := $(APP_DIR)/MCPRouter.xcodeproj
DERIVED    := $(APP_DIR)/.derived
UNSIGNED   := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# The ios-glass lane signs, and the rest do not. Measured 20 Aug 2026: built with
# CODE_SIGNING_ALLOWED=NO the app has no keychain access group, so SecItemCopyMatching
# returns -34018 errSecMissingEntitlement rather than errSecItemNotFound. The phone's
# Settings surface reads that as "Can't read this phone's pairing" and renders the
# unreadable state on a device that has simply never been paired — a lane artefact that
# reads exactly like a product defect. Ad-hoc signing ("-") costs one codesign step and
# makes the keychain behave as it does on a real install.
SIGNED     := CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES

## Look up a simulator by exact name; prints its udid, or nothing.
SIMCTL_NAMED_DEVICE = python3 -c "import json,subprocess,sys; \
ds=json.loads(subprocess.run(['xcrun','simctl','list','devices','-j'],capture_output=True,text=True).stdout)['devices']; \
c=[d for v in ds.values() for d in v if d.get('name')==sys.argv[1]]; \
print(c[0]['udid'] if c else '')"

## Print '<runtime-id> <device-type-id>' for the newest iOS runtime that offers an iPhone.
SIMCTL_NEWEST_IPHONE = python3 -c "import json,subprocess; \
r=[x for x in json.loads(subprocess.run(['xcrun','simctl','list','runtimes','-j'],capture_output=True,text=True).stdout)['runtimes'] if x.get('isAvailable') and 'iOS' in x.get('name','')]; \
r.sort(key=lambda x: [int(n) for n in x.get('version','0').split('.')], reverse=True); \
out=''; \
[out := out or (x['identifier'] + ' ' + t['identifier']) \
 for x in r for t in x.get('supportedDeviceTypes', []) if 'iPhone' in t.get('name','')]; \
print(out)"


IOS_DEST   ?= generic/platform=iOS Simulator
MAC_DEST   ?= platform=macOS
## Which surface `make mock-fidelity` audits. One surface has a filled ledger today (Servers);
## M15-M22 add theirs by writing planning/fidelity/<surface>.layers.json beside this one.
SURFACE    ?= servers

.PHONY: build-cli-debug all tools generate build enum-layout-stamp build-mac build-mac-release build-ios test test-ios test-ios-glass parity parity-regen parity-selftest parity-lane-selftest parity-watch-mutations mutation mutation-selftest acceptance acceptance-lanes-selftest mock-fidelity mock-fidelity-selftest role-intersection lint format clean install-default surface-reconcile surface-reconcile-arm

## G4's two harness gates run inside `lint` rather than as a stage of their own. Both are
## hermetic and finish in under ten seconds, and `lint` is where the other four script gates
## already live — a lane of its own would be a lane somebody runs separately from `all`.
##
## `reader-accounting.py` reads what every Python reader under planning/ and scripts/ discards and
## fails on one that discards silently. `null-run-gate.py` runs the hermetic assertions against
## poisoned and empty input and fails on one that cannot be made to go red. Neither reaches an
## assertion that reads a real quantity that is the wrong one; both print that boundary on every
## run rather than leaving a green to imply it.
##
## `citation-gate.py` (`G7`) is the third, and it is hermetic in the same way. It reads every
## `path:line` citation in the tracked corpus and blocks only on a STATED frame that does not hold
## at the tree it names — a false claim, where a bare citation is merely an absent one. Bare
## citations are ratcheted against `planning/citation-ratchet.json` instead, so the number can only
## fall. Renumbering a citation to the current revision earns nothing here, which is the point: a
## number with no tree and no anchor is unfalsifiable however recently it was chased.
##
## `sweep-control-gate.py` (`G8`) is the fourth, and it guards the other three. An absence check
## cannot detect its own blindness, and this corpus has four measured absence checks that could not
## fail. Every sweeping script here already carries a control; nothing checked that the next one
## does. It discovers sweeps across the tracked corpus with four named readers, requires each to
## carry a disposition, and RUNS the declared controls rather than believing the registry at
## `planning/sweep-controls.json` — so a control rotted into a no-op reddens. What exists today is
## grandfathered by name and printed as a backlog with a number on it; the gate blocks on a NEW
## undisposed sweep. Eight seconds, hermetic, and its own control plants a control that exits 1 and
## requires it to be reported failing. Its codes are 0 clean · 1 findings · 3 inconclusive (no
## registry, or an empty corpus) · 4 the control failed · 2 usage. `lint` treats every non-zero the
## same, which is right for a lint step and is why the codes have to be readable on their own.
##
## `runnable-path-gate.py` (`G9`) is the last of `lint`'s six Python gates — `py39-annotation-gate.py`
## landed on `main` between null-run and citation, and `sweep-control-gate.py` ahead of it, while
## this was in flight — and it is in `lint` for the reason it exists.
## Two tracked 0755 scripts began by `cd`-ing into a literal home path under `.worktrees/R2`; the
## directory was deleted in a routine cleanup, both scripts exited 90 on every invocation from that
## day on, and a spec went on citing one of them as a mutation gate that had run. **Nothing went
## red, because nothing invoked them.** A gate against that shipped invoked by nothing would be the
## same sentence one layer up, so it runs here rather than behind a target somebody remembers.
##
## It fails any tracked file the repository can RUN — git mode 100755, or an interpreter suffix, or
## a shebang, a union because each catches what the others miss — that names a path under `/Users`
## or `/Volumes`. `~/`, `/Applications`-class system paths and `/tmp`-class scratch paths are
## counted and printed, never blocked, each for a reason the gate states; scratch roots are
## `foreign-path-gate.py`'s axis and are deliberately not duplicated. Four seconds, hermetic, and
## its presence control plants nine instances across every class on every invocation and exits 2
## without printing a verdict if any one of them is missed — so a zero here is a measurement.
##
## `planning/hooks/install.sh --gate` (`G9`, 2026-08-27) is the same rule turned on G9's own
## remedy. The pre-commit hook that refuses a non-merge commit on `main` in the shared checkout is
## tracked at `planning/hooks/pre-commit`, but `.git/hooks` is not tracked, so the installed copy
## is derived state that can drift from the source with nothing going red — an edited tracked hook
## and a stale installed copy are indistinguishable from outside. `--check` was written to detect
## exactly that and was then invoked by nothing, which is how the hook reached a third hand-off
## still uninstalled: two verifiers recorded the gap and no instrument could.
##
## It is `--gate` rather than `--check` because CI runs `make lint` on a fresh clone, where
## `.git/hooks` holds only the samples. `--gate` splits the two states `--check` conflates: DRIFTED
## always reds, because a stale copy claims to be a control and is not; ABSENT reds only where
## linked worktrees exist, because that is where the hook has a job — it exists to tell the main
## checkout apart from a runner's worktree, and with none there is neither. The discriminator is
## counted from `git worktree list`, not sniffed from the environment. Proved red four ways and
## green on a real fresh clone; see `planning/progress/G9.md`.
##
## `pin-class-gate.py` (`P11`) runs here for the reason P9 declined to put it here in a hurry:
## "bolting an unproven gate into the lint chain at the end of a gap-fix round is how a gate ends
## up reporting success without running." It is armed twice before it is trusted — five arms of its
## own that fire on every invocation via `--control`, and seven arms in `null-run-gate.py` that run
## it against a scratch corpus built to break it — and `lint` is then the right home because it is
## hermetic, needs no node and no `dist/`, finishes in well under a second, and is where the other
## seven Python gates already live. A lane of its own would be a lane somebody runs separately
## from `all`.
##
## What it refuses: a parity vector that does not say what it pins. Five vectors have been found
## carrying a hand-copy of the reference expression they exist to pin, each proved blind by
## mutating the reference and watching `make parity-regen` stay at exit 0. Every one was found by a
## sweep, and a sweep is a snapshot. This is the standing version: `src-export` must import the
## named production export and carry no local implementation of it, `platform-builtin` may only
## reach a builtin in a closed vocabulary, and an UNANNOTATED writer fails — so the default for a
## sixth vector is refusal rather than silent admission. The five that exist today are carried by
## name in the gate's own `CARRY` constant, printed on every run, and close with `P9`.

## `evidence-citation-gate.py` (`G24`) runs here because the defect it closes is invisible to the
## person who caused it. `.gitignore:24` was `*.log`, unanchored, and the campaign writes its run
## evidence as `.log`: 42 evidence logs on disk, 0 tracked, 38 distinct log paths cited as evidence
## by the registries. Three of them were already gone — `ai/g19` merged the `.json` siblings while
## the `.log` files stayed behind in `.worktrees/G19` — and six cases went on citing paths that
## existed in one worktree and in no commit. `.gitignore` now carries a negation scoped to
## `planning/test-campaign/evidence/**/*.log`, and this is the gate that keeps it honest.
##
## It reads the INDEX, never the working tree, and that is the whole design. `os.path.exists`
## answered True for all 45 logs throughout the entire period in which none of them was tracked,
## so a check that consults the filesystem measures nothing here. A structured evidence field —
## `evidence[]`, `shot`, `source` — must name a path `git ls-files` knows; prose naming a path is
## swept, counted and printed rather than blocked, because `inventory.json`'s DEF-006 text exists
## precisely to record the shot pointers that were WRONG. Four unresolvable citations found on the
## landing run are declared by path and owner in `planning/evidence-citation-carry.json`, which can
## only shrink: a carried path that starts resolving is reported. `UNTRACKED` — on disk, in no
## commit — is never carryable, because it is the class the gate exists for.
##
## Its control plants one citation per class plus a stale carry on every invocation and exits 2
## without printing a verdict if any arm misbehaves. The arm that carries the weight is `UNTRACKED`,
## whose artifact IS written to disk in the control repo: a classifier that reads the filesystem
## answers `TRACKED` and the control fails.

## `target-resolution-gate.py` (`G7`, third axis) is the third sibling on that axis, and the split
## between the three is the whole reason it is a separate file. `citation-gate` asks whether a
## STATED FRAME holds — is the anchor at the cited line at the cited tree. `foreign-path-gate` asks
## whether the artifact behind a SCRATCH path survives. This asks whether the target a record names
## exists at all, for paths rooted INSIDE the repository and for registry ids, which is the half
## none of the three reads: `citation-gate` DROPS a citation whose path is not tracked rather than
## classifying it — 65 of them at the run this landed against — and those 65 are the top of this
## gate's population.
##
## Measured over 411 hand-written records at the landing commit: 1651 repo-rooted path citations,
## of which 1596 resolve, 10 are dead-but-framed (a tree carried, so still checkable), 10 withdrawn,
## 8 plan work-items, 5 values rather than pointers — and 22 name a target no commit reachable from
## any ref holds. 1057 id citations, all of which resolve, are foreign, or are named precisely
## because they have no row. The census is the finding; the numbers are printed on every run so
## none can be quoted without its question.
##
## It reads the INDEX rather than `HEAD`, which is `evidence-citation-gate`'s frame and not
## `foreign-path-gate`'s. Deliberate: this gate exists to stop a dead pointer being WRITTEN, and a
## gate that only sees a citation once it is committed has already let it through. `--rev <sha>`
## gives the deterministic per-commit reading `G11`'s argument wants.
##
## It survives a legitimate renumber without a waiver list, which is what decided its design —
## `G16` became `DEF-059`, `G19` `SURF-027` and `G17` `CASE-0184..0194` in one day. Registries are
## read as a UNION, so a refiling that keeps the old row leaves both ids resolving; a path citation
## carrying a tree reads `FRAMED` whatever happens to the path afterwards; and what is left is a
## renumber that deletes the old id everywhere and names no successor, which is
## `registry-drop-gate`'s undeclared drop and is declared in the same
## `planning/registry-retirements.json`. Its control holds both halves apart: a renumber that keeps
## the old row must be silent and one that does not must fire, and the run fails if they agree.
##
## Its floor is per CITING file and may only fall, for `citation-gate`'s reason — a scalar lets a
## deletion in one file buy headroom for a new dead citation in another. `--set-floor` writes it;
## checking never does.

## `foreign-path-gate.py` (`G6`) is the sibling of that one, one directory out. `evidence-citation-gate`
## asks whether a path a campaign record names is in the index; this asks whether a path a
## hand-written record cites is inside the repository AT ALL. On 2026-08-23 a terminal died and
## every `/tmp` artifact this fleet had cited went with it — four sweeps and a build log, one of
## them carrying an ACCEPTED verdict and one of them named by a live verify brief as the arm that
## decided the item. A sweep is the instrument proving a guard is armed, and a dead pointer at one
## produces no wrong answer to catch: only an absence, which reads exactly like *not yet run*.
##
## It landed on `main` at `03c34c3` deliberately NOT wired here, because it was knowingly red on
## five citations in files that branch was not permitted to write, because
## "a gate added to a shared target in a red state is a", `planning/progress/G6.md:206` at `03c34c3`
## gate that gets softened. Those five landed with the merge and the gate has been at `CITED 0` on
## `main` since. The condition it named is met, so this is the line it named — and until it
## existed, `git grep` found this gate invoked by nothing, which is the shape `G9` was blocked on
## twice.
##
## It reads the committed tree at `HEAD`, never the working tree, for `G11`'s reason: the same
## commit read from a dirty checkout and a pristine one gave opposite verdicts when uncommitted
## edits marked two citations withdrawn on disk. The cost is real and is the honest statement of
## what this line buys — a `/tmp` citation is refused on the first `lint` AFTER it is committed,
## not before. `--worktree` is the pre-commit reading and is not what runs here.
##
## Its control plants sixteen classifications, three of them negative, and refuses to print a
## verdict at exit 2 if any one is missed. The seventeenth arm runs the gate's own driver over a
## planted repository the two readers disagree about, because the plants alone left the choice
## between the readers untested: swapping the wrap-tolerant reader for the line-anchored one used
## to survive with `ALL PLANTS FIRED` and `PASS`, and now turns the control red.

## `shipped-brief-gate.py` (`G31`) runs here because the failure it closes is a number nobody
## disbelieves. Eleven items shipped, were verified and were merged on 2026-08-27 and the reckoning
## read 190 pieces of work before and 190 after: `reckon` reads the brief FILES, and a brief carries
## no state saying it shipped, so every one of them stayed on the total. That is not a reporting
## nuisance. `ship-fleet` finishes when the ledger drains AND the reconciliation is clean, so a
## reconciliation shipping cannot move is an exit condition nothing can reach.
##
## The one lever `reckon` leaves open is a frontmatter word in its `WAIVED_DECLARED` set, and a word
## is exactly the release-by-typing it refuses everywhere else. Its own ratchet cannot hold this end
## either -- briefs are exempt from it by construction -- so this gate is the missing half. Six
## refusals, each proved on a synthetic corpus on every invocation: a terminal word with no LEDGER
## row, a word over a To Do row, a word over a commit git cannot place on `main`, a `shipped-by` the
## row does not witness, a word over a failing case or an open defect, and `retired` claimed with no
## passing case behind it. The route out of the remaining-work set is a merge somebody can point at.
##
## Two words rather than one, because `shipped and measured` and `shipped and never measured` are
## different conclusions and `unjoined` -- which means nobody has looked at the brief at all -- is
## neither. On the landing run: 5 `retired`, 63 `completed`, 7 held back by a red case, 0 shipped
## briefs still declaring nothing, and the reckoning fell from 193 to 125 over an unchanged 388
## rows. Nothing was deleted; the denominator is the same one.
##
## What it does NOT fix: the join rate, which is the real lever and is still 17.7%. This makes a
## merge visible, not a surface measured. `--apply` is the only writing path and is never a side
## effect of checking. Exit codes are 0 clean, 1 findings, 2 the control failed, 3 inconclusive.

## `role-intersection-gate.py` (`G8`) is deliberately NOT in `lint` or in `all`, and the reason is
## its own subject. It exits **3** on this tree today: `planning/fidelity/popover.ledger.md` is an
## obituary — the fidelity gate exited 3 on `#statusPopover has no '.v-ideal' block` and wrote no
## table — so one surface has never been measured. That is a true verdict, not a broken gate, and
## wiring a permanent 3 into `all` would mean softening it to 0 within a week. It joins `all` when
## `popover` produces a table. Run it before any merge that touches `VOUCHED_CONTROLS`, and read
## the exit as: 0 no surface uses a role the union adds, 1 one does and it is a call to make, 3 a
## surface or a branch could not be read — which is not a clean surface — and 4 a control failed,
## so nothing it printed is evidence. 3 and 4 were one code until 2026-08-26; the standing verdict
## on this tree is 3, and a 4 here means fix the gate before reading its table.

## Run the whole gate, in the order a failure is cheapest to diagnose.
## `test-ios-glass` is in this list because `X2-ios-on-glass.md` said it would be: "The target
## exists, is documented, and joins `all` when DEF-X2-b and DEF-X2-c close." Both closed on
## 20 Aug 2026 (they became DEF-013 and DEF-017), and the lane has run 5 of 5 on eight separate
## runs since. It costs roughly two minutes and adds no new requirement — `test-ios` already needs
## a booted simulator — and it is the only stage here that proves the app runs rather than that its
## views construct.
all: tools lint build test test-ios test-ios-glass parity parity-selftest mutation-selftest mock-fidelity-selftest acceptance-lanes-selftest install-default surface-reconcile

## Fail loudly and specifically when a required tool is missing, rather than skipping the gate.
## A silently-skipped lint step is worse than no lint step: it reports success.
##
## The node half is checked here rather than where it is used, and that is the whole point: a
## fresh `git worktree` has no `node_modules` and no `dist`, `parity-selftest` is the LAST target
## `all` runs, and its own environment check therefore fires forty minutes in — after lint, both
## builds, 1483 package tests, the iOS lane and the on-glass lane have all passed. That happened
## twice on 20 Aug 2026, on two different worktrees, and cost two full gate runs. Checking here
## costs a millisecond and fails in the first second.
tools:
	@./scripts/worktree-preflight.sh
	@for t in xcodegen swiftlint swiftformat; do \
	  command -v $$t >/dev/null 2>&1 || { \
	    echo "error: $$t is not installed. brew install $$t"; exit 1; }; \
	done
	@[ -d node_modules ] || { \
	  echo "error: node_modules is missing — a fresh worktree needs it before the parity lanes."; \
	  echo "       run: npm install && npm run build"; exit 1; }
	@[ -f dist/index.js ] || { \
	  echo "error: dist/index.js is missing, so parity-lane-selftest would SKIP rather than run."; \
	  echo "       A skip is not a pass. Run: npm run build"; exit 1; }
	@echo "tools: $$(xcodegen --version | tr -d '\n') · swiftlint $$(swiftlint version) · swiftformat $$(swiftformat --version)"

## The Xcode project is generated, never committed — that is what keeps parallel branches from
## conflicting inside project.pbxproj.
generate: tools
	cd $(APP_DIR) && xcodegen generate

build: build-mac build-ios

build-mac: generate
	@source scripts/acceptance/build-freshness.sh && build_freshness_begin Debug "$(CURDIR)"
	xcodebuild -project $(PROJECT) -scheme MCPRouter -configuration Debug \
	  -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build
	@source scripts/acceptance/build-freshness.sh && build_freshness_write Debug "$(CURDIR)"

## Proves the release posture is *configured* rather than *required*: hardened runtime and the
## Developer ID identity are set, and the build still completes with signing switched off.
build-mac-release: generate
	@source scripts/acceptance/build-freshness.sh && build_freshness_begin Release "$(CURDIR)"
	xcodebuild -project $(PROJECT) -scheme MCPRouter -configuration Release \
	  -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build
	@source scripts/acceptance/build-freshness.sh && build_freshness_write Release "$(CURDIR)"

build-ios: generate
	@source scripts/acceptance/build-freshness.sh \
	  && build_freshness_begin Debug-iphonesimulator "$(CURDIR)"
	xcodebuild -project $(PROJECT) -scheme MCPRouterIOS -configuration Debug \
	  -destination '$(IOS_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build
	@source scripts/acceptance/build-freshness.sh \
	  && build_freshness_write Debug-iphonesimulator "$(CURDIR)"

## Swift Testing reports success for a suite that executed zero tests, so a target that silently
## stops matching its test files exits 0 and the gate says "passed". This guard closes that, and
## the narrower holes the obvious version of it leaves open.
##
## A listing that *fails* must not read as a suite with no tests: the two want opposite responses,
## and discarding stderr turns a compile error into "zero tests discovered", pointing whoever reads
## it at the wrong problem. So the listing's status is checked on its own, with its diagnostics kept.
##
## Discovery is counted as non-blank listing lines rather than by matching a naming convention. An
## earlier version required each line to end in `()`, which is the Swift Testing spelling — a
## healthy XCTest-style listing (`Suite/testName`) counted as zero and failed a suite that was fine.
## The shape of a line is not the signal; whether the listing named a TEST is.
##
## It used to count every non-blank line, which counts SwiftPM's build chatter along with the ids.
## Measured on one unchanged tree: 1742, 1734 and 1733 across three runs, differing only by
## build-cache state, against 1748 real ids and 3 chatter lines when warm. Nothing the gate DECIDED
## was wrong — it only ever compared that number to zero — but the line reads like a test count and
## was quoted as one, in a verdict draft and in a commit message. Two things are fixed here: the
## number is now the count of test ids, so it is the thing its label says, and the chatter is
## reported separately rather than silently folded in. The zero-check gets stronger as a side
## effect, because a listing that succeeds while naming no test now reads as zero rather than as
## however many lines the build printed.
##
## The number to quote for coverage is still `executed`, below, which comes from the xUnit report.
##
## Discovery is also not execution, and that is the gap the count below closes: a suite can
## enumerate thirty tests and run none of them, whether disabled or skipped. The gating number is
## therefore read from the xUnit report — an artifact of what actually ran — with skipped
## subtracted, rather than inferred from human-readable output whose format is free to change.
##
## And execution is not coverage, which is the gap the third block closes (M33). `app/` carries TWO
## build descriptions of the same tree — `Package.swift` for this lane and `project.yml` for
## `xcodebuild` — and they disagreed about `MCPRouter/`: SwiftPM declared no target there, so this
## target compiled nothing under the directory the Mac app's assembly lives in and still exited 0,
## while `xcodebuild` called a planted fault in that same directory fatal. Adding the target closed
## the hole. It did not close the item, because the defect was never that a lane was missing — it
## was that the missing lane REPORTED SUCCESS, and a reader of a green here still could not tell
## which of the two descriptions had run.
##
## So this target now says what it compiled, and the saying is a gate rather than an `echo`: an
## `echo` asserting "SwiftPM compiled the app" while nothing checks whether it did is the same
## unfalsifiable green one level up. `build-description-report.py` stands its claims on object
## files, runs its own poison arms first so a green here has just watched the report go red on
## demand, and the `grep` afterwards means an absent report line fails this target instead of
## passing quietly — which is the property the whole item is about.
enum-layout-stamp:
	@python3 $(APP_DIR)/Scripts/enum-layout-stamp.py $(APP_DIR)

test: enum-layout-stamp
	@set -eu -o pipefail; cd $(APP_DIR); \
	  if ! listing=$$(swift test list 2>&1); then \
	    echo "error: could not enumerate tests — this is a build or toolchain failure, not an empty suite:"; \
	    echo "$$listing"; exit 1; \
	  fi; \
	  discovered=$$(printf '%s\n' "$$listing" \
	                | grep -cE '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*\(' \
	                || true); \
	  chatter=$$(printf '%s\n' "$$listing" | grep -cE '[^[:space:]]' || true); \
	  chatter=$$((chatter - discovered)); \
	  echo "discovered $$discovered test ids ($$chatter further non-blank lines are build output)"; \
	  if [ "$$discovered" -eq 0 ]; then \
	    echo "error: the listing named no test — the suite is not running, which is a failure, not a pass"; \
	    exit 1; \
	  fi
	@set -eu -o pipefail; cd $(APP_DIR); \
	  dir="$$(mktemp -d -t mcprouter-xunit)"; \
	  trap 'rm -rf "$$dir"' EXIT; \
	  swift test --xunit-output "$$dir/report.xml"; \
	  reports=$$(find "$$dir" -name '*.xml' -size +0c); \
	  if [ -z "$$reports" ]; then \
	    echo "error: swift test wrote no xUnit report, so the number of tests that ran is unknown"; \
	    exit 1; \
	  fi; \
	  ran=$$(cat $$reports \
	         | grep -oE '<testsuite [^>]*>' \
	         | awk '{ \
	             t = 0; s = 0; \
	             if (match($$0, /tests="[0-9]+"/))   { t = substr($$0, RSTART + 7, RLENGTH - 8) } \
	             if (match($$0, /skipped="[0-9]+"/)) { s = substr($$0, RSTART + 9, RLENGTH - 10) } \
	             total += t - s \
	           } END { print total + 0 }'); \
	  echo "executed $$ran tests"; \
	  if [ "$$ran" -eq 0 ]; then \
	    echo "error: zero tests executed — a suite can discover tests, skip every one, and still exit 0"; \
	    exit 1; \
	  fi
	@set -eu -o pipefail; \
	  python3 scripts/build-description-report.py --selftest; \
	  out="$$(mktemp -t mcprouter-builddesc)"; \
	  trap 'rm -f "$$out"' EXIT; \
	  python3 scripts/build-description-report.py | tee "$$out"; \
	  if ! grep -q '^build-description: ' "$$out"; then \
	    echo "error: this target compiled a tree and did not say which description it compiled."; \
	    echo "error: that is M33 exactly — the green would be silent about a directory rather than clean over it."; \
	    exit 1; \
	  fi

## The iOS suite — the claims that cannot be made on the macOS host.
##
## `make test` runs the SwiftPM suite on macOS. That suite can prove a view constructs, that its
## copy comes from the manifest and that its state machine behaves, but it cannot prove a 44pt
## touch target, a safe-area inset, a system tab bar, Dynamic Type at an accessibility size, or
## that the *generated* Info.plist carries the camera purpose string. Asserting any of those on
## macOS would be a green light for a claim nobody measured, so they live in a hosted iOS test
## target and this target is what runs it.
##
## Same zero-execution guard as `make test`, for the same reason and one more: an iOS test bundle
## that fails to install on the simulator reports no tests and, without this, an exit code that a
## careless pipeline reads as success. The executed count is taken from the result bundle rather
## than from human-readable output.
##
## A concrete simulator is required — `generic/platform=iOS Simulator` builds but cannot run — so
## this resolves a booted or available device rather than assuming a name that may not exist on
## another machine.
## The device this lane owns.
##
## Named, and created if absent, for the reason DEF-020 records: the picker this replaces sorted
## booted devices first, so the lane ran on whichever simulator some other project happened to have
## up. That is how a lane comes to measure another product. Measured 20 Aug 2026: with another
## project holding three booted simulators, every one of these 35 tests read an empty accessibility
## tree — 51 failures across six consecutive runs, deterministic, with no change to this repo.
IOS_UNIT_DEVICE ?= MCPRouter-Unit

## The engine is warmed by a throwaway run before the graded one, and that run's result is ignored
## on purpose.
##
## `_AXSSetAutomationEnabled(true)` takes effect for the NEXT process on the device rather than for
## the one that calls it. Measured 20 Aug 2026 on `MCPRouter-Unit`: a run taken on a device left
## disabled fails 39 assertions across the same 15 test cases every time — deterministic, not a
## race, and exactly the cases that host a `ScrollView` — while the run after it, with no change to
## anything, is clean. `make all` went red on precisely that, on a suite that had just been proved
## green.
##
## So the enabling process runs first and its exit code is discarded, because a device that is
## already warm makes it a no-op and a device that is cold makes it fail for the reason the graded
## run exists to report. Nothing is inferred from it: the graded run asserts the engine for itself
## through `testTheAccessibilityEngineCanBeSwitchedOn`, which blocks on a probe of the same shape
## the failures take and goes red rather than quietly empty.

test-ios: generate
	@set -eu -o pipefail; \
	  udid=$$($(SIMCTL_NAMED_DEVICE) "$(IOS_UNIT_DEVICE)"); \
	  if [ -z "$$udid" ]; then \
	    pair=$$($(SIMCTL_NEWEST_IPHONE)); \
	    runtime=$${pair%% *}; devtype=$${pair##* }; \
	    if [ -z "$$pair" ] || [ -z "$$runtime" ] || [ -z "$$devtype" ]; then \
	      echo "error: no available iPhone simulator, so the iOS suite did not run."; \
	      echo "       This is an environment failure, not a pass — the claims it carries"; \
	      echo "       (44pt targets, safe area, the generated Info.plist) went unmeasured."; \
	      exit 2; \
	    fi; \
	    echo "test-ios: creating $(IOS_UNIT_DEVICE)"; \
	    udid=$$(xcrun simctl create "$(IOS_UNIT_DEVICE)" "$$devtype" "$$runtime"); \
	  fi; \
	  xcrun simctl bootstatus "$$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$$udid" || true; \
	  xcrun simctl bootstatus "$$udid" -b >/dev/null 2>&1 || true; \
	  echo "test-ios: simulator $$udid ($(IOS_UNIT_DEVICE))"; \
	  echo "test-ios: warming the accessibility engine on $$udid"; \
	  perl -e 'alarm shift @ARGV; exec @ARGV' 900 \
	  xcodebuild -project $(PROJECT) -scheme MCPRouterIOS -configuration Debug \
	    -destination "id=$$udid" -derivedDataPath $(DERIVED) $(UNSIGNED) \
	    -only-testing:MCPRouterIOSTests/PhoneSurfaceTests/testTheAccessibilityEngineCanBeSwitchedOn \
	    test >/dev/null 2>&1 || true; \
	  bundle="$$(mktemp -d -t mcprouter-xcresult)/result.xcresult"; \
	  perl -e 'alarm shift @ARGV; exec @ARGV' 1200 \
	  xcodebuild -project $(PROJECT) -scheme MCPRouterIOS -configuration Debug \
	    -destination "id=$$udid" -derivedDataPath $(DERIVED) $(UNSIGNED) \
	    -resultBundlePath "$$bundle" test; \
	  ran=$$(xcrun xcresulttool get test-results summary --path "$$bundle" --format json \
	         | python3 -c "import json,sys; d=json.load(sys.stdin); \
print((d.get('passedTests') or 0) + (d.get('failedTests') or 0))"); \
	  echo "executed $$ran iOS tests"; \
	  if [ "$$ran" -eq 0 ]; then \
	    echo "error: zero iOS tests executed — a bundle that fails to install reports no tests"; \
	    exit 1; \
	  fi

## The `ios-glass` lane — the app installed and driven on a booted simulator.
##
## Separate from `test-ios` because the two answer different questions. `test-ios` constructs views
## in the app's process and reads them back through our own walk of `UIView.accessibilityLabel`; it
## never taps a tab, so it cannot tell "each tab renders its own surface" from "all five render
## Settings". This target runs XCUITest out of process against iOS's own accessibility tree, which
## is what caught the tab bar announcing ["discover", "inbox", "tray", "book", "settings"].
##
## Attachments are exported into the campaign's evidence tree and renamed to the name the test gave
## them, so a PNG in `planning/test-campaign/evidence/shots/ios/` is attributable to the assertion
## that passed immediately before it was taken. `manifest.json` is kept beside them as the record of
## which test produced which file.
##
## Never opens Simulator.app: `xcodebuild test` against an already-booted device drives the runtime
## directly, which is `planning/practices/UI_VERIFICATION.md` rule 1.
##
## **The export runs on a red run too, and the target's exit status is carried past it.** Until
## 20 Aug 2026 `set -e` killed the recipe at the failing `xcodebuild`, so a red run exported no
## attachments at all — the run whose pictures are worth most produced none, and diagnosing a
## failure meant re-running by hand against a bundle path scraped out of the log. The signing fix
## below was found that way. `status` holds the result while the export completes, and the target
## still fails.
##
## **The lane signs ad-hoc where the rest of the repo does not** — see `SIGNED` at the top of this
## file for the measurement. An unsigned build has no keychain access group, and the phone's
## pairing read fails with `-34018` in a way that reads exactly like a product defect.
##
## **Deliberately not in `all` yet.** Two of its five cases are red, and both reds are findings
## about the product rather than about this target — DEF-X2-a and DEF-X2-b in
## `planning/features-to-triage/X2-ios-on-glass.md`. Wiring a known-red lane into the whole-repo
## gate would either block every unrelated commit or invite someone to soften the two assertions,
## and the assertions are the only reason the findings are visible. It joins `all` when they close.
IOS_GLASS_SHOTS := planning/test-campaign/evidence/shots/ios

## The device this lane owns, by name.
##
## **It must not share a simulator, and the previous picker deliberately did.** It listed every
## available iPhone and sorted `state != 'Booted'` first — that is, it *preferred* a device
## somebody else had already booted. On a machine where more than one project drives simulators,
## that means XCUITest taps arrive at whichever app is frontmost. Measured 20 Aug 2026: a run
## whose five tests failed on a different tab each time turned out to be sharing its device with
## another project's app, which was in the foreground; a screenshot of the "simulator" showed that
## app's onboarding rather than MCP Router. Every one of those failures read as a product defect.
##
## Named rather than pinned by udid so a fresh checkout creates its own, and so a person can find
## it in Simulator's device list and know what it is for.
IOS_GLASS_DEVICE ?= MCPRouter-Glass

test-ios-glass: generate
	@set -eu -o pipefail; \
	  udid=$$($(SIMCTL_NAMED_DEVICE) "$(IOS_GLASS_DEVICE)"); \
	  if [ -z "$$udid" ]; then \
	    pair=$$($(SIMCTL_NEWEST_IPHONE)); \
	    runtime=$${pair%% *}; devtype=$${pair##* }; \
	    if [ -z "$$pair" ] || [ -z "$$runtime" ] || [ -z "$$devtype" ]; then \
	      echo "error: no iOS runtime or iPhone device type is available, so the ios-glass lane"; \
	      echo "       did not run. This is an environment failure, not a pass — every capture"; \
	      echo "       and every per-tab surface claim went unmeasured."; \
	      exit 2; \
	    fi; \
	    echo "test-ios-glass: creating $(IOS_GLASS_DEVICE)"; \
	    udid=$$(xcrun simctl create "$(IOS_GLASS_DEVICE)" "$$devtype" "$$runtime"); \
	  fi; \
	  xcrun simctl bootstatus "$$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$$udid" || true; \
	  xcrun simctl bootstatus "$$udid" -b >/dev/null 2>&1 || true; \
	  echo "test-ios-glass: simulator $$udid ($(IOS_GLASS_DEVICE))"; \
	  bundle="$$(mktemp -d -t mcprouter-glass)/result.xcresult"; \
	  status=0; \
	  perl -e 'alarm shift @ARGV; exec @ARGV' 1800 \
	  xcodebuild -project $(PROJECT) -scheme MCPRouterIOSGlass -configuration Debug \
	    -destination "id=$$udid" -derivedDataPath $(DERIVED) $(SIGNED) \
	    -resultBundlePath "$$bundle" test || status=$$?; \
	  ran=$$(xcrun xcresulttool get test-results summary --path "$$bundle" --format json \
	         | python3 -c "import json,sys; d=json.load(sys.stdin); \
print((d.get('passedTests') or 0) + (d.get('failedTests') or 0))"); \
	  echo "executed $$ran on-glass tests"; \
	  if [ "$$ran" -eq 0 ]; then \
	    echo "error: zero on-glass tests executed — a runner that fails to install reports none"; \
	    exit 1; \
	  fi; \
	  rm -rf "$(IOS_GLASS_SHOTS)"; mkdir -p "$(IOS_GLASS_SHOTS)"; \
	  xcrun xcresulttool export attachments --path "$$bundle" \
	    --output-path "$(IOS_GLASS_SHOTS)" >/dev/null; \
	  python3 scripts/acceptance/name-glass-attachments.py "$(IOS_GLASS_SHOTS)"; \
	  exit $$status

## The parity corpus specifically — A41.
##
## `make test` proves *some* number of tests ran. That is not the claim this item needs: a port can
## delete half the vector corpus, keep every test name, and watch the test count rise because it
## added tests elsewhere. So the attestation test prints how many vector cases it actually compared,
## and this target reads that number back.
##
## Three outcomes, kept apart on purpose. A missing marker means the attestation did not run at all,
## which is the failure that looks most like success — a suite that silently stopped matching its
## own test prints nothing and exits 0. A count below the floor means the corpus shrank. Only a
## marker at or above the floor is a pass.
parity:
	@set -eu -o pipefail; cd $(APP_DIR); \
	  output=$$(swift test --filter VectorRegistryTests 2>&1) || { \
	    echo "$$output"; echo "error: the parity suite failed"; exit 1; }; \
	  marker=$$(printf '%s\n' "$$output" | grep -oE 'PARITY-VECTORS-EXECUTED: [0-9]+' | tail -1 || true); \
	  if [ -z "$$marker" ]; then \
	    echo "error: the suite printed no PARITY-VECTORS-EXECUTED marker, so the attestation did"; \
	    echo "       not run. A corpus nobody read cannot be distinguished from a corpus that passed."; \
	    exit 1; \
	  fi; \
	  count=$${marker##*: }; \
	  floor=$$(grep -oE 'executedFloor = [0-9]+' Tests/RouterCoreTests/VectorRegistry.swift | grep -oE '[0-9]+'); \
	  echo "parity: $$count vector cases compared (floor $$floor)"; \
	  if [ "$$count" -lt "$$floor" ]; then \
	    echo "error: the corpus executed $$count cases, below the floor of $$floor"; exit 1; \
	  fi

## A39 — the committed vectors are what the TypeScript reference produces *today*, not what it
## produced whenever they were last written by hand.
##
## Kept out of `all` because it needs node and a built `dist/`, neither of which a Swift-only
## checkout has. A worktree carries no `dist/` of its own, so the reference is driven from the main
## checkout via MCP_ROUTER_DIST while the comparison runs against the branch's committed vectors.
parity-regen:
	@set -eu -o pipefail; \
	  dist="$${MCP_ROUTER_DIST:-$$(git rev-parse --show-toplevel)/dist}"; \
	  if [ ! -f "$$dist/config.js" ]; then \
	    echo "error: no built reference at $$dist — run 'npm run build' in the main checkout,"; \
	    echo "       or set MCP_ROUTER_DIST. Skipping is not an option: an unrun regeneration"; \
	    echo "       check reports the same success as a passing one."; \
	    exit 1; \
	  fi; \
	  scratch="$$(mktemp -d -t mcprouter-vectors)"; \
	  trap 'rm -rf "$$scratch"' EXIT; \
	  MCP_ROUTER_DIST="$$dist" MCP_ROUTER_VECTORS="$$scratch" \
	    node scripts/parity/generate-vectors.mjs >/dev/null; \
	  if diff -ru $(APP_DIR)/Tests/RouterCoreTests/Vectors "$$scratch"; then \
	    echo "parity-regen: the committed vectors match the reference exactly"; \
	  else \
	    echo "error: regenerating the vectors changed them — the committed corpus no longer"; \
	    echo "       matches what the TypeScript reference produces."; \
	    exit 1; \
	  fi

## Every named behaviour is load-bearing — plan P6.
##
## Breaks the behaviour each named vector guards, one at a time, and requires the gate to go red.
## A vector that is present, unique and compared still proves nothing until this passes; that is the
## difference between a corpus and a decoration.
##
## Kept out of `all` because each mutation is a rebuild plus a test run. Run it before a merge.
mutation:
	./scripts/parity/mutation-gate.sh

## Can the mutation harness's FILTER go red? — G12.
##
## `mutation` is what other checks are measured against, so a filter typo silently converting it
## into the weakest evidence available is worse than an ordinary false pass. Until G12, a filter
## naming a mutation that does not exist selected nothing, ran nothing, and printed `0 — none` on
## both oracles with exit 0 — the same success a run that killed all thirty-five produces. It was
## read as evidence twice in one session before a third filter happened to match.
##
## In `all`, unlike `mutation` itself, and the reason is the whole point: the harness resolves its
## filter before the dirty-tree guard and before the baseline, so these eleven cases cost
## milliseconds and need no build. A selftest that needed a rebuild would be run before a merge —
## which is exactly when nobody runs it.
mutation-selftest:
	./scripts/parity/mutation-gate-selftest.sh

## Can the parity harness itself go red? — P4.
##
## The gate reports a coverage fraction over the census in planning/parity/surface.tsv, so the two
## files that decide that fraction are the two that can move it without anything noticing: the
## manifest check, and the fixture lane's normaliser. Both are mutated here and both must fail.
##
## The case that matters most is a DELETED row. It leaves the numerator alone and shrinks the
## denominator, so the reported coverage goes UP — measured against the pre-P4 check, four separate
## row deletions each exited 0 while quietly reporting 82 rows instead of 83.
##
## Fast, hermetic and offline: it copies the tree into scratch directories and runs no lane, no
## router and no build. In `all` for that reason, unlike `mutation` and `acceptance`.
## Which router `docs/install.sh` points the two launchd agents at.
##
## In `all` because that file decides what serves the user's own live Claude Code sessions, and
## because nothing else in this repository asserts anything about it: the install parity lanes
## deliberately do not run the installer — doing so would rewrite `~/.claude.json` and bootstrap
## agents into the caller's session — so they prove a Swift binary SURVIVES the supervision
## install.sh writes without proving install.sh chooses it. This lane extracts the choice and
## drives it. Exit 2 means an anchor went stale, which is a locator failure and not a pass.
install-default:
	./scripts/acceptance/install-router-default.sh

## P10: the five selftests are dispatched by `parity-selftests.sh`, which runs ALL of them and
## aggregates.
##
## They used to be five recipe lines. make stops a target at the first line that fails,
## `parity-manifest-selftest.sh` is first, and it was red on `main` from `b1160ef` onward because
## `planning/parity/surface.tsv` pinned `# rows: 95` against a file holding 97 — so the four behind
## it had not been reached at all. `grep -c parity-regen-selftest` over a full run log returns 0,
## and one of the four it silenced was P9's own new selftest, merged the same evening into a target
## that could not reach it.
##
## Exactly `make acceptance`'s finding (G10), one target over, and repaired the same way: the runner
## keeps going past a red selftest and prints a per-selftest table with every exit code, so the risk
## continuing carries — a green summary over a red selftest — is what the table makes impossible
## rather than what the ordering hopes to avoid.
##
## It preserves the 1-vs-2 distinction at the aggregate: 1 means a selftest failed, 2 means none
## failed but at least one could not run. make itself collapses both to 2, so run the script
## directly when the caller needs to tell them apart.
parity-selftest:
	./scripts/acceptance/parity-selftests.sh

## Proves the lanes can actually GO RED, by running each against a deliberately broken Swift
## router. It also reports failability per ROW, which is the only place that number exists: on this
## tree it reads 16 of 19 demonstrated, and names the 3 rows that are "recorded proven by a lane
## whose ability to fail on THAT row is unproven" — along with what each of those three would need,
## because all three were attempted and none has a lever through the shim.
##
## It was written as a script rather than a paragraph of evidence "for one reason: a paragraph is
## re-run by nothing" — and then nothing re-ran the script either. It appeared in no Makefile target
## and in no LANES list, so from R2-R until now it was executable, passing, and dispatched by
## nothing. `parity-manifest-check.sh` grew a guard for exactly this class, and this is the live
## instance that guard found.
##
## It needs the TypeScript reference and takes ~4.5 minutes, so it announces a skip loudly rather
## than failing a selftest that must stay runnable in a fresh worktree. A silent skip would be the
## same defect again.
parity-lane-selftest:
	@if [ -f dist/index.js ]; then \
	  ./scripts/acceptance/parity-lane-selftest.sh; \
	else \
	  echo "parity-lane-selftest: SKIPPED — no dist/index.js. This is a skip, not a pass:"; \
	  echo "  run 'npm install && npm run build' and re-run 'make parity-lane-selftest' to prove"; \
	  echo "  the lanes can still go red."; \
	fi

## Proves `install-launchd-watch`'s two terms can go red, by mutating the launchd agent this lane
## generates — a decoy WatchPaths, a blinded HOME, a resident program — and requiring each term to
## fail under the mutation aimed at it. It runs the install lane's own watch observation — the file
## `parity-install.sh` sources — rather than a copy of it, so the demonstration cannot drift from
## the thing demonstrated.
##
## Out of `all`, and out of `parity-selftest`, for a reason that is not squeamishness about cost:
## every trial waits out a 10s ThrottleInterval, a 60s settling bound and a 90s restaging bound, so
## the default 27 trials take roughly 40 minutes of mostly-sleeping wall clock. It is run when this
## row's terms change, and its numbers are recorded in the row note in planning/parity/surface.tsv.
##
## This row does not get to be proven on a series. It was `proven` once on a term that agreed
## sixteen consecutive times and measured the wrong thing (D-p1-e), so the claim now rests on the
## mutations here and the rate each one is caught at.
parity-watch-mutations:
	./scripts/acceptance/parity-install-watch-mutations.sh

## Launches both shells and asserts each renders a value that came from MCPRouterKit.
##
## Kept out of `all` because it needs things a build does not: a GUI session, an Accessibility
## grant, and a booted simulator. It is not optional though — a linker success is not evidence that
## the shared library reached the screen, which is the whole of A5 and A15.
##
## It distinguishes its outcomes: 1 is a failed assertion, 2 is an environment that could not run
## the check. Collapsing those is how "no Accessibility permission" gets reported as a broken app.
## G10: the lanes are dispatched by `acceptance-lanes.sh`, which runs ALL of them and aggregates.
##
## They used to be eight recipe lines. make stops a target at the first line that fails, `shells.sh`
## is first, and it was red on `main` for long enough that the blob was byte-identical across three
## branches — so the seven lanes behind it had not been reached at all, and a lane that has never run
## is not known to pass. The cost was not one red gate: enrolling a lane here had stopped being a way
## to make that lane run, while still reading like one in the commit message that did the enrolling.
##
## Not fixed by reordering. That makes one lane run and leaves the ordering as the thing deciding
## what gets measured. The runner keeps going past a red lane and prints a per-lane table with every
## lane's own exit code, so the risk continuing carries — a green summary over a red lane — is what
## `acceptance-lanes-selftest.sh` arms rather than what this target hopes to avoid.
##
## It preserves the 1-vs-2 distinction this target has always drawn, at the aggregate: 1 means a lane
## failed an assertion, 2 means no lane failed but at least one could not run. make itself collapses
## both to 2, so run the script directly when the caller needs to tell them apart.
## Prerequisites widened 2026-08-27, on the owner's decision, from `build-mac build-mac-release`.
##
## G10 established that this target reached only its first lane. With that fixed it reached all
## eight and reported `7 pass, 0 fail, 1 blocked` — and the one blocked lane was blocked on an
## artifact this target does not build.
## `shells.sh:495` at `ae845a1` reads `build_freshness_require Debug-iphonesimulator`, so it
## asserts against the iOS simulator bundle and BLOCKS without one; `app/.build/debug/MCPRouterCLI`
## is the same shape for the other two, and only passed above because an earlier build happened to
## leave one on disk.
##
## A lane that blocks on a missing artifact is not evidence about the product. It is the target
## declining to build what its own lane checks, and it reads as a gate with a permanent exception
## rather than as a gate. So the artifacts move into the prerequisites, and the cost moves with
## them: this target now builds the iOS simulator bundle and the debug CLI on every run, which
## takes it from seconds to minutes. That is the trade the owner took, deliberately, over leaving
## three of eight lanes asserting nothing.
##
## It stays out of `all` for the same reason it always did — it needs a GUI session, an
## Accessibility grant and a simulator, and `all` has to run where none of those exist.
acceptance: build-mac build-mac-release build-ios build-cli-debug
	./scripts/acceptance/acceptance-lanes.sh

## The debug CLI three acceptance lanes assert against. Separate from the release build at
## `install-default`, because a lane reading `app/.build/debug/MCPRouterCLI` is not served by a
## release binary sitting somewhere else.
build-cli-debug:
	cd $(APP_DIR) && swift build --product MCPRouterCLI

## Proves the aggregation above can go red, and that a red lane cannot hide inside a green total.
##
## In `all` deliberately, and this is the item's own lesson applied to its own repair: a script that
## appears in no Makefile target is dispatched by nothing, passes by hand forever, and reads as
## covered work — `parity-stream.sh` sat executable and unrun from R2-R until P3. A selftest for a
## summary is worth exactly as much as the odds anything runs it.
##
## It needs no build, no GUI session, no Accessibility grant and no simulator — it runs against
## planted scratch lanes with known exits in about a second, which is why it can sit in `all` where
## `acceptance` itself cannot.
acceptance-lanes-selftest:
	./scripts/acceptance/acceptance-lanes-selftest.sh

## M23's mock-to-SwiftUI conversion gate. Renders a surface through the measurement harness and
## diffs it against `design/mcp-router-console.html` on eight layers.
##
## Out of `all` because it needs a second compilation of the UI target — `MCP_ROUTER_MEASURE=1`
## defines MEASURE, which is what compiles the in-view harness in at all — for the same reason
## `mutation` and `acceptance` are out. Its exits are 0 clean, 1 findings, **3 inconclusive**: a
## layer the verdict depended on could not run.
##
## **make cannot carry that third state.** GNU make exits 2 for any failed recipe, whatever the
## recipe returned, so a caller that needs to tell 1 from 3 runs the script directly. This target
## prints which one happened before it fails, so the distinction survives in the log even though it
## cannot survive in the exit code — collapsing 3 into 1 is exactly the confusion the third state
## exists to prevent.
mock-fidelity:
	@./scripts/acceptance/mock-fidelity-gate.sh $(SURFACE); status=$$?; \
	if [ $$status = 3 ]; then \
	  echo "make: mock-fidelity INCONCLUSIVE (the gate exited 3) — a layer the verdict depended on could not run."; \
	elif [ $$status = 1 ]; then \
	  echo "make: mock-fidelity found differences (the gate exited 1)."; \
	fi; \
	echo "make: it reports its own exit as 2 for any of these; run scripts/acceptance/mock-fidelity-gate.sh for 0/1/3."; \
	exit $$status

## Proves that gate can reach all three exits, including 0 — against scratch trees, in about a
## second, with no MEASURE build. In `all` because a gate never observed failing is a gate nobody
## has written, and because this is the cheap half: it drives the real layer engine and stubs only
## the two external tools the layers shell out to.
mock-fidelity-selftest:
	./scripts/acceptance/mock-fidelity-selftest.sh

## G18 — the campaign's surface set against the product's own list of surfaces.
##
## The completeness gate this sits beside asks which ENUMERATED surface has no case, so a surface
## nobody ever enumerated is invisible to it. It reported clean for two milestones while the app
## shipped three surfaces the campaign had never heard of. This one derives the denominator from
## the app instead: `planning/test-campaign/bin/surface-oracle.swift` is COMPILED against the
## shipped `Destination.swift` and `RouterSheet.swift`, so a destination cannot be added without
## appearing in the count.
##
## **It is red today, on purpose, and the three names it prints are the point.** `destination:harnesses`,
## `destination:insights` and `sheet:readme` are shipped and unenumerated; G15, G16 and G17 are the
## items that add their surfaces, and each of those turns one row green by writing a binding and a
## case. Landing it green would have meant writing the bindings here and leaving the campaign with
## no surface for any of them, which is the defect with a fresh coat on it.
##
## In `all` for `mock-fidelity-selftest`'s reason turned around: a gate wired into nothing is a
## script. It needs `swiftc` and about eight seconds, and it builds no app target.
surface-reconcile:
	@/usr/bin/python3 planning/test-campaign/bin/surface-reconcile.py; status=$$?; \
	if [ $$status = 2 ]; then \
	  echo "make: surface-reconcile CONTROL FAILED (exit 2) — the gate could not see its own planted defects, so it printed no verdict."; \
	elif [ $$status = 3 ]; then \
	  echo "make: surface-reconcile BLOCKED (exit 3) — the oracle would not build or would not run. That is not a clean campaign."; \
	fi; \
	exit $$status

## The arm for the gate above: adds a tenth destination to the product with no campaign surface,
## requires the gate to name exactly that one and nothing else, restores the file from the bytes
## read before the mutation and proves the restore with SHA-256.
##
## Out of `all` because it writes to a tracked source file while it runs. It restores it in a
## `finally`, and the recorded hashes are how you check that rather than the promise.
surface-reconcile-arm:
	/usr/bin/python3 planning/test-campaign/bin/arm-surface-reconcile.py

## R6 — the PATH a spawned child inherits, measured at both routers under a scratch HOME.
##
## Its own target rather than a line in `acceptance`: it builds the release Swift CLI and indexes a
## fixture server at each router, which is a minute of work that the Mac acceptance run does not
## need. It writes nothing outside its own mktemp directory.
acceptance-r6: build-router-release
	npm run build
	./scripts/acceptance/r6-child-path.sh

build-router-release:
	cd $(APP_DIR) && swift build -c release --product MCPRouterCLI

lint: tools
	@fail=0; \
	swiftformat --lint . --config .swiftformat || fail=1; \
	swiftlint lint --strict --config .swiftlint.yml || fail=1; \
	./scripts/lint/no-raw-design-values.sh || fail=1; \
	./scripts/lint/no-wire-codable.sh || fail=1; \
	./scripts/lint/no-harness-config-writes.sh || fail=1; \
	./scripts/lint/no-harness-config-writes-selftest.sh || fail=1; \
	./scripts/worktree-preflight-selftest.sh || fail=1; \
	python3 planning/reader-accounting.py || fail=1; \
	python3 planning/null-run-gate.py || fail=1; \
	python3 planning/py39-annotation-gate.py || fail=1; \
	python3 planning/citation-gate.py || fail=1; \
	python3 planning/sweep-control-gate.py || fail=1; \
	python3 planning/runnable-path-gate.py || fail=1; \
	bash planning/hooks/install.sh --gate || fail=1; \
	python3 planning/registry-drop-gate.py || fail=1; \
	python3 planning/evidence-citation-gate.py || fail=1; \
	python3 planning/foreign-path-gate.py --quiet || fail=1; \
	python3 planning/target-resolution-gate.py --quiet || fail=1; \
	python3 planning/test-campaign/bin/capture-manifest.py || fail=1; \
	python3 planning/pin-class-gate.py || fail=1; \
	python3 planning/shipped-brief-gate.py || fail=1; \
	zsh app/Scripts/pool-mutation-gate-selftest.sh || fail=1; \
	exit $$fail

## The cross-branch role-intersection check (`G8`). Not in `all` — see the note above `all` for
## why a standing exit 3 stays out of it. Two controls run on every invocation and print above the
## table, so the zero it reports today is a measurement rather than a blind spot.
role-intersection:
	@python3 planning/role-intersection-gate.py; ec=$$?; \
	echo "role-intersection: exit $$ec  (0 clean · 1 findings · 3 inconclusive · 4 control failed · 2 usage)"; \
	echo "  make collapses ANY failing recipe to its own exit 2, which collides with this"; \
	echo "  gate's usage code. The line above is the verdict; make's status is not."; \
	exit $$ec

## Writes formatting changes in place. Not part of `all` — a gate that edits your files is a gate
## that can turn a red build green without anyone reading the diff.
format: tools
	swiftformat . --config .swiftformat

clean:
	rm -rf $(DERIVED) $(APP_DIR)/.build $(PROJECT)
