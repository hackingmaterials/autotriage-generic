#!/usr/bin/env bash
# [authored by claude, not human ardunn] setup.sh saves its options in
# MY_PREFERENCES.md, and --preferences makes the same files from it again,
# as an update does. Also pins the guidance that tells agents to look for
# that file first, so it keeps matching what setup.sh writes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
repo=autotriage-test/preferences-test
out=output/preferences-test
saved="$out/saved.md"
trap 'rm -rf "$out"' EXIT
failed=0
fail() {
  echo "FAIL: $1"
  failed=1
}

# Usage: setup <options...>; prints setup.sh's report to $out/report.
setup() {
  mkdir -p "$out"
  bash setup.sh "$@" </dev/null >"$out/report" 2>&1 || {
    fail "setup.sh $*: $(tail -1 "$out/report")"
    return 1
  }
}
prefs="$out/.github/MY_PREFERENCES.md"
has_line() { grep -qxF -- "$2" "$1" || fail "$1 lacks the line '$2'"; }

# A first run saves its options and its files.
setup --repo "$repo" --mode normal --maintainer @alice --maintainer bob --cron daily --max-prs 7 --pip-tools
for line in "repo = $repo" "mode = normal" "maintainer = @alice" "maintainer = @bob" "cron = daily" \
  "max-prs = 7" "mentions = on" "autofix = on" "pip-tools = yes" "allow-no-ci = no" \
  '- `workflows/autofix.yml`' '- `MY_PREFERENCES.md`' "Nothing recorded yet."; do
  has_line "$prefs" "$line"
done
if grep -n '{{' "$prefs"; then fail "placeholders left in MY_PREFERENCES.md"; fi
cp "$prefs" "$saved"

# --preferences alone makes the same files again.
setup --preferences "$saved"
diff -r "$out/.github.previous" "$out/.github" >/dev/null || fail "--preferences didn't make the same files"
if grep -q 'delete what the last setup made' "$out/report"; then fail "same files, but asked to delete some"; fi

# So does the file inside the output folder, which setup.sh moves aside.
setup --preferences "$prefs"
diff -r "$out/.github.previous" "$out/.github" >/dev/null || fail "--preferences on the output's own file didn't work"

# Options given win; a --maintainer replaces the saved list.
setup --preferences "$saved" --mode conservative --maintainer @carol
has_line "$prefs" "mode = conservative"
has_line "$prefs" "maintainer = @carol"
has_line "$prefs" "cron = daily"
if grep -qx 'maintainer = @alice' "$prefs"; then fail "--maintainer added to the saved list instead of replacing it"; fi
# ...and the report says which old files to delete from the repo.
want="(cd path/to/preferences-test/.github && rm -f autotriage_guard.sh autofix_rules.md autofix_publish.sh workflows/autofix.yml)"
grep -qF -- "$want" "$out/report" || fail "report doesn't say to delete the files conservative doesn't make"

# Customizations are carried over, and the agent is told to make them again.
awk '{ print } /^## Customizations/ { exit }' "$saved" >"$out/custom.md"
printf '\n- autotriage_rules.md, "Style for this repo": British spelling.\n' >>"$out/custom.md"
setup --preferences "$out/custom.md"
has_line "$prefs" '- autotriage_rules.md, "Style for this repo": British spelling.'
grep -q "update the autotriage files in .* from its MY_PREFERENCES.md" "$out/report" ||
  fail "report doesn't ask the agent to make the customizations again"
# A record that quotes the rules' own "None listed yet." on a line of its
# own still counts as a record.
awk '{ print } /^## Customizations/ { exit }' "$saved" >"$out/custom.md"
printf '\n- autotriage_rules.md, "Area owners": replaced\n\n```\nNone listed yet.\n```\n' >>"$out/custom.md"
setup --preferences "$out/custom.md"
grep -q "update the autotriage files in .* from its MY_PREFERENCES.md" "$out/report" ||
  fail "a record quoting \"None listed yet.\" was taken for no record"

# Bad files are refused.
printf '## Setup options\n```text\nrepo = %s\ncolour = blue\n```\n' "$repo" >"$out/bad.md"
if bash setup.sh --preferences "$out/bad.md" </dev/null >/dev/null 2>&1; then fail "unknown option accepted"; fi
printf '# no options\n' >"$out/bad.md"
if bash setup.sh --preferences "$out/bad.md" </dev/null >/dev/null 2>&1; then fail "file with no options block accepted"; fi

# The guidance: look for saved preferences before anything else, by the
# file name setup.sh writes, and never delete output/ to regenerate.
first=$(grep -m1 -n '^\*\*First' CUSTOMIZE.md || true)
[[ "$first" == *"saved preferences"* ]] || fail "CUSTOMIZE.md's first step isn't looking for saved preferences"
grep -qF 'contents/.github/MY_PREFERENCES.md' CUSTOMIZE.md || fail "CUSTOMIZE.md doesn't look for the repo's MY_PREFERENCES.md"
# In testing, an agent that saw a copy in output/ skipped the repo's, which
# may be newer. Keep the "always", whatever the line wrapping.
tr -s ' \n' ' ' <CUSTOMIZE.md | grep -qF "Always check the repo's own copy, even if \`output/\` has one" ||
  fail "CUSTOMIZE.md doesn't say to always check the repo's copy"
grep -q '^## Update from saved preferences' CUSTOMIZE.md || fail "CUSTOMIZE.md has no update section"
grep -q 'never delete `output/REPO/`' CUSTOMIZE.md || fail "CUSTOMIZE.md doesn't say to leave output/ to setup.sh"
grep -q 'update the autotriage files for' README.md || fail "README.md doesn't give the update prompt"
[[ -f github-template/MY_PREFERENCES.md ]] || fail "no github-template/MY_PREFERENCES.md"

exit $failed
