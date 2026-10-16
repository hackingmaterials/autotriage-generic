#!/usr/bin/env bash
# Make autotriage files for a repository. Run it here, in autotriage-generic;
# it writes output/REPO/.github/, which you then copy into the repository:
#
#   ./setup.sh --repo OWNER/REPO --mode normal --maintainer @someone
#   cp -R output/REPO/.github/. path/to/REPO/.github/
#
# Required:
#   --repo OWNER/REPO       the repository to make files for, as in its URL,
#                           e.g. hackingmaterials/matminer
#
# Options (defaults in brackets):
#   --mode MODE             conservative, normal, or mayhem [conservative]
#   --maintainer @HANDLE    who the bot escalates to; repeat to list other
#                           maintainers [you, from gh]
#   --cron WHEN             how often the bot sweeps open PRs: weekdays,
#                           daily, weekly, 6h, never, or a cron expression
#                           in UTC [weekdays, 9am Pacific]
#   --max-prs N             PRs each sweep may act on [5]
#   --mentions on|off       maintainers can tag @claude on issues and PRs [on]
#   --no-autofix            no "@claude fix" in normal or mayhem mode
#   --test-command CMD      how autofix runs tests [python -m pytest]
#   --install-command CMD   how autofix installs the package
#                           [python -m pip install -e ".[tests]" pytest]
#   --pip-tools             add the weekly pip-tools dependency upgrade workflow
#
# Modes:
#   conservative  Code review only: comments, labels, escalations.
#   normal        Also merges easy PRs (docs, dependency upgrades, small
#                 changes with tests); "@claude fix" opens draft PRs for
#                 issues or commits to PRs. Never merges its own work.
#   mayhem        Also merges anything that passes CI and its review, its
#                 own fixes included.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/github-template"

die() {
  echo "setup.sh: $1" >&2
  exit 1
}
usage() {
  sed -n '2,/^set -euo pipefail/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
  exit 0
}
need() { [[ $# -ge 2 ]] || die "$1 needs a value"; }

# Replace the one line of file $1 that starts with $2 by $3, which may span
# lines. Values pass through the environment, so nothing needs escaping.
set_line() {
  local n
  n=$(PREFIX="$2" awk 'index($0, ENVIRON["PREFIX"]) == 1 { n++ } END { print n + 0 }' "$1")
  [[ "$n" -eq 1 ]] || die "expected one line starting with '$2' in $1, found $n"
  PREFIX="$2" NEW="$3" awk 'index($0, ENVIRON["PREFIX"]) == 1 { print ENVIRON["NEW"]; next } { print }' "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}

# Delete the one line of file $1 that starts with $2.
drop_line() {
  set_line "$1" "$2" "@@drop@@"
  awk '$0 != "@@drop@@"' "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}

# Replace every "$2" in file $1 by $3.
set_text() {
  OLD="$2" NEW="$3" awk '{
    out = ""; rest = $0; old = ENVIRON["OLD"]
    while ((i = index(rest, old)) > 0) {
      out = out substr(rest, 1, i - 1) ENVIRON["NEW"]
      rest = substr(rest, i + length(old))
    }
    print out rest
  }' "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}

# Quote $1 as a single-quoted YAML string.
yaml_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }

# Read the options.
mode=conservative
cron=weekdays
max_prs=5
mentions=on
autofix=on
test_cmd=""
install_cmd=""
pip_tools=false
repo=""
maintainers=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) need "$@"; mode="$2"; shift 2 ;;
    --maintainer) need "$@"; maintainers+=("$2"); shift 2 ;;
    --cron) need "$@"; cron="$2"; shift 2 ;;
    --max-prs) need "$@"; max_prs="$2"; shift 2 ;;
    --mentions) need "$@"; mentions="$2"; shift 2 ;;
    --no-autofix) autofix=off; shift ;;
    --test-command) need "$@"; test_cmd="$2"; shift 2 ;;
    --install-command) need "$@"; install_cmd="$2"; shift 2 ;;
    --pip-tools) pip_tools=true; shift ;;
    --repo) need "$@"; repo="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
done

# Check them.
[[ "$mode" =~ ^(conservative|normal|mayhem)$ ]] || die "--mode must be conservative, normal, or mayhem"
[[ "$max_prs" =~ ^[1-9][0-9]*$ ]] || die "--max-prs must be a whole number above 0"
[[ "$mentions" =~ ^(on|off)$ ]] || die "--mentions must be on or off"
# The test command also goes inside a double-quoted --allowedTools list.
[[ "$test_cmd" != *'"'* ]] || die "--test-command can't contain double quotes; use single quotes"
case "$cron" in
  weekdays) cron_expr="0 16 * * 1-5" ;;
  daily) cron_expr="0 16 * * *" ;;
  weekly) cron_expr="0 16 * * 1" ;;
  6h) cron_expr="0 */6 * * *" ;;
  never) cron_expr="" ;;
  *)
    read -r -a fields <<<"$cron"
    [[ ${#fields[@]} -eq 5 ]] || die "--cron must be weekdays, daily, weekly, 6h, never, or a 5-field cron expression"
    cron_expr="$cron"
    ;;
esac
[[ "$mode" != conservative ]] || autofix=off
i=0
while [[ $i -lt ${#maintainers[@]} ]]; do
  handle="${maintainers[$i]#@}"
  [[ "$handle" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "'${maintainers[$i]}' is not a GitHub handle"
  maintainers[i]="@$handle"
  i=$((i + 1))
done

# The repository, and where its files go.
[[ -n "$repo" ]] || die "pass --repo OWNER/REPO: the repository to make files for"
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] || die "'$repo' is not OWNER/REPO"
rel="output/${repo#*/}/.github"
out="$here/$rel"
have_gh=false
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then have_gh=true; fi
description=""
if $have_gh; then description=$(gh repo view "$repo" --json description --jq '.description // ""' 2>/dev/null || true); fi

# Default the maintainer to whoever runs this.
me_note=""
if [[ ${#maintainers[@]} -eq 0 ]]; then
  me=""
  if $have_gh; then me=$(gh api user --jq .login 2>/dev/null || true); fi
  [[ -n "$me" ]] || die "pass --maintainer @handle: who the bot escalates to"
  maintainers=("@$me")
  me_note=" (you; change with --maintainer)"
fi

# Choose the files for the mode.
files=(autotriage_rules.md autotriage.conf autotriage_lib.sh workflows/autotriage.yml)
if [[ "$mode" != conservative ]]; then
  files+=(autotriage_guard.sh)
  if [[ "$autofix" == on ]]; then
    files+=(autofix_rules.md autofix_publish.sh workflows/autofix.yml)
  fi
fi
if [[ "$pip_tools" == true ]]; then files+=(workflows/upgrade-dependencies.yml); fi

# Copy into a fresh output folder. It becomes the repository's .github/, so
# paths below are relative to that.
rm -rf "$out"
mkdir -p "$out/workflows"
cd "$out"
for f in "${files[@]}"; do cp "$src/$f" "$f"; done
for f in autotriage_guard.sh autofix_publish.sh; do
  if [[ -f "$f" ]]; then chmod +x "$f"; fi
done

# Fill in the settings.
conf=autotriage.conf
set_line "$conf" "mode = " "mode = $mode"
set_line "$conf" "max_prs_per_run = " "max_prs_per_run = $max_prs"
set_line "$conf" "mentions = " "mentions = $mentions"
if [[ "$mode" != conservative && "$autofix" == off ]]; then set_line "$conf" "# autofix = off" "autofix = off"; fi

wf=workflows/autotriage.yml
if [[ -z "$cron_expr" ]]; then
  drop_line "$wf" "  schedule:"
  drop_line "$wf" "    - cron: "
else
  set_line "$wf" "    - cron: " "    - cron: \"$cron_expr\""
fi
if [[ "$mode" == conservative ]]; then
  # Conservative never merges: no guard, and the job's own read-only token
  # instead of the Claude app's token, which permissions: doesn't limit.
  set_text "$wf" ",Bash(.github/autotriage_guard.sh:*)" ""
  set_line "$wf" "      contents: write" "      contents: read"
  set_line "$wf" "          anthropic_api_key: " "          anthropic_api_key: \${{ secrets.ANTHROPIC_API_KEY }}
          # Conservative mode: the job's own token, limited by permissions.
          github_token: \${{ github.token }}"
fi

if [[ -f workflows/autofix.yml ]]; then
  af=workflows/autofix.yml
  if [[ -n "$test_cmd" ]]; then set_line "$af" "      TEST_COMMAND: " "      TEST_COMMAND: $(yaml_quote "$test_cmd")"; fi
  if [[ -n "$install_cmd" ]]; then set_line "$af" "        run: python -m pip install" "        run: $(yaml_quote "$install_cmd")"; fi
fi

rules=autotriage_rules.md
repo_line="$repo"
if [[ -n "$description" ]]; then repo_line="$repo: $description"; fi
others="none listed yet"
if [[ ${#maintainers[@]} -gt 1 ]]; then
  others="${maintainers[1]}"
  i=2
  while [[ $i -lt ${#maintainers[@]} ]]; do
    others="$others, ${maintainers[$i]}"
    i=$((i + 1))
  done
fi
set_text "$rules" "{{REPO}}" "$repo_line"
set_text "$rules" "{{MAINTAINER}}" "${maintainers[0]}"
set_text "$rules" "{{OTHER_MAINTAINERS}}" "$others"

# Check the result.
! grep -n '{{' "$rules" || die "placeholders left in $rules"
for f in autotriage_lib.sh autotriage_guard.sh autofix_publish.sh; do
  if [[ -f "$f" ]]; then bash -n "$f" || die "syntax error in $f"; fi
done
expected="$mode"
(
  source autotriage_lib.sh
  load_conf "$conf" >/dev/null
  [[ "$mode" == "$expected" ]]
) || die "$conf doesn't read back as mode $expected"
lint_note=""
if command -v actionlint >/dev/null; then
  wfs=()
  for f in "${files[@]}"; do
    if [[ "$f" == workflows/* ]]; then wfs+=("$f"); fi
  done
  actionlint "${wfs[@]}" || lint_note="actionlint reported the problems above; check them."
fi

# Report.
case "$cron" in
  weekdays) when="weekdays at 9am Pacific" ;;
  daily) when="daily at 9am Pacific" ;;
  weekly) when="Mondays at 9am Pacific" ;;
  6h) when="every 6 hours" ;;
  never) when="never on a schedule (only when tagged or run by hand)" ;;
  *) when="on cron \"$cron_expr\" (UTC)" ;;
esac
echo "Made autotriage files for $repo, in $mode mode, in $rel:"
for f in "${files[@]}"; do echo "  $f"; done
echo
echo "Settings:"
echo "  Sweeps open PRs $when, acting on up to $max_prs per sweep."
echo "  Maintainers can tag @claude: $mentions."
if [[ "$mode" != conservative ]]; then echo "  \"@claude fix\": $autofix."; fi
echo "  Escalates to ${maintainers[0]}$me_note."
echo
cat <<'EOF'
What each mode allows:

  |                                                       | conservative | normal       | mayhem     |
  |-------------------------------------------------------|--------------|--------------|------------|
  | Review PRs: comment, label, escalate                  | yes          | yes          | yes        |
  | Merge docs, dependency upgrades, small tested changes | no           | yes          | yes        |
  | Merge anything that passes CI and review              | no           | no           | yes        |
  | "@claude fix" on an issue opens a PR                  | no           | yes, a draft | yes, ready |
  | "@claude fix" on a PR commits to it                   | no           | yes          | yes        |
  | Merge its own fixes                                   | no           | no           | yes        |
  | Always escalate security, cost, protected files,      | yes          | yes          | yes        |
  | domain risk areas                                     |              |              |            |

You can adjust any of this later: the mode and other settings are lines in
.github/autotriage.conf, and the sweep schedule is the cron line in
.github/workflows/autotriage.yml. Conservative mode always wins: it stops
every merge and commit.
EOF
echo
echo "To install:"
n=1
step() {
  echo "  $n. $1"
  n=$((n + 1))
}
step "Copy the folder's contents into .github/ in your $repo checkout. Files with the same names are replaced: cp -R $rel/. path/to/${repo#*/}/.github/"
step "Merge it into your default branch (usually main), through a PR or directly. Nothing runs until it is there: GitHub only runs scheduled and comment-triggered workflows from the default branch."
url="https://github.com/$repo"
if [[ "$mode" != conservative ]]; then
  step "Install the Claude GitHub App on $repo; the bot merges and commits with its token: https://github.com/apps/claude"
fi
if [[ "$mode" != conservative || "$pip_tools" == true ]]; then
  step "Add a PAT secret, so CI runs on the bot's PRs and commits: $url/settings/secrets/actions/new or gh secret set PAT -R $repo"
fi
step "Turn off \"Allow GitHub Actions to create and approve pull requests\": $url/settings/actions"
if [[ "$mode" != conservative ]]; then
  step "Protect the default branch: require PRs, with your test jobs as required status checks: $url/settings/branches"
fi
if [[ -f workflows/autofix.yml && ( -z "$test_cmd" || -z "$install_cmd" ) ]]; then
  step "Check TEST_COMMAND and the install step in .github/workflows/autofix.yml match your CI."
fi
step "Run it once by hand and read the summary: gh workflow run autotriage -R $repo"
echo
echo "If $repo already has other workflows that run Claude, make sure they don't"
echo "answer the same @claude comments. If you rerun setup.sh with a different mode,"
echo "delete autotriage files the new mode no longer lists from the repo."
if [[ -n "$lint_note" ]]; then
  echo
  echo "$lint_note"
fi

# The API key: check the repo has it, and offer to set it.
echo
echo "Anthropic API key:"
new_secret="https://github.com/$repo/settings/secrets/actions/new"
names=""
if $have_gh && names=$(gh secret list -R "$repo" --json name --jq '.[].name' 2>/dev/null); then
  if grep -qx ANTHROPIC_API_KEY <<<"$names"; then
    echo "  ANTHROPIC_API_KEY is already set on $repo."
  else
    echo "  $repo has no ANTHROPIC_API_KEY secret (fine if it's an organization secret)."
    answer=""
    if [[ -t 0 ]]; then
      read -r -p "  Set it now? gh will ask you to paste the key, and won't show it. [y/N] " answer
    fi
    if [[ "$answer" =~ ^[Yy] ]]; then
      if gh secret set ANTHROPIC_API_KEY -R "$repo"; then
        echo "  Set."
      else
        echo "  That didn't work. Add it at $new_secret"
      fi
    else
      echo "  Add it at $new_secret, or run: gh secret set ANTHROPIC_API_KEY -R $repo"
    fi
  fi
else
  echo "  Couldn't check $repo's secrets (gh isn't installed or logged in, or you"
  echo "  lack access). If ANTHROPIC_API_KEY isn't set yet, add it at $new_secret"
fi

# How to tailor the files with an agent.
echo
echo "Now run this in your agent:"
echo
echo "  Read CUSTOMIZE.md and walk me through customizing the autotriage files in"
echo "  $rel for $repo. I already ran setup.sh."
