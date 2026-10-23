#!/usr/bin/env bash
# README.md keeps its smiley face emoji (issue #10).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

if ! grep -q '😊' "$root/README.md"; then
  echo "FAIL: README.md has no smiley face emoji"
  exit 1
fi
