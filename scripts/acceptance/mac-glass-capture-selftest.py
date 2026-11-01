#!/usr/bin/env python3
"""Check capture subject ordering and portable paths without launching an app."""

import os
from pathlib import Path
import runpy
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CAPTURE = ROOT / "planning/test-campaign/bin/capture-mac-glass.sh"
GATE = ROOT / "planning/test-campaign/bin/glass-build-gate.py"


def provenance_has_subject(text):
    scenario = None
    for line in text.splitlines():
        if line.startswith("relaunch_and_capture "):
            scenario = line.split()[1]
        if line.startswith('if "$AXKIT" press "$PID" "Read first"'):
            return scenario == "cleanupSkills"
    return False


def config(script, env):
    result = subprocess.run(
        ["/bin/bash", str(script), "--print-config"],
        env=env, check=True, capture_output=True, text=True,
    )
    return dict(line.split("=", 1) for line in result.stdout.splitlines())


def main():
    source = CAPTURE.read_text()
    assert provenance_has_subject(source), "Read first is not on cleanupSkills"
    mutant = source.replace(
        'if "$AXKIT" press "$PID" "Read first"',
        'relaunch_and_capture offline SURF-026.failure SURF-026 Insights\n'
        'if "$AXKIT" press "$PID" "Read first"',
    )
    assert not provenance_has_subject(mutant), "ordering control did not reject Insights"

    env = {key: value for key, value in os.environ.items()
           if not key.startswith("MCP_ROUTER_GLASS_")}
    with tempfile.TemporaryDirectory(prefix="router glass paths ") as tmp:
        root = Path(tmp) / "relocated checkout"
        script = root / "planning/test-campaign/bin/capture-mac-glass.sh"
        script.parent.mkdir(parents=True)
        shutil.copyfile(CAPTURE, script)
        defaults = config(script, env)
        assert defaults["ROOT"] == str(root)
        assert defaults["CAMPAIGN"] == str(root / "planning/test-campaign")
        assert defaults["AXKIT"] == str(root / "planning/test-campaign/bin/axkit")
        assert defaults["GLASS_BUILD_GATE"] == str(root / "planning/test-campaign/bin/glass-build-gate.py")
        assert defaults["MAC_APP"] == str(root / "app/.derived/Build/Products/Debug/MCPRouter.app")
        isolated = {
            "MCP_ROUTER_GLASS_REPO_ROOT": str(root),
            "MCP_ROUTER_GLASS_CAMPAIGN": str(Path(tmp) / "private evidence"),
            "MCP_ROUTER_GLASS_APP": str(Path(tmp) / "unique subject.app"),
            "MCP_ROUTER_GLASS_AXKIT": str(Path(tmp) / "private axkit"),
        }
        selected = config(script, {**env, **isolated})
        assert selected["GLASS_BUILD_GATE"] == defaults["GLASS_BUILD_GATE"]
        for key, value in isolated.items():
            target = {"REPO_ROOT": "ROOT", "CAMPAIGN": "CAMPAIGN",
                      "APP": "MAC_APP", "AXKIT": "AXKIT"}[key.removeprefix("MCP_ROUTER_GLASS_")]
            assert selected[target] == value
        prior = os.environ.copy()
        try:
            os.environ.update(isolated)
            gate = runpy.run_path(str(GATE), run_name="glass_path_control")
            oracle = runpy.run_path(str(GATE.with_name("glass-assert.py")), run_name="glass_oracle_path_control")
        finally:
            os.environ.clear()
            os.environ.update(prior)
        assert gate["ROOT"] == root.resolve()
        assert gate["CAMPAIGN"] == Path(isolated["MCP_ROUTER_GLASS_CAMPAIGN"]).resolve()
        assert gate["RECORD"].parent == gate["CAMPAIGN"] / "evidence/ax"
        assert oracle["D"] == gate["CAMPAIGN"]

        # Observe the real shell's launch arguments, stopping before any app or capture runs.
        helper = root / "scripts/acceptance/mac-app.sh"
        helper.parent.mkdir(parents=True)
        helper.write_text('mac_app_launch() { printf "%s\\n" "$@" > "$PROBE_ARGS"; exit 77; }\n')
        toolkit = Path(isolated["MCP_ROUTER_GLASS_AXKIT"])
        toolkit.write_text('#!/bin/bash\nprintf "Background witness\\n"\n')
        toolkit.chmod(0o700)
        Path(isolated["MCP_ROUTER_GLASS_APP"]).mkdir()
        args = Path(tmp) / "launch arguments.txt"
        launch_env = {**env, **isolated, "PROBE_ARGS": str(args),
                      "MCP_ROUTER_HOME": str(Path(tmp) / "isolated router"),
                      "MCP_ROUTER_URL": "http://127.0.0.1:18971"}
        probe = subprocess.run(["/bin/bash", str(script)], env=launch_env,
                               capture_output=True, text=True)
        assert probe.returncode == 77, probe.stderr
        assert args.read_text().splitlines() == [
            isolated["MCP_ROUTER_GLASS_APP"], isolated["MCP_ROUTER_GLASS_AXKIT"],
            "MCPROUTER_SCENARIO=populated",
            "MCP_ROUTER_HOME=" + launch_env["MCP_ROUTER_HOME"],
            "MCP_ROUTER_URL=" + launch_env["MCP_ROUTER_URL"],
        ]
        for changes in [
            {"MCP_ROUTER_HOME": ""},
            {"MCP_ROUTER_URL": "http://192.0.2.1:8879"},
            {"MCP_ROUTER_URL": "http://127.0.0.1"},
        ]:
            probe = subprocess.run(["/bin/bash", str(script)],
                                   env={**launch_env, "MCP_ROUTER_GLASS_INBOX_SCENARIO": "live", **changes},
                                   capture_output=True, text=True)
            assert probe.returncode == 2, probe.stdout + probe.stderr
        probe = subprocess.run(["/bin/bash", str(script)],
                               env={**launch_env, "MCP_ROUTER_GLASS_INBOX_SCENARIO": "live"},
                               capture_output=True, text=True)
        assert probe.returncode == 77, probe.stdout + probe.stderr

        # The app's display name is deliberately different: only its PID can guard the shutter.
        toolkit.write_text('''#!/bin/bash
case "$1" in
  front) printf 'Renamed capture subject\\n' ;;
  front-pid) printf '%s\\n' "$PROBE_FRONT_PID" ;;
  title) printf 'Checks\\n' ;;
  frame) printf '10,20,900,450\\n' ;;
esac
''')
        bin_dir = Path(tmp) / "mock capture commands"
        bin_dir.mkdir()
        shutter = bin_dir / "screencapture"
        shutter.write_text('#!/bin/bash\nprintf "\\211PNG\\r\\n\\032\\nfixture" > "${@: -1}"\n')
        shutter.chmod(0o700)
        shots = Path(tmp) / "shutter controls"
        shots.mkdir()
        function = source[source.index("capture() {"):source.index("\nSHELL_SHARE_REASON=")]
        capture_probe = Path(tmp) / "capture guard.sh"
        variables = {"AXKIT": toolkit, "MAC_APP": isolated["MCP_ROUTER_GLASS_APP"],
                     "SHOTS": shots, "WINID": "42", "PID": "123"}
        capture_probe.write_text("#!/bin/bash\nset -euo pipefail\n" +
                                 "".join(f"{key}={shlex.quote(str(value))}\n"
                                         for key, value in variables.items()) +
                                 function + "\ncapture probe SURF-CONTROL READBACK\n")
        for front, expected_status in [("123", 1), ("999", 0), ("unknown", 1)]:
            image = shots / "probe.png"
            image.unlink(missing_ok=True)
            probe = subprocess.run(["/bin/bash", str(capture_probe)],
                                   env={**env, "PATH": str(bin_dir) + ":" + env["PATH"],
                                        "PROBE_FRONT_PID": front},
                                   capture_output=True, text=True)
            assert probe.returncode == expected_status, probe.stdout + probe.stderr
            assert image.exists() == (expected_status == 0)
    print("mac glass capture: subject ordering, portable paths, isolated live Inbox launch and renamed target PID shutter controls passed")


if __name__ == "__main__":
    main()
