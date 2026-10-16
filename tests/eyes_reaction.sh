#!/usr/bin/env bash
# Both template workflows that answer a maintainer's "@claude" comment must
# acknowledge it with an 👀 reaction (issue #5).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
status=0
for wf in github-template/workflows/autotriage.yml github-template/workflows/autofix.yml; do
  if ! grep -qF 'issues/comments/${{ github.event.comment.id }}/reactions' "$wf" ||
    ! grep -qF 'content=eyes' "$wf"; then
    echo "$wf: no 👀 reaction on the triggering comment"
    status=1
  fi
done
exit $status
