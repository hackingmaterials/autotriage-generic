#!/usr/bin/env bash
# A comment that is only "@claude sweep" or "@claude cron" runs the scheduled
# sweep; anything longer stays an ordinary mention.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
wf=github-template/workflows/autotriage.yml
re=$(grep -F '(sweep|cron)' "$wf" | sed -E 's/.*=~ (.*) \]\] && trigger=sweep.*/\1/')
[[ -n "$re" ]] || { echo "$wf: no sweep command"; exit 1; }
grep -qF "steps.settings.outputs.trigger" "$wf" || { echo "$wf: prompt ignores the sweep trigger"; exit 1; }
status=0
check() {
  local body=$1 want=$2 got=mention
  shopt -s nocasematch
  [[ "$body" =~ $re ]] && got=sweep
  shopt -u nocasematch
  if [[ "$got" != "$want" ]]; then
    printf '%q: got %s, want %s\n' "$body" "$got" "$want"
    status=1
  fi
}
check "@claude sweep" sweep
check "@claude cron" sweep
check "  @CLAUDE  Sweep " sweep
check $'@claude sweep\r\n' sweep
check "@claude sweep the PRs" mention
check "@claude sweeping changes?" mention
check "please @claude sweep" mention
check "@claude fix" mention
exit $status
