#!/usr/bin/env bash
# The bots' comments must not carry a literal "Bottom line up front:" label,
# neither in the templates' fixed comment text nor in the format they tell
# the agents to follow (issue #6).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if grep -rniF 'bottom line up front:' github-template/; then
  echo "github-template/ still writes or asks for the \"Bottom line up front:\" label"
  exit 1
fi
