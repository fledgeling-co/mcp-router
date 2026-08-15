# MCP Router — Swift build entry point.
#
# CI runs these same targets rather than its own copy of the commands, so the two cannot drift.
# Everything builds unsigned: no developer account is wired up yet, and a build that requires a
# signing identity nobody has is a build nobody can run.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all

APP_DIR    := app
PROJECT    := $(APP_DIR)/MCPRouter.xcodeproj
DERIVED    := $(APP_DIR)/.derived
UNSIGNED   := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

IOS_DEST   ?= generic/platform=iOS Simulator
MAC_DEST   ?= platform=macOS

.PHONY: all tools generate build build-mac build-mac-release build-ios test test-ios parity parity-regen mutation acceptance lint format clean

## Run the whole gate, in the order a failure is cheapest to diagnose.
all: tools lint build test test-ios parity

## Fail loudly and specifically when a required tool is missing, rather than skipping the gate.
## A silently-skipped lint step is worse than no lint step: it reports success.
tools:
	@for t in xcodegen swiftlint swiftformat; do \
	  command -v $$t >/dev/null 2>&1 || { \
	    echo "error: $$t is not installed. brew install $$t"; exit 1; }; \
	done
	@echo "tools: $$(xcodegen --version | tr -d '\n') · swiftlint $$(swiftlint version) · swiftformat $$(swiftformat --version)"

## The Xcode project is generated, never committed — that is what keeps parallel branches from
## conflicting inside project.pbxproj.
generate: tools
	cd $(APP_DIR) && xcodegen generate

build: build-mac build-ios

build-mac: generate
	xcodebuild -project $(PROJECT) -scheme MCPRouter -configuration Debug \
	  -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build

## Proves the release posture is *configured* rather than *required*: hardened runtime and the
## Developer ID identity are set, and the build still completes with signing switched off.
build-mac-release: generate
	xcodebuild -project $(PROJECT) -scheme MCPRouter -configuration Release \
	  -destination '$(MAC_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build

build-ios: generate
	xcodebuild -project $(PROJECT) -scheme MCPRouterIOS -configuration Debug \
	  -destination '$(IOS_DEST)' -derivedDataPath $(DERIVED) $(UNSIGNED) build

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
## The shape of a line is not the signal; whether the listing produced anything is.
##
## Discovery is also not execution, and that is the gap the count below closes: a suite can
## enumerate thirty tests and run none of them, whether disabled or skipped. The gating number is
## therefore read from the xUnit report — an artifact of what actually ran — with skipped
## subtracted, rather than inferred from human-readable output whose format is free to change.
test:
	@set -eu -o pipefail; cd $(APP_DIR); \
	  if ! listing=$$(swift test list 2>&1); then \
	    echo "error: could not enumerate tests — this is a build or toolchain failure, not an empty suite:"; \
	    echo "$$listing"; exit 1; \
	  fi; \
	  discovered=$$(printf '%s\n' "$$listing" | grep -cE '[^[:space:]]' || true); \
	  echo "discovered $$discovered test lines"; \
	  if [ "$$discovered" -eq 0 ]; then \
	    echo "error: the listing was empty — the suite is not running, which is a failure, not a pass"; \
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
test-ios: generate
	@set -eu -o pipefail; \
	  udid=$$(xcrun simctl list devices available -j \
	          | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; \
c=[d for v in ds.values() for d in v if d.get('isAvailable') and 'iPhone' in d['name']]; \
c.sort(key=lambda d: d['state'] != 'Booted'); \
print(c[0]['udid'] if c else '')"); \
	  if [ -z "$$udid" ]; then \
	    echo "error: no available iPhone simulator, so the iOS suite did not run."; \
	    echo "       This is an environment failure, not a pass — the claims it carries"; \
	    echo "       (44pt targets, safe area, the generated Info.plist) went unmeasured."; \
	    exit 2; \
	  fi; \
	  echo "test-ios: simulator $$udid"; \
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

## Launches both shells and asserts each renders a value that came from MCPRouterKit.
##
## Kept out of `all` because it needs things a build does not: a GUI session, an Accessibility
## grant, and a booted simulator. It is not optional though — a linker success is not evidence that
## the shared library reached the screen, which is the whole of A5 and A15.
##
## It distinguishes its outcomes: 1 is a failed assertion, 2 is an environment that could not run
## the check. Collapsing those is how "no Accessibility permission" gets reported as a broken app.
acceptance: build-mac build-mac-release
	./scripts/acceptance/shells.sh
	./scripts/acceptance/control-client.sh
	./scripts/acceptance/p1-auth-routes.sh
	./scripts/acceptance/mac-shell.sh

lint: tools
	@fail=0; \
	swiftformat --lint . --config .swiftformat || fail=1; \
	swiftlint lint --strict --config .swiftlint.yml || fail=1; \
	./scripts/lint/no-raw-design-values.sh || fail=1; \
	./scripts/lint/no-wire-codable.sh || fail=1; \
	exit $$fail

## Writes formatting changes in place. Not part of `all` — a gate that edits your files is a gate
## that can turn a red build green without anyone reading the diff.
format: tools
	swiftformat . --config .swiftformat

clean:
	rm -rf $(DERIVED) $(APP_DIR)/.build $(PROJECT)
