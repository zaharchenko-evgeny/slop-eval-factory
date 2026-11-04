#!/bin/sh
# Air environment setup: runs from the settings repository checkout on every launch and resume.
# Idempotent: a launch from a snapshot already has the tools.
set -e
# FACTORY_ENV picks the environment (read, write, ops); each installs the skills and tools of its roles.
ROLES=
TOOLS=
case "${FACTORY_ENV:-default}" in
  read) ROLES="router reviewer" ;;
  write) ROLES="developer"; TOOLS="shellcheck-py==0.10.0.1 jactionlint==2.3.0" ;;
  ops) ROLES="distill retro" ;;
esac
TEAM=$(pwd)
FACTORY_TEAM=$TEAM
export FACTORY_TEAM
ENGINE="$HOME/factory-main"
ENGINE_REPOSITORY=${FACTORY_ENGINE_REPOSITORY:-https://github.com/zaharchenko-evgeny/slop-factory.git}
resolve() {
  path="$TEAM/$1"
  if [ -f "$path" ]; then
    printf '%s\n' "$path"
  else
    echo "startup: missing team file: $1" >&2
    return 1
  fi
}
skill_names() {
  for r in $ROLES; do
    [ -f "$TEAM/roles/$r/skills.txt" ] || { echo "startup: missing team file: roles/$r/skills.txt" >&2; return 1; }
  done
  for r in $ROLES; do cat "$TEAM/roles/$r/skills.txt"; done | sort -u | tr '\n' ' '
}
role_tools() {
  for r in $ROLES; do
    [ -f "$TEAM/roles/$r/setup.sh" ] || { echo "startup: missing team file: roles/$r/setup.sh" >&2; return 1; }
  done
  for r in $ROLES; do sed -n 's/^need_tools //p' "$TEAM/roles/$r/setup.sh"; done | tr ' ' '\n' | sort -u | tr '\n' ' '
}
if [ -n "${FACTORY_DRY:-}" ]; then
  echo "startup: env=${FACTORY_ENV:-default} roles=$ROLES"
  echo "startup: would install skills: $(skill_names)"
  echo "startup: would install tools: $(role_tools)$TOOLS"
  exit 0
fi
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
# shellcheck disable=SC2016
grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
# Every download is pinned to a version and a SHA-256; a mismatch fails the script (set -e), nothing is installed.
UV_URL=https://github.com/astral-sh/uv/releases/download/0.5.11/uv-x86_64-unknown-linux-gnu.tar.gz
UV_SHA=14411de26cdea5f5139fafaf2b675b1c633e744dd49c6d6a9fc8817ec065158b
GH_URL=https://github.com/cli/cli/releases/download/v2.62.0/gh_2.62.0_linux_amd64.tar.gz
GH_SHA=41c8b0698ad3003cb5c44bde672a1ffd5f818595abd80162fbf8cc999418446a
CONFTEST_URL=https://github.com/open-policy-agent/conftest/releases/download/v0.56.0/conftest_0.56.0_Linux_x86_64.tar.gz
CONFTEST_SHA=620f41640d63bbde1646a108ce2816ba54c980466ceebb7e754dda2d508e8cd5
fetch() {
  TMP=$(mktemp -d)
  curl -fsSL "$1" -o "$TMP/pkg.tgz"
  if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum -c -"; else SUM="shasum -a 256 -c -"; fi
  echo "$2  $TMP/pkg.tgz" | $SUM >/dev/null 2>&1 || { echo "startup: checksum mismatch for $1" >&2; exit 1; }
}
if ! command -v uv >/dev/null 2>&1; then
  fetch "$UV_URL" "$UV_SHA"
  tar -xzf "$TMP/pkg.tgz" -C "$TMP"
  cp "$TMP"/uv-*/uv "$TMP"/uv-*/uvx "$BIN/"
fi
if ! command -v gh >/dev/null 2>&1; then
  fetch "$GH_URL" "$GH_SHA"
  tar -xzf "$TMP/pkg.tgz" -C "$TMP"
  cp "$TMP"/gh_*/bin/gh "$BIN/gh"
fi
# The settings repository is the only source of team roles, skills and hooks.
FACTORY_TEAM=$(cd "$TEAM" && pwd)
export FACTORY_TEAM
REF=$(sed -n 's/^engine: *"\{0,1\}\([^" #]*\).*/\1/p' "$TEAM/factory.project.yaml" "$TEAM/factory.descriptor.yaml" 2>/dev/null | head -n 1)
case "$REF" in
  main|"") REF=main ;;
  *[!0-9]*) if git check-ref-format "refs/tags/$REF"; then :; else REF=main; fi ;;
  *) REF=main ;;
esac
install_engine() {
  if [ -d "$ENGINE/.git" ]; then
    git -C "$ENGINE" fetch --depth 1 "$ENGINE_REPOSITORY" "$REF" || return 1
    git -C "$ENGINE" checkout --detach FETCH_HEAD || return 1
  else
    git clone --depth 1 --branch "$REF" "$ENGINE_REPOSITORY" "$ENGINE" || return 1
  fi
  uv tool install --force "$ENGINE"
}
if ! install_engine; then
  echo "startup: factory install failed" >&2
  exit 1
fi
# Ops runs from the settings checkout; expose engine scripts used by its role instructions there.
if [ "${FACTORY_ENV:-default}" = ops ] && [ ! -e "$TEAM/factory" ] && [ ! -L "$TEAM/factory" ]; then
  ln -s "$ENGINE/factory" "$TEAM/factory"
fi
for s in $(skill_names); do
  case "$s" in
    ""|.|..|*/*) echo "startup: invalid skill name: $s" >&2; exit 1 ;;
  esac
  src="$TEAM/skills/$s"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "startup: missing team skill: $s" >&2
    exit 1
  fi
  for d in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    mkdir -p "$d"
    rm -rf "${d:?}/$s"
    cp -R "$src" "$d/$s"
  done
done
echo "startup: installed skills: $(skill_names)"
for t in $TOOLS; do
  uv tool install --quiet "$t" || { echo "startup: tool install failed: $t" >&2; exit 1; }
done
for setup in "$TEAM/environments/setup.sh" "$TEAM/environments/${FACTORY_ENV:-default}/setup.sh"; do
  if [ -f "$setup" ]; then
    bash "$setup" || { echo "startup: environment setup failed: $setup" >&2; exit 1; }
  fi
done
for r in $ROLES; do
  bash "$(resolve "roles/$r/setup.sh")" >&2 || echo "startup: tools of role $r are missing" >&2
done
case "${FACTORY_ENV:-default}" in
  light|probe) echo "startup ran $(date -u +%FT%TZ) FACTORY_ENV=$FACTORY_ENV"; exit 0 ;;
esac
if ! command -v conftest >/dev/null 2>&1 && [ ! -x "$BIN/conftest" ]; then
  fetch "$CONFTEST_URL" "$CONFTEST_SHA"
  tar -xzf "$TMP/pkg.tgz" -C "$BIN" conftest
fi
# decisions-kit comes from the additional repository JetBrains/jbeval; skipped when it is absent.
if ! command -v decide >/dev/null 2>&1 && [ ! -x "$BIN/decide" ] && [ -d ../jbeval/.git ]; then
  git -C ../jbeval fetch --depth 1 origin tag decisions-kit/v0.3.0
  rm -rf /tmp/decisions-kit
  git -C ../jbeval worktree add --force /tmp/decisions-kit decisions-kit/v0.3.0
  uv tool install /tmp/decisions-kit/apps/decisions
fi