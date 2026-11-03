# Slop factory settings: rules

This repository holds only Slop factory's settings. The engine (code, default roles, skills, the graph and
`engine/defaults.yaml`) is `zaharchenko-evgeny/slop-factory`, and its `AGENTS.md` describes the development
workflow. Tickets, PRs and Air automations for Slop factory stay in `slop-factory`.

- `factory.descriptor.yaml` is the team descriptor. It must pass `factory validate --team .`.
- A file here at the same path as an engine file (`roles/`, `skills/`, `workflows/`) replaces the engine's.
- Secrets are named, never stored.
- A change here takes effect after the operator redeploys with `factory deploy --team <this checkout>`.
