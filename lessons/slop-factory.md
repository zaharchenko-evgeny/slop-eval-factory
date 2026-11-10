# Lessons: slop-factory

## Automated checks

- `jactionlint` fails on `origin/main` for `comment-wake-label.yml` (concurrency-limits, dangerous-triggers); report `env-broken`, do not fix it in an unrelated ticket (#652, #847, #861, #867, #896, #941).
- Treat `factory/tests/test_check_workflow.py` (6 tests, check-workflow time-out) as failing on `origin/main`: report `env-broken` instead of fixing it in a ticket (#902, #951).
- Downloads of GitHub releases and the TLC jar return HTTP 504 in CI and tests; wrap each in `scripts/retry-network.sh`, and report a 504-only red as `env-broken` (#1045, #892, run 42465461232).
- Build the wheel in tests with `uv build`, not `pip --no-build-isolation`; CI has no pip or setuptools (#1091, PR 1093).
- Run `factory/tests` one process per file; a single process fails 90+ tests through shared state (#766).
- `test_readme.py` rewrites the `fixtures/team` symlinks to local paths; revert them before commit (#890).
- A test that calls `deploy.main(--apply)` must mock every external writer, or it hits the real GitHub API in CI (#891, `factory/tests/test_deploy.py`).
- A new `validate` rule can fail the factory-setup template and the slop fixture; check both. If the team repo breaks the rule, merge the team PR first, then regenerate the fixture (CI pins `SOURCE`) (#995, `skills/factory-setup/tests/test_templates.py`).

## Coding standards

- Never hand-edit `fixtures/slop/workflow.yaml`; regenerate it with the migrate tool, or `test_slop_fixture_is_migrate_project_output` fails in CI (#1008, PR 1020).
- `test_no_hardcoded_factory_labels_in_engine` flags every literal `factory:x` not preceded by `<!-- `; widen the regex for closing markers (#1038, `factory/tests/test_project_ports.py`).
- Grep for a symbol on `origin/main` before you remove it; removing `wake.ROOT` conflicted with `engine_repository` and broke 3 tests after merge (#1091, PR 1093).
- `writes-not-heard` needs the node to listen to every repository it writes (#978, `factory/definition.py _event_errors`).
- A definition has no tag or field store, so YouTrack deploy scenarios edit the compiled config in test (`youtrack_plan`) (#837).

## Information access

- In the uv tool install `wake.ROOT` (`Path(__file__).parents[3]`) points to `lib/python3.12`, so the comment-wake probes report `project-files denied` (#1091, `factory/factory_plugins/github/wake.py:13`).
- A router `factory doctor` run writes to live issues and PRs, and its `read:actions-run-logs` probe fails with "log not found" for an unknown cause (#732, #968).
- `FACTORY_ISSUES_TOKEN` cannot write the `blocked_by` dependency API (403), so the router cannot link split tickets (#652, `POST .../issues/70/dependencies/blocked_by`).
- A rendered YouTrack team still reports `unlinked-project`: the template has GitHub label triggers and no state stores (#903).
