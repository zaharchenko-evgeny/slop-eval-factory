#!/usr/bin/env bash
# The write environment's tools beyond the engine: checks the developer runs before review.
set -euo pipefail
for t in shellcheck-py==0.10.0.1 jactionlint==2.3.0; do
  uv tool install --quiet "$t" || { echo "environments/write: tool install failed: $t" >&2; exit 1; }
done
