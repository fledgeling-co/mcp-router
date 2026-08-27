#!/usr/bin/env python3
"""Materialise the constructed packages `GET /servers/:name/document` is exercised against.

EVERY SERVER AND EVERY PACKAGE HERE IS CONSTRUCTED. None of the 21 upstreams installed on this
machine declares a package directory, so the route 404s `noPackageDirectory` for all of them and
there is no real package on this host to point the wire at. That is a reach limit rather than a
finding about the route, and it is why the fixture exists: without it the case could only observe
one of the route's five outcomes, and the containment check — the half M30 proved once and the
half this case exists to keep proving — would never be reached at all.

The fixture is kept in the repository and rebuilt into a scratch directory on every run. The
witness lane learned that the hard way: a fixture that lives only in /tmp does not survive a
reboot, and a script that copies it with `2>/dev/null` runs green against an empty home. So every
package below is asserted into place and a missing one is a loud failure.

Layout, with the reason each piece exists:

    <scratch>/home/                     MCP_ROUTER_HOME — servers.json, control.token
    <scratch>/packages/pkg-served/      README + CHANGELOG + CAPABILITIES + one real figure
    <scratch>/packages/pkg-nodocs/      a directory carrying none of the three files
    <scratch>/packages/pkg-toolarge/    a README one byte over documentBytes
    <scratch>/packages/pkg-escape/      a README naming eight references that must not be read
    <scratch>/packages/pkg-escape-evil/ the SIBLING-PREFIX trap: its path has pkg-escape's path
                                        as a STRING prefix and is not inside it
    <scratch>/packages/pkg-budget/      six figures sized to spend the shared image budget exactly
    <scratch>/outside/                  a directory no package contains, holding the secret every
                                        escaping reference is trying to reach
    (pkg-absent is declared in servers.json and deliberately never created)
"""

import json
import os
import shutil
import sys

# The router's own caps, restated here rather than imported, because a fixture that reads its
# sizes from the implementation cannot fail when the implementation changes them. `src/document.ts`
# and `DocumentPackage.swift` both carry these numbers; `wire-document.py` re-reads them off the
# TypeScript source and refuses to run if these three disagree with it.
DOCUMENT_BYTES = 524_288
IMAGE_BYTES = 2_097_152
IMAGE_BUDGET_BYTES = 8_388_608

# A byte string the response must carry back verbatim for the served case to pass, and which
# nothing else in the fixture writes.
SENTINEL = "wire-document sentinel 9f4c1e-served-readme"

# The figure the served package publishes. Eight bytes, so its base64 is short enough to compare
# by eye in the evidence log: QUFBQUFBQUE=
FIGURE_BYTES = b"AAAAAAAA"


def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def write_bytes(path, data):
    with open(path, "wb") as handle:
        handle.write(data)


def seed(scratch):
    """Build the whole fixture under `scratch` and return the servers.json object."""
    if os.path.exists(scratch):
        shutil.rmtree(scratch)
    os.makedirs(scratch)
    # Resolved once, and everything below is built from the resolved spelling. On macOS /tmp is a
    # symlink to /private/tmp, so an unresolved root would be a different string from the one the
    # router reports having read — and the "no filesystem path in the body" assertion compares
    # strings. Comparing the wrong spelling would pass while proving nothing.
    scratch = os.path.realpath(scratch)

    home = os.path.join(scratch, "home")
    packages = os.path.join(scratch, "packages")
    outside = os.path.join(scratch, "outside")
    os.makedirs(home)
    os.makedirs(packages)
    os.makedirs(outside)

    # What every escaping reference is reaching for. If any of them is served, these bytes appear
    # in the response body and the case says so by name rather than by a status code.
    secret = "wire-document ESCAPED-THE-PACKAGE 3b7a20"
    write_bytes(os.path.join(outside, "secret.png"), secret.encode("utf-8"))

    # ---------------------------------------------------------------- pkg-served
    served = os.path.join(packages, "pkg-served")
    os.makedirs(os.path.join(served, "docs"))
    write(
        os.path.join(served, "README.md"),
        "# constructed package\n\n%s\n\n![a figure](docs/figure.png)\n" % SENTINEL,
    )
    write(os.path.join(served, "CHANGELOG.md"), "1.2.0 - constructed changelog line.\n")
    write(os.path.join(served, "CAPABILITIES.md"), "- one constructed capability\n")
    write_bytes(os.path.join(served, "docs", "figure.png"), FIGURE_BYTES)

    # ---------------------------------------------------------------- pkg-nodocs
    os.makedirs(os.path.join(packages, "pkg-nodocs"))
    write(os.path.join(packages, "pkg-nodocs", "NOTES.txt"), "not one of the three\n")

    # ---------------------------------------------------------------- pkg-toolarge
    toolarge = os.path.join(packages, "pkg-toolarge")
    os.makedirs(toolarge)
    write_bytes(os.path.join(toolarge, "README.md"), b"x" * (DOCUMENT_BYTES + 1))

    # ---------------------------------------------------------------- pkg-escape
    #
    # Eight references, each a different way out of the package, and one that is legitimately
    # inside it so the case can tell "everything was refused" from "the refusals are the right
    # ones". The two symlinks are the reason containment is compared after resolving them: a
    # downloaded archive is exactly where a link pointing out of itself comes from.
    escape = os.path.join(packages, "pkg-escape")
    os.makedirs(os.path.join(escape, "docs"))
    write_bytes(os.path.join(escape, "docs", "inside.png"), FIGURE_BYTES)
    os.symlink(os.path.join(outside, "secret.png"), os.path.join(escape, "link-out.png"))
    os.symlink(outside, os.path.join(escape, "linkdir"))

    # The sibling-prefix trap. `<packages>/pkg-escape-evil` has `<packages>/pkg-escape` as a
    # string prefix and is not inside it. A containment check written as `startsWith` serves this;
    # one written on path segments refuses it. Nothing else in the fixture separates those two.
    evil = os.path.join(packages, "pkg-escape-evil")
    os.makedirs(evil)
    write_bytes(os.path.join(evil, "secret.png"), secret.encode("utf-8"))

    write(
        os.path.join(escape, "README.md"),
        "# constructed escape package\n\n"
        "![inside](docs/inside.png)\n\n"
        "![relative out](../outside/secret.png)\n\n"
        "![sibling prefix](../pkg-escape-evil/secret.png)\n\n"
        "![symlinked file](link-out.png)\n\n"
        "![symlinked directory](linkdir/secret.png)\n\n"
        "![deep traversal](../../../../etc/passwd)\n\n"
        "![absolute](/etc/hosts.png)\n\n"
        "![tilde](~/secret.png)\n\n"
        "![remote](https://example.invalid/secret.png)\n\n"
        "![percent encoded](%2e%2e/outside/secret.png)\n",
    )

    # ---------------------------------------------------------------- pkg-budget
    #
    # Sized so the shared budget is spent EXACTLY, and so the oversized figure is first.
    #
    #   oversize.png  IMAGE_BYTES + 1  -> tooLarge, and must spend NOTHING
    #   a..d.png      IMAGE_BYTES each -> 4 x 2 MiB = 8 MiB, exactly IMAGE_BUDGET_BYTES
    #   tail.png      1 KiB            -> budgetExhausted
    #
    # If the oversized figure spent the budget, d.png would come back budgetExhausted instead of
    # sent, and tail.png would still be budgetExhausted — so the discriminator is d.png, not the
    # last one. The case asserts on d.png for that reason.
    budget = os.path.join(packages, "pkg-budget")
    os.makedirs(budget)
    write_bytes(os.path.join(budget, "oversize.png"), b"O" * (IMAGE_BYTES + 1))
    for name in ("a", "b", "c", "d"):
        write_bytes(os.path.join(budget, "%s.png" % name), name.encode() * IMAGE_BYTES)
    write_bytes(os.path.join(budget, "tail.png"), b"T" * 1024)
    write(
        os.path.join(budget, "README.md"),
        "# constructed budget package\n\n"
        "![oversize](oversize.png)\n\n![a](a.png)\n\n![b](b.png)\n\n"
        "![c](c.png)\n\n![d](d.png)\n\n![tail](tail.png)\n",
    )

    # ---------------------------------------------------------------- servers.json
    #
    # Every entry is constructed. `command` is /usr/bin/true because the document route never
    # spawns anything — it reads the declared `cwd` and nothing else — so a server that could not
    # start is the honest fixture for a route that does not start it.
    def entry(cwd):
        server = {"type": "stdio", "command": "/usr/bin/true", "args": []}
        if cwd is not None:
            server["cwd"] = cwd
        return server

    servers = {
        "port": 8981,
        "host": "127.0.0.1",
        "idleMs": 300000,
        "mcpServers": {
            "constructed-served": entry(served),
            "constructed-no-directory": entry(None),
            "constructed-absent-directory": entry(os.path.join(packages, "pkg-absent")),
            "constructed-nodocs": entry(os.path.join(packages, "pkg-nodocs")),
            "constructed-toolarge": entry(toolarge),
            "constructed-escape": entry(escape),
            "constructed-budget": entry(budget),
        },
    }
    write(os.path.join(home, "servers.json"), json.dumps(servers, indent=2) + "\n")

    # Loud assertions. A fixture that half-materialised is the failure mode that reads as a pass.
    expect = [
        os.path.join(home, "servers.json"),
        os.path.join(served, "README.md"),
        os.path.join(served, "docs", "figure.png"),
        os.path.join(toolarge, "README.md"),
        os.path.join(escape, "README.md"),
        os.path.join(escape, "link-out.png"),
        os.path.join(evil, "secret.png"),
        os.path.join(budget, "README.md"),
        os.path.join(outside, "secret.png"),
    ]
    missing = [p for p in expect if not os.path.exists(p)]
    if missing:
        sys.stderr.write("seed.py: these did not land: %s\n" % ", ".join(missing))
        raise SystemExit(1)
    if os.path.exists(os.path.join(packages, "pkg-absent")):
        sys.stderr.write("seed.py: pkg-absent must NOT exist; it is the packageUnreadable case\n")
        raise SystemExit(1)
    if os.path.getsize(os.path.join(toolarge, "README.md")) != DOCUMENT_BYTES + 1:
        sys.stderr.write("seed.py: the oversized README is not one byte over the cap\n")
        raise SystemExit(1)

    return {"scratch": scratch, "home": home, "packages": packages, "outside": outside,
            "secret": secret, "sentinel": SENTINEL}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: seed.py <scratch-dir>\n")
        raise SystemExit(2)
    print(json.dumps(seed(sys.argv[1]), indent=2))
