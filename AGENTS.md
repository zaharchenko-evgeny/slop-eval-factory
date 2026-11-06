# Slop factory settings: rules

This repository holds Slop factory's definition and its knowledge base. The engine (the gate, deploy, setup)
is `zaharchenko-evgeny/slop-factory`, and its `AGENTS.md` describes the development workflow. Tickets, PRs and
Air automations for Slop factory stay in `slop-factory`.

- The layout is the engine's ADR-0021: `factory.yaml` lists what the factory has, `workflow.yaml` says how it
  works, `roles/<role>/role.md` holds each role's instructions. All YAML lives in those two files. A change
  must pass `factory validate --team .`.
- `lessons/` is the knowledge base: retro merges lessons into it, agents read it; edit it only through a
  retro PR or a ticket.
- Secrets are named, never stored.
- A change here takes effect after the operator redeploys with the engine's `factory-deploy` skill.
