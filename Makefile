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

.PHONY: all tools generate build build-mac build-mac-release build-ios test lint format clean

## Run the whole gate, in the order a failure is cheapest to diagnose.
all: tools lint build test

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
## three narrower holes the obvious version of it leaves open.
##
## A listing that *fails* must not read as a suite with no tests: the two want opposite responses,
## and discarding stderr turns a compile error into "zero tests discovered", pointing whoever reads
## it at the wrong problem. So the listing's status is checked on its own, with its diagnostics kept.
##
## Discovery is also not execution. A suite whose tests are all disabled discovers many and runs
## none, which is the same silent pass by a different route — so the count that decides the gate is
## read from the xUnit report `swift test` writes, which is a machine-readable artifact of what
## actually ran rather than a scrape of human-readable output whose format is free to change.
test:
	@set -eu -o pipefail; cd $(APP_DIR); \
	  if ! listing=$$(swift test list 2>&1); then \
	    echo "error: could not enumerate tests — this is a build or toolchain failure, not an empty suite:"; \
	    echo "$$listing"; exit 1; \
	  fi; \
	  discovered=$$(printf '%s\n' "$$listing" | grep -cE '\(\)$$' || true); \
	  echo "discovered $$discovered tests"; \
	  if [ "$$discovered" -eq 0 ]; then \
	    echo "error: zero tests discovered — the suite is not running, which is a failure, not a pass"; \
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
	         | sed -n 's/.*<testsuite [^>]*tests="\([0-9]*\)".*/\1/p' \
	         | awk '{ total += $$1 } END { print total + 0 }'); \
	  echo "executed $$ran tests"; \
	  if [ "$$ran" -eq 0 ]; then \
	    echo "error: zero tests executed — a suite can discover tests and run none of them"; \
	    exit 1; \
	  fi

lint: tools
	swiftformat --lint . --config .swiftformat
	swiftlint lint --strict --config .swiftlint.yml

## Writes formatting changes in place. Not part of `all` — a gate that edits your files is a gate
## that can turn a red build green without anyone reading the diff.
format: tools
	swiftformat . --config .swiftformat

clean:
	rm -rf $(DERIVED) $(APP_DIR)/.build $(PROJECT)
