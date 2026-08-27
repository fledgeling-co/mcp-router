#!/usr/bin/env python3
"""Wire-level cases for `GET /servers/:name/document` — M30's route, over a real socket.

M30 already proves this route in process: `ControlDocumentRouteTests.swift` calls the handler
directly and asserts on the string it returns. That is a different claim from this one. This
script starts a router, lets the kernel carry the bytes, and reads what a client actually
receives — which is the claim the campaign makes of every other route on this lane, and the one
the route did not have.

Seven scenarios, each a distinct outcome of the route:

    served       200 and the content, with NO filesystem path anywhere in the body
    no-directory 404 noPackageDirectory   — the server declares no package at all
    absent       404 packageUnreadable    — it declares one that is not there
    nodocs       404 noDocuments          — the directory is there and publishes none of the three
    toolarge     413 documentTooLarge     — and it names WHICH cap, with the limit and the actual
    escape       200, and every reference out of the package refused, by name
    budget       200, and an oversized image refused WITHOUT spending the shared budget

Run against both implementations. `src/document.ts` is the reference and `DocumentPackage.swift`
is the port, they are diffed by the parity lane, and a wire case that observed only one of them
would leave the shipped router — the Swift one — unobserved.

Exit 0 when every scenario passes on every implementation it was asked to run, 1 on any failure,
2 on a setup problem (a port already held, a binary missing, the caps having drifted).
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "wire-document-fixture"))
import seed as fixture  # noqa: E402  — the sys.path line above has to come first

PORT = 8981
SCRATCH = "/tmp/g19-wire-scratch"
OUT = os.path.join(REPO, "planning", "test-campaign", "evidence", "wire-document")

DOCUMENT_BYTES = 524_288
IMAGE_BYTES = 2_097_152
IMAGE_BUDGET_BYTES = 8_388_608


def caps_still_agree():
    """Refuse to run if the implementation's caps have moved away from the fixture's.

    A fixture sized one byte over a cap that has since changed is a fixture sized comfortably
    under it, and every size case would pass by not reaching the boundary at all.
    """
    text = open(os.path.join(REPO, "src", "document.ts"), encoding="utf-8").read()
    found = {}
    for name in ("documentBytes", "imageBytes", "imageBudgetBytes"):
        m = re.search(name + r":\s*([0-9_]+)", text)
        if not m:
            return "src/document.ts no longer declares %s" % name
        found[name] = int(m.group(1).replace("_", ""))
    want = {"documentBytes": DOCUMENT_BYTES, "imageBytes": IMAGE_BYTES,
            "imageBudgetBytes": IMAGE_BUDGET_BYTES}
    if found != want:
        return "caps drifted: src/document.ts says %s, this fixture is built for %s" % (found, want)
    return None


def port_free(port):
    """Whether a router could BIND here — not whether something answers a connect.

    Measured 27 Aug 2026: a connect-based check reported the port free while the previous
    implementation's socket was still in TIME_WAIT, and the next router died on EADDRINUSE
    with the pre-check having said the coast was clear. The routers bind without
    SO_REUSEADDR, so the honest probe is the same bind they perform.
    """
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def port_listening(port):
    s = socket.socket()
    try:
        s.connect(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def wait_for_port(port, deadline):
    while time.time() < deadline:
        if port_listening(port):
            return True
        time.sleep(0.1)
    return False


def wait_until_free(port, deadline):
    while time.time() < deadline:
        if port_free(port):
            return True
        time.sleep(0.2)
    return False


def get(path):
    """One GET, returning (status, raw body text). A refusal is a response, not an exception."""
    url = "http://127.0.0.1:%d%s" % (PORT, path)
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")


class Checks:
    """One scenario's assertions, each recorded whether it passed or failed.

    Recorded rather than raised: a scenario that stops at its first failure hides how much else
    is wrong, and the evidence file is more useful when it carries every assertion that ran.
    """

    def __init__(self, name):
        self.name = name
        self.rows = []

    def ok(self, label, condition, detail=""):
        self.rows.append({"assert": label, "pass": bool(condition), "detail": detail})
        return bool(condition)

    def eq(self, label, actual, expected):
        return self.ok(label, actual == expected, "expected %r, got %r" % (expected, actual))

    @property
    def passed(self):
        return all(r["pass"] for r in self.rows)

    def failures(self):
        return [r for r in self.rows if not r["pass"]]


def refusal_map(body):
    return dict((r["reference"], r["reason"]) for r in body.get("refusedImages", []))


def scenario_served(paths, log):
    c = Checks("served")
    status, raw = get("/servers/constructed-served/document")
    body = json.loads(raw)
    c.eq("status is 200", status, 200)
    c.ok("readMe carries the sentinel", fixture.SENTINEL in body.get("documents", {}).get("readMe", ""))
    c.ok("changelog is present", "changelog" in body.get("documents", {}))
    c.ok("capabilities is present", "capabilities" in body.get("documents", {}))
    images = body.get("images", [])
    c.eq("one image travelled", len(images), 1)
    if images:
        c.eq("the reference is as the document spelled it", images[0]["reference"], "docs/figure.png")
        c.eq("media type", images[0]["media"], "image/png")
        c.eq("the bytes are the file's own", base64.b64decode(images[0]["base64"]), fixture.FIGURE_BYTES)
    c.eq("nothing was refused", body.get("refusedImages"), [])
    # M30's own assertion, moved to the wire: the app may not open a file, so a payload carrying a
    # path is a payload that invites one. `ControlDocumentRouteTests.swift:104` asserts this in
    # process; this asserts it on what the socket delivered.
    root = paths["served_root"]
    c.ok("the package root appears NOWHERE in the body", root not in raw,
         "root=%s" % root)
    c.ok("no absolute path of any shape appears in the body",
         not re.search(r'"(/private/tmp|/Users|/tmp)[^"]*"', raw))
    log(c, raw)
    return c


def scenario_refusal(server, want_status, want_reason, log, extra=None):
    c = Checks(want_reason)
    status, raw = get("/servers/%s/document" % server)
    body = json.loads(raw)
    c.eq("status", status, want_status)
    c.eq("names its own rule", body.get("reason"), want_reason)
    c.ok("carries a human sentence", bool(body.get("error")))
    if extra:
        extra(c, body, raw)
    log(c, raw)
    return c


def toolarge_extra(c, body, raw):
    # The refusal has to say WHICH of the three caps it hit. "too large" without a cap name tells
    # a reader nothing they can act on, and there are three caps that can produce one.
    c.eq("names the cap it hit", body.get("cap"), "documentBytes")
    c.eq("names the limit", body.get("limit"), DOCUMENT_BYTES)
    c.eq("names the actual size", body.get("actual"), DOCUMENT_BYTES + 1)
    c.eq("names the file", body.get("file"), "README.md")


def scenario_escape(paths, log):
    c = Checks("escape")
    status, raw = get("/servers/constructed-escape/document")
    body = json.loads(raw)
    c.eq("status is 200", status, 200)

    # The strongest oracle here is not the reason codes — it is the bytes. If anything escaped,
    # the secret is in the response and no status code hides it.
    c.ok("the out-of-package secret is NOT in the body", paths["secret"] not in raw)
    c.ok("the package root is NOT in the body", paths["escape_root"] not in raw)

    images = body.get("images", [])
    c.eq("exactly one image travelled", len(images), 1)
    if images:
        c.eq("and it is the one inside the package", images[0]["reference"], "docs/inside.png")

    want = {
        "../outside/secret.png": "escapesPackage",
        "../pkg-escape-evil/secret.png": "escapesPackage",
        "link-out.png": "escapesPackage",
        "linkdir/secret.png": "escapesPackage",
        "../../../../etc/passwd": "escapesPackage",
        "/etc/hosts.png": "absolutePath",
        "~/secret.png": "absolutePath",
        "https://example.invalid/secret.png": "remote",
        "%2e%2e/outside/secret.png": "notInPackage",
    }
    got = refusal_map(body)
    for ref, reason in want.items():
        c.eq("%s -> %s" % (ref, reason), got.get(ref), reason)
    c.eq("nine references refused and no more", len(got), len(want))
    log(c, raw)
    return c


def scenario_budget(log):
    c = Checks("budget")
    status, raw = get("/servers/constructed-budget/document")
    body = json.loads(raw)
    c.eq("status is 200", status, 200)
    got = refusal_map(body)
    sent = dict((i["reference"], len(base64.b64decode(i["base64"]))) for i in body.get("images", []))

    c.eq("the oversized figure is refused on its own terms", got.get("oversize.png"), "tooLarge")
    over = [r for r in body.get("refusedImages", []) if r["reference"] == "oversize.png"]
    if over:
        c.eq("and names the per-image limit", over[0].get("limit"), IMAGE_BYTES)

    # THE DISCRIMINATOR. a..d are 2 MiB each and spend the 8 MiB budget exactly. d.png travels
    # only if the oversized figure spent nothing; if it had spent its 2 MiB + 1, d would come back
    # budgetExhausted. tail.png is budgetExhausted either way, so it proves nothing on its own.
    for name in ("a", "b", "c", "d"):
        c.eq("%s.png travelled" % name, sent.get("%s.png" % name), IMAGE_BYTES)
    c.ok("d.png is not a refusal — the oversized figure spent NO budget",
         "d.png" not in got, "refusals=%s" % sorted(got))
    c.eq("tail.png is refused once the budget is spent", got.get("tail.png"), "budgetExhausted")
    c.eq("the budget was spent exactly", sum(sent.values()), IMAGE_BUDGET_BYTES)
    log(c, raw)
    return c


def run_against(impl, cmd, paths, logf):
    """Start one router, run all seven scenarios against it, stop it."""
    env = dict(os.environ)
    env["MCP_ROUTER_HOME"] = paths["home"]
    # Up to 30s, because the wait is for the previous implementation's socket to leave TIME_WAIT
    # rather than for anything of ours. A port still held after that is somebody else's, and a
    # router found there would not be ours.
    if not wait_until_free(PORT, time.time() + 30):
        raise SystemExit("port %d is still held; a router found there would not be ours" % PORT)

    proc = subprocess.Popen(cmd, env=env, stdout=logf, stderr=subprocess.STDOUT, cwd=REPO)
    try:
        if not wait_for_port(PORT, time.time() + 30):
            raise SystemExit("%s never listened on 127.0.0.1:%d" % (impl, PORT))
        results = []
        entries = []

        def log(c, raw):
            entries.append({"scenario": c.name, "pass": c.passed, "bodyBytes": len(raw),
                            "bodySha256": hashlib.sha256(raw.encode()).hexdigest(),
                            "asserts": c.rows})

        results.append(scenario_served(paths, log))
        results.append(scenario_refusal("constructed-no-directory", 404, "noPackageDirectory", log))
        results.append(scenario_refusal("constructed-absent-directory", 404, "packageUnreadable", log))
        results.append(scenario_refusal("constructed-nodocs", 404, "noDocuments", log))
        results.append(scenario_refusal("constructed-toolarge", 413, "documentTooLarge", log,
                                        extra=toolarge_extra))
        results.append(scenario_escape(paths, log))
        results.append(scenario_budget(log))
        return results, entries
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        # The port must be back before the next implementation starts, or its router binds nothing
        # and every scenario silently talks to the previous one.
        wait_until_free(PORT, time.time() + 30)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv):
    drift = caps_still_agree()
    if drift:
        sys.stderr.write("wire-document.py: %s\n" % drift)
        return 2

    want = argv[1:] or ["node", "swift"]
    paths = fixture.seed(SCRATCH)
    packages = paths["packages"]
    paths["served_root"] = os.path.join(packages, "pkg-served")
    paths["escape_root"] = os.path.join(packages, "pkg-escape")

    os.makedirs(OUT, exist_ok=True)
    record = {"recordedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "port": PORT, "scratch": paths["scratch"],
              "constructed": True,
              "constructedNote": ("Every server exercised here is constructed. None of the 21 "
                                  "upstreams installed on this machine declares a package "
                                  "directory, so the route 404s noPackageDirectory for all of "
                                  "them and no real package on this host can reach the other six "
                                  "outcomes."),
              "implementations": {}}

    binaries = {
        "node": [os.path.join(REPO, "dist", "index.js")],
        "swift": [os.path.join(REPO, "app", ".build", "debug", "MCPRouterCLI")],
    }
    commands = {
        "node": ["node", os.path.join(REPO, "dist", "index.js"), "serve", "--port", str(PORT)],
        "swift": [os.path.join(REPO, "app", ".build", "debug", "MCPRouterCLI"),
                  "serve", "--port", str(PORT)],
    }

    failed = 0
    with open(os.path.join(OUT, "wire-document.log"), "w", encoding="utf-8") as logf:
        for impl in want:
            binary = binaries[impl][0]
            if not os.path.exists(binary):
                sys.stderr.write("wire-document.py: %s is not built at %s\n" % (impl, binary))
                return 2
            logf.write("\n===== %s =====\n" % impl)
            logf.flush()
            results, entries = run_against(impl, commands[impl], paths, logf)
            record["implementations"][impl] = {
                "binary": binary, "sha256": sha256_of(binary),
                "scenarios": entries,
                "passed": sum(1 for r in results if r.passed),
                "total": len(results),
            }
            for r in results:
                mark = "PASS" if r.passed else "FAIL"
                print("%-6s %-18s %s" % (impl, r.name, mark))
                for f in r.failures():
                    failed += 1
                    print("         %s  %s" % (f["assert"], f["detail"]))

    with open(os.path.join(OUT, "wire-document.json"), "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2)
        f.write("\n")

    print("\nfailures: %d" % failed)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
