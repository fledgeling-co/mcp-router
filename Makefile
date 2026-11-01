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
## Which SwiftPM build system every `swift build` / `swift test` below uses. `make test` reads the
## build description through `scripts/build-description-report.py` (M33), and that report reads
## llbuild's plan at `.build/<config>.yaml`. SwiftPM 6.4 defaults to `swiftbuild` on Xcode 27, which
## writes under `.build/out/` and produces no such plan, so the report found nothing to read after
## every test had passed. `native` still writes the plan. It is deprecated in SwiftPM 6.4 and prints
## a warning, so this is a stopgap: the report needs porting to `.build/out` before native goes.
SWIFT_BUILD_SYSTEM ?= native
## Which surface `make mock-fidelity` audits. One surface has a filled ledger today (Servers);
## M15-M22 add theirs by writing planning/fidelity/<surface>.layers.json beside this one.
SURFACE    ?= servers

.PHONY: node-e2e
.PHONY: all tools generate build enum-layout-stamp build-mac build-mac-release build-ios test test-ios test-ios-glass parity-regen acceptance acceptance-lanes-selftest mock-fidelity mock-fidelity-selftest role-intersection lint format clean install-default surface-reconcile surface-reconcile-arm

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
## `parity` and `parity-selftest` left `all` on 2026-10-19. The owner retired the Swift router, and
## parity stopped gating a release (plan-retire-swift-router.md, G1). Their targets were removed with
## the Swift router's build gates (G2). Its source and dual-router harness were deleted on 2026-11-01.
all: tools lint build test test-ios test-ios-glass mock-fidelity-selftest acceptance-lanes-selftest install-default surface-reconcile

## Fail loudly and specifically when a required tool is missing, rather than skipping the gate.
## A silently-skipped lint step is worse than no lint step: it reports success.
##
## The node half is checked here rather than where it is used, and that is the whole point: a
## fresh `git worktree` has no `node_modules` and no `dist`, `parity-selftest` was the LAST target
## `all` ran, and its own environment check therefore fired forty minutes in — after lint, both
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
	  echo "error: node_modules is missing — a fresh worktree needs it before the TypeScript gates."; \
	  echo "       run: npm install && npm run build"; exit 1; }
	@[ -f dist/index.js ] || { \
	  echo "error: dist/index.js is missing, and the acceptance lanes drive the TypeScript router from it."; \
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
	  if ! listing=$$(swift test --build-system $(SWIFT_BUILD_SYSTEM) list 2>&1); then \
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
	  swift test --build-system $(SWIFT_BUILD_SYSTEM) --xunit-output "$$dir/report.xml"; \
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
## R29's two node proofs, together, because they are halves of one claim and a green on one
## alone says nothing about the other. Deliberately NOT in `lint`: that lane is hermetic and
## needs neither node nor `dist/`, and a member that requires a TypeScript build would take
## that property away from the other twenty-three.
##
## `e2e-session-push` builds its own session registry, binds its own socket and pushes only at
## that. It never reads the real registry: a live session on this machine is somebody else's
## work, and a message arriving mid-task is an interruption they pay for.
node-e2e:
	@set -eu -o pipefail; \
	  npm run --silent build; \
	  echo "== e2e-session-push (the socket ask) =="; \
	  node scripts/e2e-session-push.mjs; \
	  echo; echo "== e2e-live-reload (the tool-list tell) =="; \
	  node scripts/e2e-live-reload.mjs

acceptance: build-mac build-mac-release build-ios
	./scripts/acceptance/acceptance-lanes.sh

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


## `raster-claim-gate.py` (`J3`) is the ninth Python gate in `lint`, and it is here rather than
## behind a campaign target because the rule it holds is the campaign's strongest claim: that
## somebody looked at pixels.
##
## Measured 2026-08-29 over 114 cases, 32 of them on the raster rung: **28 pixel claims cited an
## artifact that is not a picture** — six mac-glass cases cited `evidence/shots/captures.json`, a
## manifest, and two of those also cited a run log; five swiftui cases cited a verdicts file, a
## manifest, a run log and a wire response between them. **Three cases published one PNG byte for
## byte.** **Five named no capture method at all.** The three findings overlap by case id, which
## is the tell that they are one cause rather than three: the rung accepted a claim without
## demanding a distinct image, from a named channel, of the thing being claimed.
##
## `campaign.py check` finds two of the three and is how all of it was found. It cannot be the
## enforcement: `vendor/test-campaign/` pins **0.9.2**, whose `campaign.py` has neither
## `RASTER_RUNGS` nor `inspect_raster`, and the version that has them is whichever one a shared
## plugin cache happens to hold. A rule enforced only there leaves with the cache. This runs from
## the tree, over the tree, on every lint, in under a second with no node and no `dist/`.
##
## What it refuses: a pixel claim with no artifact, one whose artifact is not a raster by its own
## first bytes, two claims standing on one file's bytes without both declaring the share, a claim
## naming no `capture.channel` or one outside the closed vocabulary, a `capture.derivedFrom` that
## is not itself a picture, and any cited path the INDEX does not hold. What it deliberately does
## not do is score a picture — no density or entropy floor can separate a failed capture from a
## legitimately sparse empty state — and it does not adjudicate whether a picture is OF its
## subject, which is `capture-manifest.py` and `capture-lineage.py`'s axis.
##
## Ten control arms run on every invocation, one per rule plus a clean corpus that must stay green
## and a declared share that must be admitted; any arm misbehaving exits 4 and prints no verdict,
## because a zero from an instrument that cannot see the defect is not a measurement. A run in
## which no raster case resolved to `pass` exits 3 rather than reporting clean.

## `effect-class-vocabulary-gate.py` (`WE3`) is the sibling of `defect-status-vocabulary-gate.py`
## one axis over, and it exists because the failure it catches is SILENT AND GREEN.
##
## An effect class outside `campaign.py`'s closed `EFFECT_CLASSES` does not fail the census -- it
## drops out of the population. Measured on this tree by planting `outbound-sockett`, one letter,
## on `REQ-016`: `vacuity-check.py --gate` went from `uncensused: examined=17 findings=1` to
## `examined=16 findings=0`. The typo did not produce a finding; it took a requirement off the
## list of things anybody has to prove, and the census got GREENER.
##
## R1 is blocking and covers the 44 requirements. R2 is a RATCHET over cases, because 31 of the
## 49 cases naming a `witness.effect` name a class the vocabulary does not carry -- `machine-state`
## x25, `file` x2, and `os-record`, `process`, `notification`, `ui-state`. They are not a spelling
## accident and are deliberately not remapped: `process` over `Get-ScheduledTaskInfo` is a rename,
## but `machine-state` over *"the router's own /servers listing, read over the control API"* is a
## recorder INSIDE the product, and whether that case belongs at `effect-witness` is a judgement
## about the case rather than about a word. Picking the nearest legal spelling for all 31 would
## turn 31 rows green while answering neither question. Filed as `DEF-502`; the ratchet holds the
## exact roster, so a 32nd row fails and a row leaving it lowers the floor.
##
## `campaign.py check` does compute this and cannot report it: its line reads `40 effect-witness
## claim(s) with no recorder, no effect class, or a count of zero` and then caps the detail at
## twelve lines, which on this campaign are twelve lines about four cases with missing recorders.
## All 31 class findings are inside that 40 and none is printed.
##
## The vocabulary is parsed out of `vendor/test-campaign/.../campaign.py` under a recorded
## SHA-256 rather than copied here, so this file cannot become a third vocabulary; a re-vendor
## that moves the tuple exits 2 NOT COMPARED. Watched: R1 red on the planted letter and green on
## revert, R2 red at floor 0 and green at floor 31, transcript in
## `planning/evidence/WE3/effect-class-vocabulary-gate.baseline.txt`.

## `mock-exclusion-gate.py` (`WE3`) runs here because the defect it closes is one no gate in
## `lint` could see: it lived in the gap BETWEEN this repository's declarations and the pinned
## instrument's, and every gate on either side of that gap was green while it stood.
##
## `attach-shots.py` and `capture-lineage.py` both drop an image with a directory part named
## EXACTLY `mock` before matching -- the instrument's own guard against publishing a render of the
## design as a photograph of the build. This repository kept its hi-dpi renders at
## `evidence/shots/mock-hidpi/`, which is not that name, so both tools walked them. Measured on
## `5934c38f` with the pinned 0.9.2: `attach-shots.py --apply --filename-only` attached
## **SURF-009** to `evidence/shots/mock-hidpi/SURF-009.full.png`, a render of the DESIGN, because
## SURF-009 is the one surface with a design of record and no build capture (`DEF-051`) and
## nothing outranked it. The other ten were saved by sort order that does not hold across
## platforms. The renders now live under `evidence/shots/mock/hidpi/`, inside the guard.
##
## What runs here is not a check that the directory has that name. It is the equality the rename
## restored: the set `capture-manifest.py` excludes as a render of the DESIGN, and the set the
## vendored rule refuses to attach, must be the same set (R2 and R3, the two directions). Both
## sides are read rather than copied -- `MOCK_DIRS` by import, the exclusion line out of
## `vendor/test-campaign/` under a recorded SHA-256 -- so a re-vendor that moves the rule exits 2
## NOT COMPARED rather than asserting yesterday's rule, and the pin is a digest rather than a
## `HEAD:` comparison, which is what `DEF-443` turned into a self-comparison on merge.
##
## Watched to fail before it passed: 11 findings against the tree as it stood, one per render;
## green after; and the R1 pin refused a copy of the instrument with its exclusion line altered.
## Transcript at `planning/evidence/WE3/mock-exclusion-gate.baseline.txt`.

## `forced-state-assert.py --control` (`J5`) is in `lint` for the reason its own lane cannot be.
##
## `planning/test-campaign/bin/forced-state.sh` starts a real router, drives the built Debug app
## against it in three arranged conditions — cold, running, and stale with the router killed
## underneath a live app — and photographs the Servers board in each. That needs a build, a display
## server and an Accessibility grant, so it belongs to `acceptance` and never to `lint`.
##
## What runs here is the ARM. Almost everything the assertion claims is that a string is NOT in a
## file: `REQ-005` is a promise that a count goes absent, and an absence check that is pointed at
## the wrong file, the wrong column or the wrong state passes exactly as loudly as one that is
## right. So `--control` builds a scratch observation set in a temp directory that is never this
## campaign, proves the clean set passes, then plants ONE defect per check — 38 of them, one for
## every check the clean run makes — and requires each to be seen. A check with no mutation behind
## it fails the control rather than being counted, so the arm cannot fall behind the assertions it
## arms. It is hermetic, needs no router and no `.app`, and finishes in under a second.
## `instrument-census.py` (`R19`) runs here because the claim it retires is one no reviewer can
## check by reading. R19's resolution paragraph made a statement about instrument coverage four
## times and was wrong four times, each time about a different instrument, and each refuting
## instrument was one no record had ever named — `IndexFailureRecordTests`, then `parity-cli.sh`,
## then `parity-overlap.sh`, then `WatchAdoptionTests`. Between the third and fourth passes `main`
## brought `parity-divergence.sh` in underneath the paragraph, so the set grows from the trunk as
## well as from a verifier's arm.
##
## What it refuses is a tree whose instrument set has moved while `planning/instrument-census.tsv`
## has not. It runs nothing and claims nothing about what any instrument catches: it derives the
## population from `git ls-files`, the reach of each row from an INVOCATION SHAPE in that row's own
## source with the matched token carried in the row, and containment from recipes and dispatch
## lists. The one edge that pays for the file is `make test`'s — an unfiltered `swift test` contains
## every suite in the package, which is why `make test catches none of these arms and structurally
## cannot` was refutable from two other sentences in the same paragraph.
##
## Its control is 15 arms, and nine of them require a class NOT to fire. That direction is the
## whole difficulty: prose about `dist/index.js`, an echoed repair instruction and a path named in
## a comment each read as reach or containment in this reader's first cut, and a census that
## over-claims is the same defect as the paragraph it exists to bound.

## `planning/carrier-parity-gate.py` is no longer run by `lint` (plan-retire-swift-router.md, G4).
## When it last ran it reported one undispositioned landing, f53242b5 (the log rotation), and that
## finding stays open.
lint: tools
	@fail=0; \
	swiftformat --lint . --config .swiftformat || fail=1; \
	swiftlint lint --strict --config .swiftlint.yml || fail=1; \
	./scripts/lint/no-raw-design-values.sh || fail=1; \
	./scripts/lint/no-wire-codable.sh || fail=1; \
	./scripts/lint/no-harness-config-writes.sh || fail=1; \
	./scripts/lint/no-harness-config-writes-selftest.sh || fail=1; \
	./scripts/lint/no-telemetry-egress.sh || fail=1; \
	./scripts/lint/no-telemetry-egress-selftest.sh || fail=1; \
	./scripts/lint/no-harness-skill-writes.sh || fail=1; \
	./scripts/lint/no-harness-skill-writes-selftest.sh || fail=1; \
	./scripts/worktree-preflight-selftest.sh || fail=1; \
	./scripts/warden/selftest.sh || fail=1; \
	python3 planning/reader-accounting.py || fail=1; \
	python3 planning/null-run-gate.py || fail=1; \
	python3 planning/py39-annotation-gate.py || fail=1; \
	python3 planning/citation-gate.py || fail=1; \
	python3 planning/ledger-reconcile.py || fail=1; \
	python3 planning/sweep-control-gate.py || fail=1; \
	python3 planning/scope-invariance-gate.py --quiet || fail=1; \
	python3 planning/instrument-census.py || fail=1; \
	python3 planning/runnable-path-gate.py || fail=1; \
	bash planning/hooks/install.sh --gate || fail=1; \
	python3 planning/registry-drop-gate.py || fail=1; \
	python3 planning/defect-status-vocabulary-gate.py || fail=1; \
	python3 planning/defect-status-vocabulary-gate.py --selftest || fail=1; \
	python3 planning/effect-provider-gate.py || fail=1; \
	python3 planning/effect-provider-gate.py --selftest || fail=1; \
	python3 planning/design-divergence-marker-gate.py || fail=1; \
	python3 planning/test-campaign/bin/sidebar-foot-arm.py || fail=1; \
	python3 planning/evidence-citation-gate.py || fail=1; \
	python3 planning/foreign-path-gate.py --quiet || fail=1; \
	python3 planning/target-resolution-gate.py --quiet || fail=1; \
	python3 planning/test-campaign/bin/capture-manifest.py || fail=1; \
	python3 planning/test-campaign/bin/glass-build-gate.py --selftest || fail=1; \
	python3 planning/test-campaign/bin/raster-claim-gate.py || fail=1; \
	python3 planning/mock-exclusion-gate.py || fail=1; \
	python3 planning/mock-exclusion-gate.py --selftest || fail=1; \
	python3 planning/effect-class-vocabulary-gate.py || fail=1; \
	python3 planning/effect-class-vocabulary-gate.py --selftest || fail=1; \
	python3 planning/test-campaign/bin/forced-state-assert.py --control || fail=1; \
	python3 planning/test-campaign/bin/effect-class-census.py --control || fail=1; \
	python3 planning/test-campaign/bin/effect-class-census.py || fail=1; \
	python3 planning/test-campaign/bin/blind-vocabulary-arm.py || fail=1; \
	python3 planning/test-campaign/bin/vocab-differential.py --control || fail=1; \
	python3 planning/test-campaign/bin/vocab-differential.py || fail=1; \
	python3 planning/pin-class-gate.py || fail=1; \
	python3 planning/shipped-brief-gate.py || fail=1; \
	python3 planning/brief-target-gate.py --quiet || fail=1; \
	exit $$fail

## Does the committed glass evidence still depict the build this tree would produce?
##
## `macos-glass` was green for seven days over pictures taken from a build that predates M22,
## because a committed capture recorded everything about itself except WHICH BUILD IT CAME FROM.
## `glass-build-gate.py` binds each artifact to the git blob identity of the Mac app's own build
## inputs -- the set `scripts/acceptance/build-freshness.sh` compiles from -- and goes red when
## that identity is not the one the lane is being read against. Blob ids are line-ending
## normalised, so the verdict is the same on macOS and on Windows.
##
## OUT OF `lint` AND OUT OF `all`, for the same reason `role-intersection` is: it is standing red
## on this tree and the finding is true. Every glass artifact was captured before M22, the
## re-capture needs a macOS host with Xcode and a display server, and wiring a permanent red into
## `all` would mean softening it inside a week. What IS in `lint` is `--selftest`, which watches
## all four arms move: green over a capture stamped with the current tree, red over a stale one,
## red over one no record covers, and red over a row that cannot be shown to predate its own
## manifest. The gate joins `all` when `bin/capture-mac-glass.sh` has re-run on a macOS host and
## its `--emit` has replaced the reconstructed stamps with capture-time ones.
##
## Exit codes: 0 every artifact names the build it depicts and that build is this one, 2 findings.
glass-build:
	@python3 planning/test-campaign/bin/glass-build-gate.py; ec=$$?; \
	echo "glass-build: exit $$ec  (0 current · 2 evidence outlived its build)"; \
	exit 0

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
