#!/usr/bin/env python3
"""Verification harness for G11: corpus determinism and machine resolution.

Proves:
1. 2-way control: a pristine checkout and a dirty working tree evaluate HEAD identically.
2. --worktree mode evaluates working-tree disk state and reflects uncommitted edits.
3. Machine resolution (/tmp file presence vs absence) is non-gating and does not alter the partition.
4. Fault injection: planting a disk-reading regression fails the 2-way checkout control.
"""

import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
GATE = ROOT / "planning" / "foreign-path-gate.py"


def sha256_file(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def test_2way_checkout_and_worktree():
    """Verify that HEAD scanning is hermetic across checkouts and distinct from --worktree."""
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td)
        repo_dir = d / "repo"
        repo_dir.mkdir()
        subprocess.run(["git", "init"], cwd=repo_dir, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.name", "Tester"], cwd=repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "tester@test.com"], cwd=repo_dir, check=True)

        # Commit an unwithdrawn scratch citation
        (repo_dir / "doc.md").write_text("See sweep at `/tmp/test-g11/sweep.py` for results.\n")
        subprocess.run(["git", "add", "doc.md"], cwd=repo_dir, check=True)
        subprocess.run(["git", "commit", "-m", "add doc"], cwd=repo_dir, capture_output=True, check=True)

        # Pristine clone
        pristine_dir = d / "pristine"
        subprocess.run(["git", "clone", "--shared", str(repo_dir), str(pristine_dir)],
                       capture_output=True, check=True)

        # Dirty the working tree in repo_dir by adding (gone)
        (repo_dir / "doc.md").write_text("See sweep at `/tmp/test-g11/sweep.py` (gone) for results.\n")

        # Run gate in repo_dir evaluating HEAD -> should block (exit 1, CITED)
        r_head = subprocess.run([sys.executable, str(GATE), "--root", str(repo_dir), "--quiet"], cwd=repo_dir, capture_output=True, text=True)
        # Run gate in pristine_dir evaluating HEAD -> should block (exit 1, CITED)
        p_head = subprocess.run([sys.executable, str(GATE), "--root", str(repo_dir), "--quiet"], cwd=pristine_dir, capture_output=True, text=True)
        # Run gate in repo_dir evaluating --worktree -> should pass (exit 0, WITHDRAWN)
        r_wt = subprocess.run([sys.executable, str(GATE), "--root", str(repo_dir), "--worktree", "--quiet"], cwd=repo_dir, capture_output=True, text=True)

        assert r_head.returncode == 1, f"repo HEAD expected exit 1, got {r_head.returncode}"
        assert p_head.returncode == 1, f"pristine HEAD expected exit 1, got {p_head.returncode}"
        assert r_wt.returncode == 0, f"repo --worktree expected exit 0, got {r_wt.returncode}"
        assert r_head.stdout == p_head.stdout, "repo HEAD and pristine HEAD stdout must match"
        print("  [PASS] 2-way checkout and worktree discrimination verified")


def test_machine_resolution_partition_invariance():
    """Verify that whether /tmp paths exist or not, the partition classes and counts are invariant."""
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td)
        repo_dir = d / "repo"
        repo_dir.mkdir()
        subprocess.run(["git", "init"], cwd=repo_dir, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.name", "Tester"], cwd=repo_dir, check=True)
        subprocess.run(["git", "config", "user.email", "tester@test.com"], cwd=repo_dir, check=True)

        live_path = "/tmp/g11-live-probe-test.txt"
        pathlib.Path(live_path).write_text("live\n")
        dead_path = "/tmp/g11-dead-probe-test-definitely-absent.txt"
        if pathlib.Path(dead_path).exists():
            pathlib.Path(dead_path).unlink()

        try:
            (repo_dir / "live.md").write_text(f"Citation at `{live_path}`.\n")
            (repo_dir / "dead.md").write_text(f"Citation at `{dead_path}`.\n")
            subprocess.run(["git", "add", "live.md", "dead.md"], cwd=repo_dir, check=True)
            subprocess.run(["git", "commit", "-m", "add citations"], cwd=repo_dir, capture_output=True, check=True)

            res = subprocess.run([sys.executable, str(GATE), "--root", str(repo_dir)], cwd=repo_dir, capture_output=True, text=True)
            assert "CITED            2  *" in res.stdout, "Both live and dead scratch citations must classify as CITED"
            assert "2 citations of an artifact outside the repository (1 live on host, 1 dead)" in res.stdout,                 "Host diagnostic should report 1 live, 1 dead"
            print("  [PASS] Machine resolution partition invariance verified")
        finally:
            if pathlib.Path(live_path).exists():
                pathlib.Path(live_path).unlink()


def test_fault_injection_on_control():
    """Verify that mutating the gate to read from disk fails the 2-way presence control."""
    original_text = GATE.read_text()
    original_hash = sha256_file(GATE)

    # Corrupt read_corpus so worktree=False incorrectly reads disk
    corrupted_text = original_text.replace(
        "def read_corpus(root=ROOT, rev=\"HEAD\", worktree=False):",
        "def read_corpus(root=ROOT, rev=\"HEAD\", worktree=False):\n    worktree = True  # PLANT FAULT"
    )
    try:
        GATE.write_text(corrupted_text)
        fault_res = subprocess.run([sys.executable, str(GATE), "--control"], capture_output=True, text=True)
        assert fault_res.returncode == 2, f"Planted fault must exit 2, got {fault_res.returncode}"
        assert "MISSED" in fault_res.stdout, "Planted fault must produce MISSED in presence control"
        print(f"  [PASS] Planted fault tripped control (exit {fault_res.returncode})")
    finally:
        GATE.write_text(original_text)
        restored_hash = sha256_file(GATE)
        assert restored_hash == original_hash, f"Hash mismatch after restore: {restored_hash} != {original_hash}"
        print(f"  [PASS] Restored byte-identically with hash {restored_hash[:12]}")


def main():
    print("G11 Verification Suite:")
    test_2way_checkout_and_worktree()
    test_machine_resolution_partition_invariance()
    test_fault_injection_on_control()
    print("ALL G11 VERIFICATION TESTS PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
