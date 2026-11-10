# Lessons: router

## Estimates and scope

- Size estimates for engine tickets run low (#837 ~400 vs 1327, #860 ~300 vs 450, #862 ~350 vs 539, #74 ~150 vs 254); count tests in the estimate and split such tickets at intake.
- Check ticket acceptance wording against the workflow's state rules before delivery; a scope conflict only a person could resolve reached a fix round (#52).

## Doctor and permission tickets

- A doctor ticket for a permission failure (for example `write:label` with `FACTORY_ISSUES_TOKEN` unset) is not buildable work; reconcile and doctor can open two tickets for one error, so dedupe by error (#1092, #1169, #1170).

## Splits

- A split re-run fails with HTTP 403 after the children exist; skip children that already exist instead of creating them again (#1155).
