#!/bin/sh
# Air environment setup: runs from the settings repository checkout on every launch and resume.
# Idempotent: a launch from a snapshot already has the tools.
set -e
# FACTORY_ENV picks the environment (read, write, ops). Its roles come from the workflow
# (`factory env roles`); each role's skills come from this repository. Tools a team needs beyond
# the engine go in environments/setup.sh (every environment) or environments/<env>/setup.sh.
FACTORY_ENV=${FACTORY_ENV:-default}
TEAM=$(pwd)
FACTORY_TEAM=$(cd "$TEAM" && pwd)
export FACTORY_TEAM
ENGINE="$HOME/factory-main"
# The first value of a top-level key of factory.project.yaml, without quotes or a comment.
project_value() {
  sed -n "s/^$1: *[\"']\{0,1\}\([^\"' #]*\).*/\1/p" "$TEAM/factory.project.yaml" 2>/dev/null | head -n 1
}
ENGINE_REPOSITORY=$(project_value engine_repository)
ENGINE_REPOSITORY=${ENGINE_REPOSITORY:-https://github.com/zaharchenko-evgeny/slop-factory.git}
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
# The roles of the workflow's agent nodes in this environment, one line; needs the engine's `factory`.
env_roles() {
  roles=$("$1" env roles "$FACTORY_ENV") || { echo "startup: cannot read the roles of $FACTORY_ENV" >&2; return 1; }
  echo "$roles" | tr '\n' ' ' | sed 's/ *$//'
}
if [ -n "${FACTORY_DRY:-}" ]; then
  ROLES=$(env_roles factory)
  echo "startup: env=$FACTORY_ENV roles=$ROLES"
  echo "startup: would install skills: $(skill_names)"
  echo "startup: would check tools: $(role_tools)"
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
REF=$(project_value engine)
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
# ADR-0019: a write node may edit this checkout, so the agent's factory reads the team from $HOME/factory-team,
# a worktree detached at the checkout's origin/main and refreshed on every launch, never from the checkout.
TEAM_WORKTREE="$HOME/factory-team"
make_team_worktree() {
  git -C "$TEAM" fetch origin main || return 1
  if [ -e "$TEAM_WORKTREE/.git" ]; then
    git -C "$TEAM_WORKTREE" checkout --detach origin/main
  else
    git -C "$TEAM" worktree prune && git -C "$TEAM" worktree add --detach "$TEAM_WORKTREE" origin/main
  fi
}
if ! make_team_worktree; then
  echo "startup: cannot make the team worktree $TEAM_WORKTREE" >&2
  exit 1
fi
# The agent's shell does not inherit this script's exports: the factory command carries the team itself.
if [ -e "$BIN/factory" ] && ! grep -q 'factory-team-wrapper' "$BIN/factory" 2>/dev/null; then
  mv -f "$BIN/factory" "$BIN/.factory-engine"
fi
cat > "$BIN/factory" <<EOF
#!/bin/sh
# factory-team-wrapper: written by .air/cloud/startup.sh
FACTORY_TEAM=\${FACTORY_TEAM:-$TEAM_WORKTREE}
export FACTORY_TEAM
exec "$BIN/.factory-engine" "\$@"
EOF
chmod +x "$BIN/factory"
ROLES=$(env_roles "$BIN/factory")
# Ops runs from the settings checkout; expose engine scripts used by its role instructions there.
if [ "$FACTORY_ENV" = ops ] && [ ! -e "$TEAM/factory" ] && [ ! -L "$TEAM/factory" ]; then
  ln -s "$ENGINE/factory" "$TEAM/factory"
fi
install_skill() {
  for d in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
    mkdir -p "$d"
    rm -rf "${d:?}/$2"
    cp -R "$1" "$d/$2"
  done
}
for s in $(skill_names); do
  case "$s" in
    ""|.|..|*/*) echo "startup: invalid skill name: $s" >&2; exit 1 ;;
  esac
  src="$TEAM/skills/$s"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "startup: missing team skill: $s" >&2
    exit 1
  fi
  install_skill "$src" "$s"
done
# The engine's own skills are the same for every team: factory-step tells each role how to report its outcome.
if [ -f "$ENGINE/skills/factory-step/SKILL.md" ]; then
  install_skill "$ENGINE/skills/factory-step" factory-step
else
  echo "startup: engine ref $REF has no skill factory-step" >&2
fi
echo "startup: installed skills: $(skill_names) factory-step"
# Environment hooks see the environment's roles in FACTORY_ROLES.
FACTORY_ROLES=$ROLES
export FACTORY_ROLES
for setup in "$TEAM/environments/setup.sh" "$TEAM/environments/$FACTORY_ENV/setup.sh"; do
  if [ -f "$setup" ]; then
    bash "$setup" || { echo "startup: environment setup failed: $setup" >&2; exit 1; }
  fi
done
for r in $ROLES; do
  bash "$(resolve "roles/$r/setup.sh")" >&2 || echo "startup: tools of role $r are missing" >&2
done
case "$FACTORY_ENV" in
  light|probe) echo "startup ran $(date -u +%FT%TZ) FACTORY_ENV=$FACTORY_ENV"; exit 0 ;;
esac
