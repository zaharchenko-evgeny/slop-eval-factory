# Lessons: every repository and agent

## Information access

- `~/.agents/skills` is stale in some sandboxes (5 of 10 skills), so doctor's `skill:*` alarms recur from it; check the skill list before you blame the change (#964, #967, `factory/doctor.py skill_installed`).
- A fix-mode checkout can be shallow or grafted with no merge base; run `git fetch --unshallow origin` before a merge or `git diff origin/main...HEAD` (#785, #860).
- Check that a config key a ticket cites exists before you plan on it (#1052, `engine/defaults.yaml`).

## Automated checks

- Diff against the PR base before handoff; a branch carried unrelated files (fixture symlinks, README) and caused 5 test failures (#897, commit 2f45ac2).
- Reproduce a check that fails with no output on `origin/main` in a clean worktree before you blame the change; the agnix pre-review check exited 1 that way (#1167, commit aa261b7).

## Pushing and branches

- A push is rejected when an old branch from a closed PR exists on origin; use a new slug (#652).
- `git push` with `FACTORY_WRITE_TOKEN` in the URL failed for slop-factory; plain `git push origin` worked (#837).
- After a file move on main, `git merge` mangles the conflict region: take theirs and reapply the patch by hand (#1052, merge 380ebdd).

## No-ops and routing

- An acceptance check that needs a new operator-set secret cannot pass before merge, and the review blocks on not-run; mark it as an operator step on the ticket (#652, PR 905 review B1).
- A reviewer finding that asks to delete code a live path still uses needs a scope decision on the ticket; the fixer cannot resolve it (#951, PR #1046 B1).
- Route an out-of-scope blocking finding straight to a person instead of spending a fix round; a fix round with no change ends blocked anyway (#52).

## AGENTS.md and docs

- List `docs/design.md` and `docs/adr/` in a ticket's affected files when the change alters a documented flow; otherwise they stay stale (#52, ADR-0007).
