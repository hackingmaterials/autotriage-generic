#!/usr/bin/env bash
# In mayhem mode the triage bot may close junk issues (issue #14): the rules
# say when, and the workflow sweeps issues and allows `gh issue close`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
rules="$root/github-template/autotriage_rules.md"
workflow="$root/github-template/workflows/autotriage.yml"
failed=0

# Usage: need <file> <fixed string> <what's missing>
need() {
  if ! grep -qF -- "$2" "$1"; then
    echo "FAIL: $3"
    failed=1
  fi
}

need "$rules" "## Closing issues" "rules have no \"Closing issues\" section"
need "$rules" "**Only in mayhem mode.**" "closing issues isn't limited to mayhem"
need "$rules" "Was opened by a maintainer" "maintainer issues aren't protected from closing"
need "$rules" "Has any label" "labeled issues aren't protected from closing"
need "$workflow" "Bash(gh issue close:*)" "workflow doesn't allow gh issue close"
need "$workflow" "gh issue list --state open" "scheduled sweep doesn't list issues"

exit $failed
