# Workflow: delivery

The per-ticket loop. `workflows/delivery.yaml` (format 2,
[ADR-0016](https://github.com/zaharchenko-evgeny/slop-factory/blob/main/docs/adr/0016-project-descriptor-and-workflow.md))
defines it as a list of nodes. Each node is a `[factory:<node>]` Air automation. A state, a command, a PR
event or a schedule wakes it. The node runs `factory check`, does its role's work, writes its handoff and runs
`factory apply`. The gate moves the state. The project descriptor (`factory.project.yaml`) names the
repositories, the states and commands with their labels, the models and the checks. The tracker operations are
in the engine's `docs/agents/issue-tracker.md`.

By hand, use the `factory-delivery` skill. It runs one node the same way.

## The ticket's states

Each box is a state, stored as the ticket label `factory:<state>`. Each arrow is one node's outcome, written
as `node · outcome`. Text in `[ ]` is a condition. Text after `/` is what the outcome adds: a command label
that wakes the next node, a comment or a field. A command such as `+implement-{tier}` is the label
`factory:implement-cheap`, `-mid` or `-strong`. Yellow states wait for a person. Dashed states and
arrows marked `off` are disabled in `delivery.yaml`, with their ticket.

```mermaid
stateDiagram-v2
    classDef waiting fill:#fff8e6,stroke:#c90
    classDef final fill:#eef7ee,stroke:#393
    classDef off fill:#f4f4f4,stroke:#999,stroke-dasharray:5 5,color:#777

    state "in-dev" as in_dev
    state "in-review" as in_review
    state "changes-requested" as changes_requested
    state "needs-answers" as needs_answers
    state "not-actionable" as not_actionable

    [*] --> draft
    draft --> triage: human · triage
    draft --> ready: human · ready

    triage --> ready: intake · proceed / set risk, complexity
    triage --> needs_answers: intake · grill / questions as a comment
    triage --> split: intake · split / child tickets
    triage --> not_actionable: intake · not-actionable / reason as a comment
    triage --> investigating: intake · bug (off, #161)

    investigating --> in_dev: investigate · bug (off) / diagnosis
    investigating --> not_actionable: investigate · intended (off)
    investigating --> needs_answers: investigate · cannot-reproduce (off)

    ready --> in_dev: start · started [blockers closed] / +implement-{tier}
    in_dev --> in_dev: implement · error / +implement-{next tier}
    in_dev --> in_review: implement · done / PR opened
    in_dev --> blocked: implement · blocked, failed / reason
    in_dev --> ready: implement · env-broken / wait for main to turn green

    [*] --> in_review: adopt · adopted (off, #160) / set risk

    in_review --> changes_requested: join · changes / +fix-{tier}
    in_review --> approved: join · approved [CI green]

    changes_requested --> in_review: fix · done / +rereview-{focus}
    changes_requested --> in_review: fix · nothing-to-fix / join again
    changes_requested --> in_review: update · resolved
    changes_requested --> changes_requested: update · escalate / +update-{next tier}
    changes_requested --> blocked: fix · blocked
    changes_requested --> blocked: update · unresolvable
    changes_requested --> ready: fix · env-broken / wait for main to turn green

    approved --> in_review: reopen · reopened [push, or CI red]
    approved --> changes_requested: finish · conflict / +update-cheap
    approved --> done: finish · merged [PR merged by merge · merged]

    needs_answers --> triage: finish · answered [ticket comment]
    split --> done: finish · children-done
    split --> blocked: finish · child-blocked

    done --> [*]
    not_actionable --> [*]

    note right of blocked
        notify pings the owner of blocked
        and needs-answers tickets.
        A person sets ready or triage.
    end note

    class draft, blocked, needs_answers waiting
    class done, not_actionable final
    class investigating off
```

A person, the `recover` sweep, the hourly `reconcile` and a merged PR can move a ticket from almost any
state. These arrows would cross the chart above, so this chart draws them from one pseudo-state.

```mermaid
stateDiagram-v2
    state "any state except done" as any
    state "changes-requested" as changes_requested
    state "in-review" as in_review

    any --> triage: human · triage
    any --> ready: human · ready
    any --> done: finish · merged [the ticket's PR merged]
    any --> blocked: recover · blocked [a run died, found by sweep --stale]
    any --> blocked: reconcile · blocked [no outcome twice] / +factory:needs-human
    in_review --> changes_requested: reconcile · conflict [unapproved PR conflicts with main] / +fix-cheap
```

`human` cannot move a `done` ticket. `finish · merged` does not apply to `not-actionable`. `recover` acts
only on `triage`, `ready`, `in-dev`, `in-review`, `changes-requested` and `approved`. `reconcile` acts on
these states and `split`.

## Inside in-review and approved

The PR, not the ticket, carries the CI result (`ci-green`, `ci-red`) and the merge (`pr-merged`). These PR
facts wake the nodes that move the ticket.

```mermaid
flowchart LR
    push["push to the PR"] --> ci["CI in slop-factory"]
    ci -- "+ci-green" --> gate["gate adds +review-{focus}<br/>for each focus the risk requires"]
    gate --> review["review<br/>one run per focus"]
    review -- "approve or changes at the head" --> join
    ci -- "+ci-red" --> join
    join -- "approved" --> approved(["approved"])
    join -- "changes" --> cr(["changes-requested"])
    approved --> merge["merge<br/>[round complete at head, CI green]"]
    ci -- "+ci-green" --> merge
    merge -- "merged" --> merged["PR merged"] --> finish -- "merged" --> done(["done"])
    merge -- "updated: base merged in" --> push
    merge -- "waiting: comment on the PR" --> approved
    push -- "while approved" --> reopen -- "reopened" --> ir(["in-review"])
    ci -- "+ci-red while approved" --> reopen
```

`merge` merges only while `gates.auto_merge.enabled` is true and the ticket's risk is at most
`gates.auto_merge.max_risk`. Otherwise it reports `waiting` with a comment, and a person merges the PR.
`finish` then moves the ticket to `done`.

## Scheduled nodes

Five nodes run on a clock, outside any ticket. Only `reconcile` changes a ticket's state. It does so in
`factory/reconcile.py`, so its outcome in `delivery.yaml` (`reconciled`) declares no state.

```mermaid
flowchart LR
    clock(("clock"))
    clock -- "hourly at :17" --> reconcile
    clock -- "daily 02:00" --> retro
    clock -- "daily 05:00" --> doctor["doctor, doctor-write, doctor-ops"]
    clock -- "Monday 03:00" --> distill

    reconcile -- "a run left no outcome: re-fire its command" --> same(["same state"])
    reconcile -- "second miss: +factory:needs-human" --> blocked(["blocked"])
    reconcile -- "unapproved PR conflicts: +fix-cheap" --> cr(["changes-requested"])
    reconcile -- "waiting state for 24 h: reminder comment" --> same

    retro -- "one entry per ticket done in the last 24 h" --> inbox[["PR to the knowledge-inbox branch"]]
    inbox -. "read by" .-> distill
    distill -- "lessons merged into knowledge/" --> kb[["one PR to main"]]
    doctor -- "a probe fails" --> dt[["ticket: Doctor: {probe} fails"]]
```

| Node | Schedule | Environment | What it does |
|---|---|---|---|
| `reconcile` | `17 * * * *`, hourly | ops | For a ticket in an active state with no outcome after `limits.run_timeout_minutes`, it re-fires the command that wakes the expected node. On a second miss it sets `blocked` and `factory:needs-human`. An unapproved PR that conflicts with main gets `fix-cheap` and `changes-requested`. A waiting ticket with an assignee gets a reminder comment after 24 hours. |
| `retro` | `0 2 * * *`, daily | ops | For each ticket that reached `done` since the last run, it writes one lesson entry to `knowledge.branch` (`knowledge-inbox`) and updates the one open inbox PR. |
| `distill` | `0 3 * * 1`, Mondays | ops | It merges the inbox entries into `knowledge/<repo>/lessons.md` and opens one PR to the default branch. |
| `doctor` | `0 5 * * *`, daily | read | It probes every write, read and tool the gate needs in its environment. A failed probe opens or updates the ticket `Doctor: <probe> fails`. |
| `doctor-write` | `0 5 * * *`, daily | write | The same probes in the `write` environment. |
| `doctor-ops` | `0 5 * * *`, daily | ops | The same probes in the `ops` environment. |

`recover` is a routine too, but a person starts it. It runs `factory sweep --stale` and moves a ticket whose
run died to `blocked`.

## What wakes each node

| Node | Wakes on | Runs when | Role · tier | Environment |
|---|---|---|---|---|
| `human` | a person | actor human | human |  |
| `intake` | state `triage` entered | state triage | router · cheap | read |
| `start` | state `ready` entered | state ready, blockers closed | script | read |
| `investigate` (off, #161) | state `investigating` entered | state investigating | developer · mid | write |
| `implement` | command `implement-<tier>` | state in-dev | developer · cheap/mid/strong | write |
| `adopt` (off, #160) | command `adopt` | state none | router · cheap | read |
| `review` | command `review-<focus>`<br>command `rereview-<focus>` | state in-review, focus required-by-risk, ci green | reviewer · per focus | read |
| `join` | PR review submitted<br>state `ci-red` entered | state in-review, ci green/red | script | read |
| `fix` | command `fix-<tier>` | state changes-requested, round complete, fix-rounds below-cap | developer · cheap/mid/strong | write |
| `update` | command `update-<tier>` | state changes-requested | developer · cheap/mid/strong | write |
| `reopen` | push to the PR<br>state `ci-red` entered | state approved | script | read |
| `merge` | state `approved` entered<br>state `ci-green` entered | state approved, round complete-at-head, ci green | script | read |
| `finish` | state `pr-merged` entered<br>ticket closed<br>state `blocked` entered<br>ticket comment | always | script | read |
| `notify` | state `blocked` entered<br>state `needs-answers` entered | state blocked/needs-answers | script | ops |
| `recover` (manual) | a person | always | script | read |
| `reconcile` | cron `17 * * * *` | always | script | ops |
| `doctor` | cron `0 5 * * *` | always | script | read |
| `doctor-write` | cron `0 5 * * *` | always | script | write |
| `doctor-ops` | cron `0 5 * * *` | always | script | ops |
| `retro` | cron `0 2 * * *` | always | retro · cheap | ops |
| `distill` | cron `0 3 * * 1` | always | distill · mid | ops |

## Input

A tracker ticket in state `triage` or `ready`.

## Handoffs

Each agent step ends with the structured block its role file defines. Steps
pass these blocks, never transcripts. The reviewer always starts fresh.

## External writes

Every push, label change, PR and comment carries the `[factory]` marker and a
`Factory-Run:` trailer. While `gates.confirm_external_writes` is `true`, each
write kind in `gates.confirm_external_writes_scope` is shown and waits for the
user's approval; a declined write stops the run with stage unchanged. Other
writes, including the push of the ticket's own branch, are auto-approved.
The `merge` node merges under `gates.auto_merge`, as described above.
