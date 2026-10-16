#!/usr/bin/env bash
# load_conf defaults for autofix_prs, autofix_issues, and merge_own_fixes.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# Usage: check "<conf lines>" "<expected autofix_prs autofix_issues merge_own_fixes>"
check() {
  printf '%b\n' "$1" >"$tmp/autotriage.conf"
  got=$(source "$root/github-template/autotriage_lib.sh"
    load_conf "$tmp/autotriage.conf"
    echo "$autofix_prs $autofix_issues $merge_own_fixes")
  if [[ "$got" != "$2" ]]; then
    echo "FAIL: conf '$1': got '$got', expected '$2'"
    failed=1
  fi
}

check "" "off off no"
check "mode = conservative" "off off no"
check "mode = normal" "on on no"
check "mode = mayhem" "on on yes"
check "mode = normal\nautofix = off" "off off no"
check "mode = normal\nautofix = off\nautofix_issues = on" "off on no"
check "mode = normal\nautofix_prs = off" "off on no"
check "mode = normal\nmerge_own_fixes = yes" "on on yes"
check "mode = mayhem\nmerge_own_fixes = no" "on on no"
# Conservative overrides the file.
check "mode = conservative\nautofix_prs = on\nautofix_issues = on\nmerge_own_fixes = yes" "off off no"

exit $failed
