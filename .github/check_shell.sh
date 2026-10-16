#!/usr/bin/env bash
# Run by workflows/ci.yml on every PR and push to main.
# This repo has no test suite, so: syntax-check every shell script, make sure
# setup.sh still starts, then run any tests/*.sh. Arguments are ignored.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
status=0
while IFS= read -r f; do
  bash -n "$f" || { echo "syntax error: $f"; status=1; }
done < <(git ls-files -co --exclude-standard '*.sh')
bash setup.sh --help >/dev/null || { echo "setup.sh --help failed"; status=1; }
for t in tests/*.sh; do
  [[ -e "$t" ]] || continue
  echo "running $t"
  bash "$t" || { echo "failed: $t"; status=1; }
done
exit $status
