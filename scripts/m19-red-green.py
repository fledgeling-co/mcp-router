#!/usr/bin/env python3
"""M19's red-green pass — one mutation at a time, applied to the IMPLEMENTATION only.

A test that has never failed is not known to work (SWIFT_PRACTICES.md §7). Each arm names the
guard it is supposed to kill; an arm that leaves the suite green is a decoration exposed and is
reported as SURVIVED. The tests themselves are never edited — a mutation that edits a test
proves nothing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ARMS = [
    ("A1", "the fixture carries every block kind the mock draws",
     "app/Sources/MCPRouterKit/Control/Authored/capability-documents/trawl/README.md",
     "|---|---|---|", "|xxx|xxx|xxx|",
     "CapabilityDocumentFixtureTests"),
    ("A2", "no block in any tab falls back to raw text",
     "app/Sources/MCPRouterKit/Markdown/MarkdownParser.swift",
     "guard (1 ... 3).contains(level) else { return nil }",
     "guard (1 ... 0).contains(level) else { return nil }",
     "CapabilityDocumentFixtureTests"),
    ("A3", "a link survives only where the scheme is https",
     "app/Sources/MCPRouterKit/Markdown/MarkdownInline.swift",
     'url.scheme?.lowercased() == "https"', "url.scheme != nil",
     "MarkdownSecurityTests"),
    ("A4", "an image reference may not climb out of the package",
     "app/Sources/MCPRouterKit/Markdown/PackageImageResolver.swift",
     "guard candidateParts.count > baseParts.count,\n              Array(candidateParts.prefix(baseParts.count)) == baseParts\n        else {\n            return .failure(.escapesPackage)\n        }",
     "if false { return .failure(.escapesPackage) }",
     "MarkdownSecurityTests"),
    ("A5", "a parsed shield carries no colour from the badge",
     "app/Sources/MCPRouterKit/Markdown/Shield.swift",
     "return greenNames.contains(lowered) ? .good : .neutral",
     "return lowered.isEmpty ? .good : .neutral",
     "MarkdownSecurityTests"),
    ("A6", "a shield's fill is one of the app's own two text-safe fills",
     "app/Sources/MCPRouterUI/Document/ShieldView.swift",
     "case .good: .shieldGood", "case .good: .live",
     "CapabilityDocumentSheetTests"),
    ("A7", "the panel fabricates no action",
     "app/Sources/MCPRouterUI/Document/CapabilityDocumentSheet.swift",
     'Button("Close") { dismiss?() }', 'Button("Install…") { dismiss?() }',
     "CapabilityDocumentSheetTests"),
    ("A8", "a table's rows are padded and truncated to the header's width",
     "app/Sources/MCPRouterKit/Markdown/MarkdownParser+Tables.swift",
     "while row.count < columns {\n                row.append(MarkdownInline(literal: \"\"))\n            }", "",
     "MarkdownParserTests"),
]

def run(filt):
    r = subprocess.run(["swift", "test", "--filter", filt], cwd=ROOT / "app",
                       capture_output=True, text=True)
    return r.returncode

survived = []
for aid, guard, rel, find, repl, filt in ARMS:
    path = ROOT / rel
    original = path.read_text()
    if find not in original:
        print(f"{aid}  COULD NOT ARM — the text it mutates is not in {rel}")
        survived.append(aid)
        continue
    path.write_text(original.replace(find, repl, 1))
    try:
        code = run(filt)
    finally:
        path.write_text(original)
    if code == 0:
        print(f"{aid}  SURVIVED  — {guard}")
        survived.append(aid)
    else:
        print(f"{aid}  red       — {guard}")

print()
if survived:
    print(f"m19-redgreen: {len(survived)} arm(s) did not bite: {', '.join(survived)}")
    sys.exit(1)
print(f"m19-redgreen: all {len(ARMS)} arms bit, and every file was restored")
