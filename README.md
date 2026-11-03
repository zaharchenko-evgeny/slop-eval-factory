# Slop factory settings

The team repository of Slop factory. Every Air environment checks it out as the team root (`$HOME/factory-team`,
`FACTORY_TEAM`), and a file here replaces the engine's file at the same path. The engine is
[zaharchenko-evgeny/slop-factory](https://github.com/zaharchenko-evgeny/slop-factory); tickets, PRs and Air
automations stay there.

## Layout

| Path | What it is |
|---|---|
| `factory.descriptor.yaml` | repositories, tracker, models, environments, limits, gates, checks |
| `workflows/nodes.yaml` | the workflow graph: nodes, triggers, outcomes, next steps (`delivery.md` explains it) |
| `roles/<role>/` | each role's `role.md`, `skills.txt`, `handoff.schema.json` and `setup.sh` (tools the role's environment installs); `_common.md` is appended to every role |
| `skills/<name>/` | the skills the roles use, installed into `~/.agents/skills` and `~/.claude/skills` by the environment |
| `knowledge/` | shared knowledge: distilled lessons (`knowledge/slop-factory/`, `knowledge/_shared/`) |

## Changing settings

1. Edit here and open a PR; check it with `uv run --project <engine> <engine>/factory/cli.py validate --team .`.
2. After the merge, the operator redeploys: `factory deploy --team <this checkout> --dry-run`, then `--apply`.
   Roles, skills and knowledge are read at run time, so they apply to the next run without a redeploy; the
   workflow graph and the descriptor change the Air automations, so they need it.
