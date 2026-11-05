#!/usr/bin/env bash
# autotriage_comment.sh posts a comment only if it has at most
# max_comment_words outside a closed <details> section. "gh" is a stub that
# records what would be posted, so this runs offline and posts nothing.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$root"/github-template/{autotriage_lib.sh,autotriage_comment.sh} "$tmp/"
mkdir "$tmp/bin"
printf '#!/usr/bin/env bash\necho "$*" >"%s/posted"\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
failed=0

# n words of filler.
words() { printf 'word %.0s' $(seq "$1"); }

# Usage: check "<conf lines>" "<body>" posted|refused
check() {
  printf '%b\n' "$1" >"$tmp/autotriage.conf"
  rm -f "$tmp/posted"
  bash "$tmp/autotriage_comment.sh" 7 "$2" >/dev/null 2>&1 || true
  got=refused
  [[ ! -f "$tmp/posted" ]] || got=posted
  if [[ "$got" != "$3" ]]; then
    echo "FAIL: conf '$1', $(wc -w <<<"$2") words: got $got, expected $3"
    failed=1
  fi
}

check "" "$(words 120)" posted
check "" "$(words 121)" refused
check "" "$(words 100)
<details><summary>Details</summary>
$(words 500)
</details>" posted
# An unclosed <details> hides nothing.
check "" "$(words 100)
<details>
$(words 200)" refused
check "max_comment_words = 200" "$(words 150)" posted

exit $failed
