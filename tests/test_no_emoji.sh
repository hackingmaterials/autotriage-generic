#!/usr/bin/env bash
# README.md and CUSTOMIZE.md contain no emoji (issue #12).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export LC_ALL=C.UTF-8

if grep -nP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{FE0F}]' \
    "$root/README.md" "$root/CUSTOMIZE.md"; then
  echo "FAIL: emoji found in README.md or CUSTOMIZE.md"
  exit 1
fi
