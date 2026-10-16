#!/usr/bin/env bash
# The gates read merge_own_fixes, autofix_prs, and autofix_issues. "gh" is a
# stub that prints canned JSON, so this runs offline and changes nothing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$root"/github-template/{autotriage_lib.sh,autotriage_guard.sh,autofix_publish.sh} "$tmp/"
mkdir "$tmp/bin"
printf '#!/usr/bin/env bash\ncat "%s/gh.json"\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
failed=0

# Usage: check <script> "<conf lines>" "<gh JSON>" "<expected output>"
check() {
  printf '%b\n' "$2" >"$tmp/autotriage.conf"
  printf '%s\n' "$3" >"$tmp/gh.json"
  out=$(bash "$tmp/$1" 7 someone "$tmp" 2>&1 || true)
  if [[ "$out" != *"$4"* ]]; then
    echo "FAIL: $1 with conf '$2': got '$out', expected '$4'"
    failed=1
  fi
}

# The guard stops at the autofix/* check, or else at the "stop" label.
pr='{"state":"OPEN","isDraft":false,"baseRefName":"main","mergeable":"MERGEABLE",
"reviewDecision":"","headRefName":"autofix/issue-3","labels":[{"name":"stop"}]}'
own="the bot's own fixes need a person"
base="base_branch = main\nblock_label = stop"
check autotriage_guard.sh "mode = normal\n$base" "$pr" "$own"
check autotriage_guard.sh "mode = mayhem\n$base" "$pr" "has label 'stop'"
check autotriage_guard.sh "mode = normal\nmerge_own_fixes = yes\n$base" "$pr" "has label 'stop'"
check autotriage_guard.sh "mode = mayhem\nmerge_own_fixes = no\n$base" "$pr" "$own"
check autotriage_guard.sh "mode = normal\nmerge_own_fixes = maybe\n$base" "$pr" "bad merge_own_fixes"

# Publishing refuses the kind of fix that is off.
issue='{"state":"open","title":"t"}'
pull='{"state":"open","title":"t","pull_request":{}}'
check autofix_publish.sh "mode = normal\nautofix_issues = off" "$issue" "autofix_issues is off"
check autofix_publish.sh "mode = normal\nautofix_prs = off" "$pull" "autofix_prs is off"
check autofix_publish.sh "mode = normal\nautofix = off\nautofix_prs = on" "$issue" "autofix_issues is off"

exit $failed
