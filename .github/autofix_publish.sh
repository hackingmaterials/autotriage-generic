#!/usr/bin/env bash
# Commit a bot-written change, only if it passes these checks. autofix.yml
# runs this in a job without Claude, after Claude has finished; Claude can't
# run it. Settings, including the mode, live in autotriage.conf next to it.
#
# For an issue: commit to autofix/issue-<n> and open a PR that fixes it
# (a draft, except in mayhem mode). For a PR: add one commit to its branch.
#
# Usage: autofix_publish.sh <issue-or-PR-number> <requested-by> <dir>
#   <dir> holds base.sha, the commit Claude started from, and autofix.patch
#   if Claude changed anything. summary.md, if present, is Claude's write-up.
# Run it from the root of a full clone (fetch-depth 0), using a copy of the
# script kept outside the clone, since it switches branches.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source "$here/autotriage_lib.sh"

# Check the arguments.
usage="usage: autofix_publish.sh <issue-or-PR-number> <requested-by> <dir>"
number="${1:?$usage}"
requester="${2:?$usage}"
dir="${3:?$usage}"
[[ "$number" =~ ^[0-9]+$ ]] || fail "'$number' is not an issue or PR number"
who="#$number"
[[ "$requester" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || fail "'$requester' is not a GitHub username"

# Read and check the settings.
load_conf "$here/autotriage.conf"
[[ "$mode" != conservative ]] || fail "mode is conservative, so the bot never commits"
[[ "$autofix" =~ ^(on|off)$ ]] || fail "bad autofix '$autofix'"
[[ "$autofix" == on ]] || fail "autofix is off in autotriage.conf"
[[ "$autofix_max_files" =~ ^[0-9]+$ ]] || fail "bad autofix_max_files '$autofix_max_files'"
[[ "$autofix_max_changed_lines" =~ ^[0-9]+$ ]] || fail "bad autofix_max_changed_lines '$autofix_max_changed_lines'"

# Check the target is open, and whether it is an issue or a PR.
info=$(gh api "repos/{owner}/{repo}/issues/$number")
[[ $(jq -r .state <<<"$info") == open ]] || fail "not open"
title=$(jq -r .title <<<"$info")
target="issue"
[[ $(jq 'has("pull_request")' <<<"$info") == false ]] || target="pr"

summary=$(cat "$dir/summary.md" 2>/dev/null || true)
[[ -n "$summary" ]] || summary="**Bottom line up front:** The autofix bot left no write-up; see the workflow run."

# No change: report back and stop.
patch="$dir/autofix.patch"
if [[ ! -s "$patch" ]]; then
  gh issue comment "$number" --body "$summary

---
Automated reply from the autofix bot, requested by @$requester. No code was changed."
  echo "NO CHANGE for #$number"
  exit 0
fi

base=$(cat "$dir/base.sha")
[[ "$base" =~ ^[0-9a-f]{40}$ ]] || fail "bad base commit '$base'"
default=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)

# For a PR, check its branch first: in this repo, not the default branch,
# and unchanged since Claude started.
if [[ "$target" == pr ]]; then
  pr=$(gh pr view "$number" --json headRefName,headRefOid,isCrossRepository)
  [[ $(jq -r .isCrossRepository <<<"$pr") == false ]] ||
    fail "comes from a fork; the bot only commits to branches in this repository"
  branch=$(jq -r .headRefName <<<"$pr")
  [[ "$branch" != "$default" ]] || fail "its branch is the default branch"
  [[ $(jq -r .headRefOid <<<"$pr") == "$base" ]] || fail "the PR changed while the bot worked; ask again"
fi

# Check the patch applies to the commit Claude started from.
git switch -q --detach "$base"
git apply --check "$patch" || fail "patch does not apply to $base"

# Allow only edits and plain file creations or deletions: no renames, mode
# changes, executables, symlinks, or submodules.
plain='^ (create|delete) mode 100644 '
shapes=$(git apply --summary "$patch")
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ $plain ]] || fail "patch has '${line# }'"
done <<<"$shapes"

# Check each file: not binary, not protected, inside autofix_paths if any
# are listed. Count files, lines, and test files.
numstat=$(git apply --numstat "$patch")
n_files=0
n_lines=0
has_test=false
while IFS=$'\t' read -r added deleted path; do
  [[ -n "$path" ]] || continue
  [[ "$added" != - ]] || fail "patch has binary file $path"
  [[ "$path" != \"* ]] || fail "patch has unusual file name $path"
  ! matches_any "$path" ${protected[@]+"${protected[@]}"} || fail "touches protected file $path"
  if [[ ${#autofix_paths[@]} -gt 0 ]]; then
    matches_any "$path" "${autofix_paths[@]}" || fail "changes $path, which is not in autofix_paths"
  fi
  if matches_any "$path" ${test_paths[@]+"${test_paths[@]}"}; then
    has_test=true
  fi
  n_files=$((n_files + 1))
  n_lines=$((n_lines + added + deleted))
done <<<"$numstat"
[[ "$n_files" -gt 0 ]] || fail "patch changes no files"
[[ "$n_files" -le "$autofix_max_files" ]] || fail "$n_files files changed (limit $autofix_max_files)"
[[ "$n_lines" -le "$autofix_max_changed_lines" ]] ||
  fail "$n_lines changed lines (limit $autofix_max_changed_lines)"

bot_name="github-actions[bot]"
bot_email="41898282+github-actions[bot]@users.noreply.github.com"
commit() {
  git apply --index "$patch"
  git -c user.name="$bot_name" -c user.email="$bot_email" commit -q -F - <<EOF
$1

Written by the autofix bot at the request of @$requester.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
}

if [[ "$target" == pr ]]; then
  # A PR: add one commit to its branch. The lease makes the push fail if the
  # branch moved since the check above.
  git switch -q -C "$branch" "$base"
  commit "Apply changes requested by @$requester"
  git push -q --force-with-lease="$branch:$base" origin "$branch"
  sha=$(git rev-parse --short HEAD)
  gh pr comment "$number" --body "**Bottom line up front:** Pushed $sha to this PR with the changes @$requester asked for; please review it.

It changes $n_files files ($n_lines lines).

$summary

---
Automated reply from the autofix bot. Its conclusions should be checked by a person."
  echo "PUSHED $sha to #$number"
  exit 0
fi

# An issue: the base must be on the default branch, and the fix must change
# a test file if test_paths are listed.
git merge-base --is-ancestor "$base" "origin/$default" || fail "$base is not on $default"
[[ ${#test_paths[@]} -eq 0 || "$has_test" == true ]] || fail "no test changed; a fix needs a regression test"

# Don't overwrite commits someone else pushed to the bot's branch.
branch="autofix/issue-$number"
old=$(git rev-parse -q --verify "refs/remotes/origin/$branch" || true)
if [[ -n "$old" ]]; then
  others=$(git log --format=%ae "origin/$default..$old" | grep -vxF "$bot_email" || true)
  [[ -z "$others" ]] || fail "someone else pushed to $branch; not overwriting it"
fi

# Commit on a fresh branch from the base, and push it. The lease makes the
# push fail if the branch moved since the check above.
git switch -q -C "$branch" "$base"
commit "Fix #$number: $title"
git push -q --force-with-lease="$branch:$old" origin "$branch"

# Open a PR, or update the one already open for this branch. Only mayhem
# mode opens it ready to merge; otherwise it's a draft for a person.
draft=(--draft)
note="A maintainer must review it and mark it ready; the bot never merges its own PRs."
if [[ "$mode" == mayhem ]]; then
  draft=()
  note="In mayhem mode the bot may merge it once CI passes and its review finds nothing to escalate."
fi
body="$summary

Fixes #$number

---
Written by the autofix bot at the request of @$requester. $note"
url=$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')
if [[ -z "$url" ]]; then
  url=$(gh pr create ${draft[@]+"${draft[@]}"} --base "$default" --head "$branch" --title "Fix #$number: $title" --body "$body")
  verb=opened
else
  gh pr edit "$url" --body "$body" >/dev/null
  verb=updated
fi

# Tell the requester.
tested="It does not change any test files."
[[ "$has_test" == false ]] || tested="It includes test changes."
gh issue comment "$number" --body "**Bottom line up front:** PR $url ($verb) proposes a fix; @$requester, please review it.

It changes $n_files files ($n_lines lines). $tested CI results will appear on the PR.

---
Automated reply from the autofix bot. Its conclusions should be checked by a person."
echo "PUBLISHED $url"
