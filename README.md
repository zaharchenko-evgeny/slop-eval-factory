# Slop factory settings

The team repository of Slop factory: its descriptor, overrides and knowledge. The engine is
[zaharchenko-evgeny/slop-factory](https://github.com/zaharchenko-evgeny/slop-factory); tickets, PRs and Air
automations stay there.

## Layout

- `factory.descriptor.yaml`: the team descriptor (ADR-0015 in the engine).
- `AGENTS.md`: rules for changing these settings.

Check: `uv run --project <engine checkout> <engine checkout>/factory/cli.py validate --team .`
