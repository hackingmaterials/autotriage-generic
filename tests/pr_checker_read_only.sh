#!/usr/bin/env bash
# The triage bot's pr-checker subagent reads untrusted diffs, so it must only
# be able to read. A subagent with no "tools" list gets all of the bot's
# tools, which can comment, edit PRs, and merge. The rules must also start it
# in the foreground: claude-code-action ends the run at the first result, so
# a background subagent's answer is lost. (authored by claude, not human ardunn)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
wf=github-template/workflows/autotriage.yml
rules=github-template/autotriage_rules.md
failed=0

json=$(grep -o -- "--agents '[^']*'" "$wf" | sed -e "s/^--agents '//" -e "s/'\$//" || true)
if [[ -z "$json" ]]; then
  echo "FAIL: no --agents '<json>' in $wf"
  failed=1
elif ! extra=$(jq -er '.["pr-checker"].tools // ["(no tools list)"]
    | map(select(. != "Read" and . != "Grep" and . != "Glob")) | join(", ")' <<<"$json" 2>/dev/null); then
  echo "FAIL: --agents in $wf is not valid JSON with a pr-checker agent"
  failed=1
elif [[ -n "$extra" ]]; then
  echo "FAIL: pr-checker in $wf may use: $extra. It must only read."
  failed=1
fi

grep -qF '`pr-checker`' "$rules" || { echo "FAIL: $rules doesn't name pr-checker"; failed=1; }
grep -qF 'run_in_background: false' "$rules" || { echo "FAIL: $rules doesn't start subagents in the foreground"; failed=1; }

exit $failed
