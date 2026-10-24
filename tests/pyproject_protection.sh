#!/usr/bin/env bash
# setup.sh leaves pyproject.toml protected only when the bot can't edit it:
# unprotected in mayhem, or when "@claude fix" may open PRs.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
repo=autotriage-test/pyproject-protection-test
out=output/pyproject-protection-test
trap 'rm -rf "$out"' EXIT
failed=0

# Usage: check "<setup.sh options>" yes|no
check() {
  # shellcheck disable=SC2086
  bash setup.sh --repo "$repo" --maintainer @someone $1 </dev/null >/dev/null 2>&1
  got=no
  if grep -qx 'protected = pyproject.toml' "$out/.github/autotriage.conf"; then got=yes; fi
  if [[ "$got" != "$2" ]]; then
    echo "FAIL: setup.sh $1: pyproject.toml protected '$got', expected '$2'"
    failed=1
  fi
}

check "--mode conservative" yes
check "--mode normal" no
check "--mode normal --no-autofix" yes
check "--mode mayhem" no
check "--mode mayhem --no-autofix" no

exit $failed
