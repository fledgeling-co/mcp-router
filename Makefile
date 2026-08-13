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
## stops matching its test files exits 0 and the gate says "passed". Counting the enumerated tests
## first turns that into a failure. `swift test list` is used rather than scraping run output
## because its format is stable across toolchain versions.
test:
	@cd $(APP_DIR) && count=$$(swift test list 2>/dev/null | grep -cE '\(\)$$' || true); \
	  echo "discovered $$count tests"; \
	  if [ "$$count" -eq 0 ]; then \
	    echo "error: zero tests discovered — the suite is not running, which is a failure, not a pass"; \
	    exit 1; \
	  fi
	cd $(APP_DIR) && swift test

lint: tools
	swiftformat --lint . --config .swiftformat
	swiftlint lint --strict --config .swiftlint.yml

## Writes formatting changes in place. Not part of `all` — a gate that edits your files is a gate
## that can turn a red build green without anyone reading the diff.
format: tools
	swiftformat . --config .swiftformat

clean:
	rm -rf $(DERIVED) $(APP_DIR)/.build $(PROJECT)
