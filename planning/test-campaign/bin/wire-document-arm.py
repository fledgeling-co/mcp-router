#!/usr/bin/env python3
"""Arm the wire-document cases: plant a fault, watch the case go RED, put the source back.

A case that has never been seen to fail is a case nobody has any reason to believe. Each arm
below removes exactly one property the case claims to hold, rebuilds the implementation, runs the
scenarios again, and requires exactly the scenarios it declares to fail — `scenario` plus any `alsoRed`. An arm
that reddens a scenario it did not declare, or leaves a declared one green, is recorded as a
failed arm: the first means the case is sensitive to something other than what it names, and
the second means it is not sensitive to what it does.

`alsoRed` exists because a property can be asserted by more than one scenario on purpose. The
response carrying no filesystem path is asserted by `served` and again by `escape`, so a
planted leak that reddened only one of them would be the finding, not the pass.

Restoration is by `git checkout` of the one file, and the sha256 before and after must match. A
restore that "looked fine" is how a campaign leaves a planted fault in the tree.

The containment arms are three rather than one, because containment can be wrong in three ways
that a single fault does not separate:

    contained-always   the check removed outright
    contained-prefix   compared as a STRING prefix, so a sibling package whose path begins with
                       the package's path is served — `<pkgs>/pkg-escape-evil` against
                       `<pkgs>/pkg-escape`
    contained-nolinks  compared before resolving symlinks, so a link out of the package is served

M30 armed its own containment check with three planted divergences and a verifier attacked it with
twenty-three adversarial references. That evidence is real and it is in M30's record. This exists
so the property is checked on a schedule rather than once.

    wire-document-arm.py             every arm
    wire-document-arm.py contained-prefix leaks-the-path   named arms only
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "planning", "test-campaign", "evidence", "wire-document")
RUNNER = os.path.join(HERE, "wire-document.py")

TS = os.path.join(REPO, "src", "document.ts")
SWIFT = os.path.join(REPO, "app", "Sources", "RouterCore", "Control", "DocumentPackage.swift")
SWIFT_ROUTE = os.path.join(REPO, "app", "Sources", "RouterCore", "Control", "ControlDocument.swift")

# Each arm: which file it edits, which implementation it rebuilds, the exact substring it
# replaces, what it replaces it with, and which scenario must go red.
ARMS = [
    {
        "id": "contained-always",
        "file": TS, "impl": "node", "scenario": "escape",
        "why": "the containment check removed outright",
        "old": """  const contained =
    candidateParts.length > baseParts.length &&
    baseParts.every((part, index) => candidateParts[index] === part);""",
        "new": """  const contained = true;""",
    },
    {
        "id": "contained-prefix",
        "file": TS, "impl": "node", "scenario": "escape",
        "why": "containment compared as a string prefix rather than on path segments",
        "old": """  const contained =
    candidateParts.length > baseParts.length &&
    baseParts.every((part, index) => candidateParts[index] === part);""",
        "new": """  const contained = candidate.startsWith(base);""",
    },
    {
        "id": "contained-nolinks",
        "file": TS, "impl": "node", "scenario": "escape",
        "why": "containment compared before symlinks are resolved",
        "old": """function realPathOrResolved(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
}""",
        "new": """function realPathOrResolved(path: string): string {
  return resolve(path);
}""",
    },
    {
        "id": "leaks-the-path",
        "file": TS, "impl": "node", "scenario": "served",
        "why": ("the response carries the filesystem path it read from, under the key the app "
                "reads as a reference. The first spelling of this arm ADDED a `path` field and "
                "tsc refused it: `images` is typed `Array<{reference; media; base64}>` and an "
                "object literal carrying an extra property is an excess-property error. So the "
                "type already forbids the leak by addition and says nothing about the leak by "
                "substitution — which is the one the wire assertion is here to catch."),
        "alsoRed": ["escape"],
        "old": """      media: IMAGE_MEDIA_TYPES[extname(entry.path).toLowerCase()]!,""",
        "new": """      media: entry.path,""",
    },
    {
        "id": "nodocs-served-anyway",
        "file": TS, "impl": "node", "scenario": "noDocuments",
        "why": ("a package publishing none of the three documents is answered with a body rather "
                "than refused. The panel would then draw three empty tabs over a package that "
                "published nothing, which is the failure `noDocuments` exists to prevent."),
        "old": """  if (!documents.length) {
    return {
      status: 404,
      error: 'the package carries no read me, changelog or capability list',
      reason: 'noDocuments',
    };
  }""",
        "new": """""",
    },
    {
        "id": "unnamed-refusal",
        "file": TS, "impl": "node", "scenario": "packageUnreadable",
        "why": ("a refusal stops naming the rule it hit and answers a generic `notFound`. Three "
                "different things produce a 404 on this route and the app maps each to different "
                "copy, so a shared reason code is a refusal the reader cannot act on."),
        "old": """      reason: 'packageUnreadable',""",
        "new": """      reason: 'notFound',""",
    },
    {
        "id": "unnamed-cap",
        "file": TS, "impl": "node", "scenario": "documentTooLarge",
        "why": "the size refusal no longer names which of the three caps it hit",
        "old": """        cap: 'documentBytes',""",
        "new": """        cap: 'markdownLimits',""",
    },
    {
        "id": "oversize-spends-budget",
        "file": TS, "impl": "node", "scenario": "budget",
        "why": "an oversized image spends the shared budget instead of being refused on its own terms",
        "old": """    if (size > DOCUMENT_CAPS.imageBytes) return 'tooLarge';
    if (spent + size > DOCUMENT_CAPS.imageBudgetBytes) return 'budgetExhausted';
    spent += size;
    return 'send';""",
        "new": """    if (size > DOCUMENT_CAPS.imageBytes) {
      spent += size;
      return 'tooLarge';
    }
    if (spent + size > DOCUMENT_CAPS.imageBudgetBytes) return 'budgetExhausted';
    spent += size;
    return 'send';""",
    },
    {
        "id": "swift-contained-always",
        "file": SWIFT, "impl": "swift", "scenario": "escape",
        "why": "the SHIPPED router's containment check removed outright",
        "old": """        guard candidateParts.count > baseParts.count,
              Array(candidateParts.prefix(baseParts.count)) == baseParts
        else {
            return .refused(.escapesPackage)
        }""",
        "new": """        guard candidateParts.count > 0 else {
            return .refused(.escapesPackage)
        }""",
    },
    {
        "id": "swift-leaks-the-path",
        "file": SWIFT_ROUTE, "impl": "swift", "scenario": "served",
        "why": ("the SHIPPED router's response carries the package root it read from. Planted on "
                "the response object rather than on a reference, because `ReadableImage` carries "
                "no path to substitute — the Swift half cannot leak one the way the TypeScript "
                "half can, and the arm plants the leak this side can actually have."),
        "alsoRed": ["escape"],
        "old": """            JSONMember(key: "server", value: .string(name)),""",
        "new": """            JSONMember(key: "server", value: .string(name)),
            JSONMember(key: "root", value: .string(JSString(root))),""",
    },
    {
        "id": "swift-contained-nolinks",
        "file": SWIFT, "impl": "swift", "scenario": "escape",
        "why": "the SHIPPED router compares containment before resolving symlinks",
        "old": """        let base = URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(trimmed)
            .standardizedFileURL.resolvingSymlinksInPath()""",
        "new": """        let base = URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL
        let candidate = base.appendingPathComponent(trimmed)
            .standardizedFileURL""",
    },
]

BUILD = {
    "node": ["npx", "tsc", "-p", "tsconfig.json"],
    "swift": ["swift", "build", "--product", "MCPRouterCLI"],
}
BUILD_CWD = {"node": REPO, "swift": os.path.join(REPO, "app")}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build(impl, log):
    r = subprocess.run(BUILD[impl], cwd=BUILD_CWD[impl], stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=900)
    log.write(r.stdout.decode("utf-8", "replace"))
    return r.returncode


def scenarios_of(impl, log):
    """Run the wire cases against one implementation and return {scenario: passed}."""
    r = subprocess.run([sys.executable, RUNNER, impl], cwd=REPO, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, timeout=900)
    text = r.stdout.decode("utf-8", "replace")
    log.write(text)
    record = json.load(open(os.path.join(OUT, "wire-document.json")))
    entry = record["implementations"].get(impl)
    if not entry:
        return None
    return dict((s["scenario"], s["pass"]) for s in entry["scenarios"])


def restore(path, log):
    subprocess.run(["git", "checkout", "--", path], cwd=REPO, check=True, timeout=120)


def main(argv):
    wanted = set(argv[1:])
    arms = [a for a in ARMS if not wanted or a["id"] in wanted]
    if not arms:
        sys.stderr.write("no arm matched %s\n" % sorted(wanted))
        return 2

    os.makedirs(OUT, exist_ok=True)
    results = []
    ok = True
    with open(os.path.join(OUT, "arming.log"), "a", encoding="utf-8") as log:
        log.write("\n\n########## arming pass %s ##########\n"
                  % time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        for arm in arms:
            path = arm["file"]
            before = sha256_of(path)
            log.write("\n===== arm %s (%s) =====\nfile:   %s\nsha256 before: %s\n"
                      % (arm["id"], arm["why"], path, before))
            source = open(path, encoding="utf-8").read()
            if arm["old"] not in source:
                log.write("SKIPPED: the text this arm replaces is not in the file any more.\n")
                results.append({"arm": arm["id"], "verdict": "stale",
                                "detail": "the planted text no longer matches the source"})
                ok = False
                continue

            open(path, "w", encoding="utf-8").write(source.replace(arm["old"], arm["new"], 1))
            planted = sha256_of(path)
            log.write("sha256 planted: %s\n" % planted)
            try:
                rc = build(arm["impl"], log)
                if rc != 0:
                    verdict = "build-failed"
                    detail = "the planted source did not compile (rc=%d)" % rc
                    red = None
                else:
                    outcome = scenarios_of(arm["impl"], log)
                    want_red = set([arm["scenario"]]) | set(arm.get("alsoRed", ()))
                    got_red = set(k for k, v in (outcome or {}).items() if not v)
                    if not outcome:
                        verdict, detail = "no-outcome", "the runner recorded no scenarios"
                    elif got_red == want_red:
                        verdict = "red"
                        detail = "red exactly where declared: %s" % ", ".join(sorted(want_red))
                    elif arm["scenario"] in got_red:
                        verdict = "red-but-noisy"
                        detail = "declared %s, red %s" % (sorted(want_red), sorted(got_red))
                    else:
                        verdict = "STILL-GREEN"
                        detail = "%s passed with the fault planted — the case does not bite" % arm["scenario"]
            finally:
                restore(path, log)
                after = sha256_of(path)
                log.write("sha256 after restore: %s  (%s)\n"
                          % (after, "IDENTICAL" if after == before else "DIFFERS"))
                rebuild = build(arm["impl"], log)
                log.write("rebuild after restore rc=%d\n" % rebuild)

            if after != before:
                verdict, detail = "NOT-RESTORED", "sha256 %s != %s" % (after, before)
            if verdict != "red":
                ok = False
            log.write("VERDICT: %s — %s\n" % (verdict, detail))
            print("%-26s %-14s %s" % (arm["id"], verdict, detail))
            results.append({"arm": arm["id"], "impl": arm["impl"], "file":
                            os.path.relpath(path, REPO), "why": arm["why"],
                            "scenarioExpectedRed": ", ".join(sorted(set([arm["scenario"]]) | set(arm.get("alsoRed", ())))), "verdict": verdict,
                            "detail": detail, "sha256Before": before, "sha256Planted": planted,
                            "sha256AfterRestore": after, "restored": after == before})

    path = os.path.join(OUT, "arming.json")
    prior = []
    if os.path.exists(path):
        prior = json.load(open(path)).get("arms", [])
    keep = [a for a in prior if a["arm"] not in set(r["arm"] for r in results)]
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"recordedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   "arms": keep + results}, f, indent=2)
        f.write("\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
