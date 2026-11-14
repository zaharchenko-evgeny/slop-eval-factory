# Lessons: slop-factory

## Automated checks

- `jactionlint` fails on `origin/main` for `comment-wake-label.yml` (concurrency-limits, dangerous-triggers); report `env-broken`, do not fix it in an unrelated ticket (#652, #847, #861, #867, #896, #941).
- Treat `factory/tests/test_check_workflow.py` (6 tests, check-workflow time-out, or `spawn java ENOENT` with no Java) as failing on `origin/main`: report `env-broken` instead of fixing it in a ticket; `environments/setup.sh` now installs Node and Java, so check `java -version` first (#902, #951, #1363, #1365, #1380, #1387, #1391, #1399).
- Downloads of GitHub releases and the TLC jar return HTTP 504 in CI and tests; wrap each in `scripts/retry-network.sh`, and report a 504-only red as `env-broken` (#1045, #892, run 42465461232).
- Build the wheel in tests with `uv build`, not `pip --no-build-isolation`; CI has no pip or setuptools (#1091, PR 1093).
- Run `factory/tests` one process per file; a single process fails 90+ tests through shared state (#766).
- `test_readme.py` rewrites the `fixtures/team` symlinks to local paths; revert them before commit (#890).
- A test that calls `deploy.main(--apply)` must mock every external writer, or it hits the real GitHub API in CI (#891, `factory/tests/test_deploy.py`).
- A new `validate` rule can fail the factory-setup template and the slop fixture; check both. If the team repo breaks the rule, merge the team PR first, then regenerate the fixture (CI pins `SOURCE`) (#995, `skills/factory-setup/tests/test_templates.py`).
- `factory/tests/fixtures/slop` mirrors `slop-eval-factory`; apply the same `factory.yaml` token edit and `issues_token_env` removal there, or the SOURCE check fails (#1236).
- The sandbox sets `FACTORY_ENV`, `FACTORY_ENV_REPOSITORY` and `FACTORY_ISSUES_TOKEN`; tests that read the process environment must patch them (#1236, `test_gate_github.py CiSyncCodeHostTest`).
- `uv run factory/nodes.py validate` fails on `origin/main` with `unknown-effect: notify-pr.notified` (`assign` on `pr`); report `env-broken`, do not fix it in an unrelated ticket (#1243, #1286, #1383).
- The CI-equivalent test run needs `pytest` and Java (statechart checks) in the sandbox: `uv run --with pytest pytest -q -p no:cacheprovider factory/tests skills/factory-setup/tests` (#1326).
- Tests that read the global team break under one-process pytest; pin the slop team in `setUpModule` or `setUpClass` (`test_deploy.py` PlanTest, `test_reconcile.py` ReconcileMainBlockersTest) (#681, CI factory-checks).
- `test_gate_space.py test_definition_validation_names_the_environment_vcs` fails without `jinja2` in the script deps, also on `origin/main`; report `env-broken` (#681).
- `factory/check_refs.py` treats any backticked absolute path such as `/workspaces` in docs as a missing repo path; avoid backticks around such paths (#1237, `docs/environment.md`).
- Full `factory/tests` takes over 10 minutes in one run; use `pytest -n 8` under a foreground limit, and never run `pkill -f pytest` (it kills your own shell) (#1394, #1399).
- `doctor.skill_installed` reads `~/.agents/skills` for v2 teams, so tests pass locally and fail in CI unless they inject `has_skill` (#1394, `factory/tests/test_doctor.py test_missing_tool_reported_for_env`).
- Race tests must block at the write (barrier before the POST), not at a read; the gate reads comments several times, so a read barrier never overlaps (#1373, `test_gate_github.py test_overlapping_runs_of_one_node_keep_the_first_comment_only`).
- Test-suite clones of `cursor/plugins` from github.com (10 tests, `scripts/vendor-skills.py fetch_pinned`) turned main red on a 429 rate limit (#1369, run 43451823368).

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
- A new `factory_plugins/<name>` package must be listed in `pyproject.toml` `packages`, or the wheel lacks it and its CLI command resolves to None (#1255, #1128).
- The GitHub gate store reads only label state stores, so a github-issues repository beside a YouTrack one cannot read stage tag stores (#1298, `factory_plugins/github/gate.py:535`).
- Doctor reports of `factory validate` crashing repeat (#1096, #1097, #1248, #1267) with no traceback; on main `factory validate --team factory/tests/fixtures/team` prints `factory: ok`. Ask for the probe's engine version and traceback before you plan work (#1267).
- `deploy.py` variants, the `agent_prompt` old branch and `node_spec` tiers still serve `local/surface.py` and three test modules; delete them together with #682 (#681, `factory/factory_plugins/local/surface.py:90`).
- Engine gaps found on v2 teams: `gate.sweep`, `definition.plan` and `join` read v1 node names and tiered labels, so v2 plans nothing and counts no fix rounds; `gate.apply` refuses a failed check only for outcome `done`, not `done-low`/`done-high`; `config.load()` gives v2 roles only a tier, so `factory run --local` raises `KeyError 'luna'`; v2 `validate` rejects unknown keys only in `tracker` (#1394, `factory/definition.py:1340`, `factory/gate.py:1160`, `factory/gate.py:853`, `factory/config.py`).
- The GitHub gate cannot claim a once-comment atomically; the lock is per host only (#1373, `factory/factory_plugins/github/gate.py _once_lock`).
- `air deploy` assumes `get_environment` returns `projectId`; the contract snapshot does not show it (#1387, `factory/factory_plugins/air/deploy.py missing_project_environments`).
- A cleanup ticket called "mostly deletions" still needed test porting: `fixtures/team` and `engine/nodes.yaml` underlie about 12 test modules; estimate the test porting, not the file count (#682, `sed s#fixtures/team#fixtures/slop#` gives 45 failures).
- A ticket that needs a local path outside the Air checkouts (here an `offline-eval-factory` install on a Mac) cannot be built by the Air developer; split it or mark it local-only (#1370).
