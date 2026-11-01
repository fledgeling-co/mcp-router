#!/bin/bash
# Synthetic fixtures only. The Python harness never replaces a live migration plan.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/selftest.py"
