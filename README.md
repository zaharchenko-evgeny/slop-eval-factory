# Slop factory definition

The software factory that builds [slop-factory](https://github.com/zaharchenko-evgeny/slop-factory), in the
layout of its ADR-0021.

| Path | What it holds |
| --- | --- |
| `factory.yaml` | What the factory has: tracker, models, skills, roles, agents, environments, defaults |
| `workflow.yaml` | How it works: stages, shared settings, the nodes in delivery order |
| `roles/<role>/role.md` | Each role's instructions (Jinja, rendered with the node's settings) |
| `roles/developer/setup.sh` | The developer's tools |
| `lessons/` | The knowledge base: `_shared.md` and one file per repository; retro keeps it |
| `.air/cloud/startup.sh` | The Air startup script: installs the engine, runs `factory setup` |

Check a change with `factory validate --team .` and see the flow with `factory chart --team .`.
