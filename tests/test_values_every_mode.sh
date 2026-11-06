#!/usr/bin/env bash
# Changed expected values in tests are escalated in every mode, mayhem
# included. No bot runs code, so a test "updated to pass" needs a person to
# check the new numbers (issue #22). The bullet must sit in rule 1's
# "In every mode" list, and only there. (authored by claude, not human ardunn)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
rules=github-template/autotriage_rules.md
bullet='- Changes expected values in tests'
failed=0

every=$(sed -n '/^\*\*In every mode,\*\*/,/^\*\*Unless the mode is mayhem,\*\*/p' "$rules")
if ! grep -qF -- "$bullet" <<<"$every"; then
  echo "FAIL: $rules doesn't escalate changed expected test values in every mode"
  failed=1
fi
count=$(grep -cF -- "$bullet" "$rules" || true)
if [[ "$count" -ne 1 ]]; then
  echo "FAIL: $rules lists changed expected test values $count times, expected once"
  failed=1
fi

exit $failed
