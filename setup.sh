#!/usr/bin/env bash
# Make autotriage files for a repository. Run it here, in autotriage-generic;
# it writes output/REPO/.github/, which you then copy into the repository:
#
#   ./setup.sh --repo OWNER/REPO --mode normal --maintainer @someone
#   cp -R output/REPO/.github/. path/to/REPO/.github/
#
# It saves the options in MY_PREFERENCES.md, with the other files. After
# autotriage-generic changes, make new files with the same options:
#
#   ./setup.sh --preferences path/to/REPO/.github/MY_PREFERENCES.md
#
# A rerun moves the last run's output/REPO/.github/ to .github.previous/.
#
# Required:
#   --repo OWNER/REPO       the repository to make files for, as in its URL,
#                           e.g. hackingmaterials/matminer
#
# Options (defaults in brackets):
#   --preferences FILE      start from the options saved in a
#                           MY_PREFERENCES.md; options given here win
#   --mode MODE             conservative, normal, or mayhem [conservative]
#   --maintainer @HANDLE    who the bot escalates to; repeat to list other
#                           maintainers [you, from gh]
#   --cron WHEN             how often the bot sweeps open PRs: weekdays,
#                           daily, weekly, 6h, never, or a cron expression
#                           in UTC [weekdays, 9am Pacific]
#   --max-prs N             PRs each sweep may act on [5]
#   --mentions on|off       maintainers can tag "@claude" on issues and PRs [on]
#   --no-autofix            no "@claude fix" in normal or mayhem mode
#   --pip-tools             add the weekly pip-tools dependency upgrade workflow
#   --allow-no-ci           let the bot merge on its own review if the repo
#                           has no CI at all (ignored once it has any CI)
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

# [authored by claude, not human ardunn] Read a MY_PREFERENCES.md: the
# "option = value" lines in the block under "## Setup options", where an
# unknown option is an error. Also keep its "## Files" list and its
# "## Customizations" section, for the new MY_PREFERENCES.md.
read_prefs() {
  local file="$1" block line key value
  [[ -f "$file" ]] || die "no preferences file '$file'"
  block=$(awk '/^## Setup options/ { s = 1; next }
    s == 1 && /^```/ { s = 2; next }
    s == 2 && /^```/ { exit }
    s == 2' "$file")
  [[ -n "$block" ]] || die "$file has no options block under '## Setup options'"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]]; then continue; fi
    [[ "$line" == *=* ]] || die "$file: '$line' is not 'option = value'"
    key="${line%%=*}"
    key="${key//[[:space:]]/}"
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$key" in
      repo) repo="$value" ;;
      mode) mode="$value" ;;
      maintainer) maintainers+=("$value") ;;
      cron) cron="$value" ;;
      max-prs) max_prs="$value" ;;
      mentions) mentions="$value" ;;
      autofix)
        [[ "$value" =~ ^(on|off)$ ]] || die "$file: autofix must be on or off"
        autofix="$value" ;;
      pip-tools)
        [[ "$value" =~ ^(yes|no)$ ]] || die "$file: pip-tools must be yes or no"
        pip_tools=false
        [[ "$value" == no ]] || pip_tools=true ;;
      allow-no-ci)
        [[ "$value" =~ ^(yes|no)$ ]] || die "$file: allow-no-ci must be yes or no"
        allow_no_ci="$value" ;;
      *) die "unknown option '$key' in $file" ;;
    esac
  done <<<"$block"
  prefs_files=$(awk '/^## Files/ { s = 1; next } s && /^## / { exit }
    s && /^- `/ { sub(/^- `/, ""); sub(/`.*$/, ""); print }' "$file")
  prefs_custom=$(awk '/^## Customizations/ { s = 1 } s' "$file")
}

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

# Read the options. A --preferences file is read first, so options given
# here win over it.
mode=conservative
cron=weekdays
max_prs=5
mentions=on
autofix=on
pip_tools=false
allow_no_ci=no
repo=""
maintainers=()
prefs="" prefs_files="" prefs_custom=""
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == --preferences ]]; then
    j=$((i + 1))
    [[ $j -le $# ]] || die "--preferences needs a value"
    prefs="${!j}"
  fi
done
if [[ -n "$prefs" ]]; then read_prefs "$prefs"; fi
cli_maintainers=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preferences) need "$@"; shift 2 ;;
    --mode) need "$@"; mode="$2"; shift 2 ;;
    --maintainer)
      need "$@"
      # [authored by claude, not human ardunn] Handles given here replace
      # the saved list instead of adding to it.
      if ! $cli_maintainers; then
        maintainers=()
        cli_maintainers=true
      fi
      maintainers+=("$2")
      shift 2 ;;
    --cron) need "$@"; cron="$2"; shift 2 ;;
    --max-prs) need "$@"; max_prs="$2"; shift 2 ;;
    --mentions) need "$@"; mentions="$2"; shift 2 ;;
    --no-autofix) autofix=off; shift ;;
    --pip-tools) pip_tools=true; shift ;;
    --allow-no-ci) allow_no_ci=yes; shift ;;
    --repo) need "$@"; repo="$2"; shift 2 ;;
    -h | --help) usage ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
done

# Check them.
[[ "$mode" =~ ^(conservative|normal|mayhem)$ ]] || die "--mode must be conservative, normal, or mayhem"
[[ "$max_prs" =~ ^[1-9][0-9]*$ ]] || die "--max-prs must be a whole number above 0"
[[ "$mentions" =~ ^(on|off)$ ]] || die "--mentions must be on or off"
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
autofix_asked="$autofix"
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
files=(autotriage_rules.md autotriage.conf autotriage_lib.sh autotriage_comment.sh workflows/autotriage.yml)
if [[ "$mode" != conservative ]]; then
  files+=(autotriage_guard.sh)
  if [[ "$autofix" == on ]]; then
    files+=(autofix_rules.md autofix_publish.sh workflows/autofix.yml)
  fi
fi
if [[ "$pip_tools" == true ]]; then files+=(workflows/upgrade-dependencies.yml); fi
files+=(MY_PREFERENCES.md)

# [authored by claude, not human ardunn] Files the last setup made (from
# --preferences) that this one doesn't. Copying the new files into the repo
# leaves them there, so the report says to delete them. Only plain paths
# under .github/ are listed, since the person runs the delete.
stale=()
while IFS= read -r f; do
  if [[ -z "$f" || "$f" == *..* || ! "$f" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?$ ]]; then continue; fi
  keep=false
  for g in "${files[@]}"; do
    if [[ "$f" == "$g" ]]; then keep=true; fi
  done
  if ! $keep; then stale+=("$f"); fi
done <<<"$prefs_files"

# Which autotriage-generic made the files, so an update can see what changed.
version=$(git -C "$here" rev-parse --short HEAD 2>/dev/null || true)
if [[ -z "$version" ]]; then
  version="unknown (not a git checkout)"
elif [[ -n "$(git -C "$here" status --porcelain -- github-template setup.sh 2>/dev/null)" ]]; then
  version="\`$version\`, with local changes"
else
  version="\`$version\`"
fi

# Copy into a fresh output folder. It becomes the repository's .github/, so
# paths below are relative to that.
previous=""
if [[ -d "$out" ]]; then
  # Keep the last run's files, which may have been edited since.
  rm -rf "$out.previous"
  mv "$out" "$out.previous"
  previous="$rel.previous"
fi
mkdir -p "$out/workflows"
cd "$out"
for f in "${files[@]}"; do cp "$src/$f" "$f"; done
for f in autotriage_comment.sh autotriage_guard.sh autofix_publish.sh; do
  if [[ -f "$f" ]]; then chmod +x "$f"; fi
done

# Fill in the settings.
conf=autotriage.conf
set_line "$conf" "mode = " "mode = $mode"
set_line "$conf" "max_prs_per_run = " "max_prs_per_run = $max_prs"
set_line "$conf" "mentions = " "mentions = $mentions"
set_line "$conf" "allow_no_ci = " "allow_no_ci = $allow_no_ci"
if [[ "$mode" != conservative && "$autofix" == off ]]; then set_line "$conf" "# autofix = off" "autofix = off"; fi
# In mayhem, or when the bot may open PRs, it may edit pyproject.toml.
# (Conservative already turned autofix off above.)
if [[ "$mode" == mayhem || "$autofix" == on ]]; then drop_line "$conf" "protected = pyproject.toml"; fi

wf=workflows/autotriage.yml
if [[ -z "$cron_expr" ]]; then
  drop_line "$wf" "  schedule:"
  drop_line "$wf" "    - cron: "
else
  set_line "$wf" "    - cron: " "    - cron: \"$cron_expr\""
fi
if [[ "$mode" == conservative ]]; then
  # Conservative never merges, so the bot doesn't get the merge guard.
  set_text "$wf" ",Bash(.github/autotriage_guard.sh:*)" ""
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

# [authored by claude, not human ardunn] Save what this run used, in the
# format read_prefs reads, so --preferences can make the same files again.
saved=MY_PREFERENCES.md
options="repo = $repo"$'\n'"mode = $mode"
for m in "${maintainers[@]}"; do options="$options"$'\n'"maintainer = $m"; done
pip_tools_yn=no
if [[ "$pip_tools" == true ]]; then pip_tools_yn=yes; fi
options="$options"$'\n'"cron = $cron"$'\n'"max-prs = $max_prs"$'\n'"mentions = $mentions"
options="$options"$'\n'"autofix = $autofix_asked"$'\n'"pip-tools = $pip_tools_yn"$'\n'"allow-no-ci = $allow_no_ci"
file_list=""
for f in "${files[@]}"; do file_list="$file_list${file_list:+$'\n'}- \`$f\`"; done
set_text "$saved" "{{REPO}}" "$repo"
set_text "$saved" "{{VERSION}}" "$version"
set_text "$saved" "{{OPTIONS}}" "$options"
set_text "$saved" "{{FILES}}" "$file_list"

# Check the result.
! grep -n '{{' "$rules" "$saved" || die "placeholders left in $rules or $saved"

# Carry the customizations over. setup.sh can't make them; an agent can.
has_custom=false
if [[ -n "$prefs_custom" ]]; then
  awk '/^## Customizations/ { exit } { print }' "$saved" >"$saved.tmp"
  printf '%s\n' "$prefs_custom" >>"$saved.tmp"
  mv "$saved.tmp" "$saved"
  # Its own placeholder, not the rules' "None listed yet.", which records
  # quote when they describe a change.
  if ! grep -qx 'Nothing recorded yet.' <<<"$prefs_custom"; then has_custom=true; fi
fi
for f in autotriage_lib.sh autotriage_comment.sh autotriage_guard.sh autofix_publish.sh; do
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

# Report. Colors only on a terminal, and never with NO_COLOR set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  bold=$'\033[1m' reset=$'\033[0m'
  cyan=$'\033[36m' green=$'\033[32m' yellow=$'\033[33m' magenta=$'\033[35m'
else
  bold="" reset="" cyan="" green="" yellow="" magenta=""
fi

# Print $2, $1 times.
repeat() {
  local i
  for ((i = 0; i < $1; i++)); do printf '%s' "$2"; done
}
# A section header, 72 columns wide.
section() {
  printf '\n%s━━ %s %s%s\n\n' "$bold$cyan" "$1" "$(repeat $((68 - ${#1})) ━)" "$reset"
}
# A label and its value.
field() { printf '  %-18s %s\n' "$1" "$2"; }
# A command or link, on its own line.
cmd() { printf '     %s%s%s\n' "$green" "$1" "$reset"; }
# Something to watch out for.
note() { printf '  %s!%s %s\n' "$bold$yellow" "$reset" "$1"; }
# A numbered step, then any commands or links for it.
n=1
step() {
  printf '  %s%d.%s %s\n' "$bold" "$n" "$reset" "$1"
  shift
  local c
  for c in "$@"; do cmd "$c"; done
  n=$((n + 1))
}

case "$cron" in
  weekdays) when="weekdays at 9am Pacific" ;;
  daily) when="daily at 9am Pacific" ;;
  weekly) when="Mondays at 9am Pacific" ;;
  6h) when="every 6 hours" ;;
  never) when="never (only when tagged or run by hand)" ;;
  *) when="cron \"$cron_expr\" (UTC)" ;;
esac
url="https://github.com/$repo"

section "Files"
printf '  Made for %s%s%s, in %s:\n\n' "$bold" "$repo" "$reset" "$rel/"
for f in "${files[@]}"; do echo "    $f"; done

section "Settings"
field "Mode" "$mode"
field "Sweeps open PRs" "$when"
field "PRs per sweep" "up to $max_prs"
field '"@claude" mentions' "$mentions"
if [[ "$mode" != conservative ]]; then
  field '"@claude fix"' "$autofix"
  field "Merge without CI" "$allow_no_ci (only if the repo has no CI at all)"
fi
field "Escalates to" "${maintainers[0]}$me_note"
if [[ ${#maintainers[@]} -gt 1 ]]; then field "Other maintainers" "$others"; fi

section "Modes"
cat <<'EOF'
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
EOF
printf '\n  These files use %s%s%s mode.\n\n' "$bold" "$mode" "$reset"
printf '  %sYou can adjust any of this later:%s the mode and other settings are\n' "$bold" "$reset"
echo "  lines in .github/autotriage.conf, and the sweep schedule is the cron line"
echo "  in .github/workflows/autotriage.yml. Conservative mode always wins: it"
echo "  stops every merge and commit."

section "To install"
if [[ ${#stale[@]} -gt 0 ]]; then
  step "In your $repo checkout, delete what the last setup made and this one doesn't. Copying doesn't remove old files, and a leftover workflow still runs:" \
    "(cd path/to/${repo#*/}/.github && rm -f ${stale[*]})"
fi
step "Copy the folder's contents into .github/ in your $repo checkout (files with the same names are replaced):" \
  "cp -R $rel/. path/to/${repo#*/}/.github/"
step "Merge it into your default branch (usually main), through a PR or directly. ${bold}Nothing runs until it is there:${reset} GitHub only runs scheduled and comment-triggered workflows from the default branch."
step "Install the Claude GitHub App, so the bot posts as claude[bot]: run /install-github-app in Claude Code, from your repo. Skip its own workflows."
if [[ "$pip_tools" == true ]]; then
  step "For CI on the dependency PRs: add a personal access token as a PAT secret:" \
    "https://github.com/settings/personal-access-tokens/new" "then $url/settings/secrets/actions/new"
fi
step "Turn off \"Allow GitHub Actions to create and approve pull requests\":" \
  "$url/settings/actions"
if [[ "$mode" != conservative ]]; then
  step "Protect the default branch: require PRs, with your test jobs as required status checks:" \
    "$url/settings/branches"
fi
step "Run it once by hand and read the summary:" \
  "gh workflow run autotriage -R $repo"

section "Notes"
if [[ -n "$previous" ]]; then
  note "The files from your last run, with any edits, are in $previous/. Copy back anything you want to keep."
fi
note "If $repo already has other workflows that run Claude, make sure they don't answer the same \"@claude\" comments."
if [[ -z "$prefs_files" ]]; then
  note "If $repo already has autotriage files from an earlier setup, delete the ones not listed under \"Files\" before you copy. Copying doesn't remove them."
fi
note "MY_PREFERENCES.md saves these choices. Copy it with the rest; next time, run setup.sh --preferences on it."
if $has_custom; then
  note "MY_PREFERENCES.md lists customizations from $prefs that setup.sh doesn't make. Have your agent make them again (below) before you copy the files."
fi
if [[ -n "$lint_note" ]]; then note "$lint_note"; fi

# The API key: check the repo has it, and offer to set it.
section "Anthropic API key"
new_secret="$url/settings/secrets/actions/new"
names=""
if $have_gh && names=$(gh secret list -R "$repo" --json name --jq '.[].name' 2>/dev/null); then
  if grep -qx ANTHROPIC_API_KEY <<<"$names"; then
    printf '  %s✓%s ANTHROPIC_API_KEY is already set on %s.\n' "$bold$green" "$reset" "$repo"
  else
    note "$repo has no ANTHROPIC_API_KEY secret (fine if it's an organization secret)."
    answer=""
    if [[ -t 0 ]]; then
      read -r -p "    Set it now? gh will ask you to paste the key, and won't show it. [y/N] " answer
    fi
    if [[ "$answer" =~ ^[Yy] ]]; then
      if gh secret set ANTHROPIC_API_KEY -R "$repo"; then
        printf '  %s✓%s Set.\n' "$bold$green" "$reset"
      else
        note "That didn't work. Add it here:"
        cmd "$new_secret"
      fi
    else
      echo "    Add it yourself, on this page or with gh in your own terminal:"
      cmd "$new_secret"
      cmd "gh secret set ANTHROPIC_API_KEY -R $repo"
    fi
  fi
else
  note "Couldn't check $repo's secrets (gh isn't installed or logged in, or you lack access)."
  echo "    If ANTHROPIC_API_KEY isn't set yet, add it yourself on this page:"
  cmd "$new_secret"
fi

# The next step, impossible to miss.
bar=$(repeat 72 ━)
printf '\n%s%s%s\n\n' "$bold$magenta" "$bar" "$reset"
printf '  %s▶ NOW RUN THIS IN YOUR AGENT:%s\n\n' "$bold$yellow" "$reset"
if $has_custom; then
  printf '    %sRead CUSTOMIZE.md and update the autotriage files in %s for %s from its MY_PREFERENCES.md. I already ran setup.sh.%s\n' \
    "$bold$green" "$rel" "$repo" "$reset"
else
  printf '    %sRead CUSTOMIZE.md and walk me through customizing the autotriage files in %s for %s. I already ran setup.sh.%s\n' \
    "$bold$green" "$rel" "$repo" "$reset"
fi
printf '\n%s%s%s\n' "$bold$magenta" "$bar" "$reset"

# When an agent (or anything non-interactive) runs this, say plainly which
# steps are the person's.
if [[ ! -t 0 ]]; then
  echo
  echo "Note for AI agents running this script: the steps under \"To install\" and"
  echo "\"Anthropic API key\" are for the person to do themselves. Show them these"
  echo "steps and links; don't run them. Never ask the person to paste an API key or"
  echo "token into the chat: they set it in their own terminal or on the web page."
  echo "To tailor the files, follow CUSTOMIZE.md."
fi
