#!/usr/bin/env bash
# Every environment: tools only some roles need. FACTORY_ROLES lists this environment's roles.
set -euo pipefail
case " ${FACTORY_ROLES:-} " in
  *" approver "*) ;;
  *) exit 0 ;;
esac
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
# The approver evaluates policies/ with conftest; the download is pinned to a version and a SHA-256.
CONFTEST_URL=https://github.com/open-policy-agent/conftest/releases/download/v0.56.0/conftest_0.56.0_Linux_x86_64.tar.gz
CONFTEST_SHA=620f41640d63bbde1646a108ce2816ba54c980466ceebb7e754dda2d508e8cd5
if ! command -v conftest >/dev/null 2>&1 && [ ! -x "$BIN/conftest" ]; then
  tmp=$(mktemp -d)
  curl -fsSL --retry 3 --retry-all-errors --retry-delay 5 "$CONFTEST_URL" -o "$tmp/pkg.tgz"
  if command -v sha256sum >/dev/null 2>&1; then sum=(sha256sum -c -); else sum=(shasum -a 256 -c -); fi
  echo "$CONFTEST_SHA  $tmp/pkg.tgz" | "${sum[@]}" >/dev/null 2>&1 || { echo "environments: checksum mismatch for $CONFTEST_URL" >&2; exit 1; }
  tar -xzf "$tmp/pkg.tgz" -C "$BIN" conftest
fi
# decisions-kit comes from the additional repository JetBrains/jbeval; skipped when it is absent.
if ! command -v decide >/dev/null 2>&1 && [ ! -x "$BIN/decide" ] && [ -d ../jbeval/.git ]; then
  git -C ../jbeval fetch --depth 1 origin tag decisions-kit/v0.3.0
  rm -rf /tmp/decisions-kit
  git -C ../jbeval worktree add --force /tmp/decisions-kit decisions-kit/v0.3.0
  uv tool install /tmp/decisions-kit/apps/decisions
fi
