#!/usr/bin/env bash
# README.md no longer has its smiley face emoji (issue #12 reverses #10).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

if grep -q '😊' "$root/README.md"; then
  echo "FAIL: README.md still has the smiley face emoji"
  exit 1
fi
