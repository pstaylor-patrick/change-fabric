---
name: pst
description: Activate Patrick's engineering doctrine as hard, standing rules for the REST of this session — portable to whatever repo or area you're in. Eager background-agent swarms in isolated worktrees, mandatory adversarial review, root-cause CI fixes, local-k8s quality gate before any remote deploy, and squash-merge-only-on-green-CI. Invoke when the user types /pst, or says "enter pst mode", "apply my dev preferences here", "bring my doctrine to this repo".
argument-hint: ""
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion, Skill
---

# /pst — Patrick's engineering doctrine (session-wide mode)

Invoking this skill installs the rules below as **standing preferences for the
remainder of the session**. They are not a one-shot task list — treat them as a
hard policy layered on top of everything else, re-applied to every subsequent
request until the session ends or the user explicitly overrides a rule.

When invoked, do the following immediately:

1. Run the **git identity guard** (Rule 8) once, up front.
2. Acknowledge that PST mode is active with a short confirmation listing the
   gates now in force (one line each), then continue with whatever the user
   actually asked for — now governed by these rules.

For the rest of the session, silently honor every rule below. Do not re-announce
the full doctrine on each turn; just comply. Surface a rule explicitly only when
it changes what you're about to do (e.g. "CI is red — fixing root cause before I
can squash-merge").

---

## The doctrine

### 1. Eager background-agent swarms — keep the foreground clean
Default to offloading heavy lifting to **swarms of background agents**. The
foreground/orchestrator (you, on Opus) plans, decomposes, and validates; it does
not do the grunt work. Background sub-agents run on **Sonnet**.

- Decompose work into independent units and fan them out **in parallel** via
  background agents rather than doing them serially in the foreground.
- Reach for `/pst:sweep` and `/pst:ready` (both already parallelize across PRs
  via background agents in isolated worktrees) and the harness's workflow/agent
  fan-out tooling for structured parallelism. Use `/pst:auto` as the
  high-autonomy rough-prompt → PR orchestrator.
- Only keep work in the foreground when it genuinely needs the orchestrator's
  judgment (planning, validation, user-facing decisions).

### 2. Isolated git worktrees — eagerly, to avoid races
Any agent that **mutates files** runs in its own **isolated git worktree**, so
concurrent agents never collide in the same tree. Prefer worktree isolation for
agent/workflow work that writes. Read-only exploration does not need a worktree.

### 3. Continuous tidying — prompt, don't auto-destroy
Continuously watch for refactor / cleanup opportunities as you work.
- Specifically: when you notice **orphaned or stale git worktrees** (e.g. from
  `git worktree list` — worktrees whose branch is merged/gone or that are no
  longer in use), **prompt the user** whether to prune them. Never auto-prune.
- Surface other tidy-ups (dead code, duplicated logic, drifted config) as
  suggestions; act on them only with a green light unless trivial and in-scope.

### 4. PR + squash-merge workflow — green CI is a hard precondition
Strongly prefer: create a **PR**, then merge to `main` via **admin bypass +
squash merge**. Squash is the default merge strategy unless the user says
otherwise.
- **NEVER squash-merge unless CI is green.** No exceptions without explicit
  per-merge user override.
- Use `/pst:ready` to drive a PR to merge-ready (rebase → await CI → auto-fix →
  resolve threads → re-verify) and `/pst:rebase` for rebasing onto base.

### 5. CI fixes — root cause, never band-aids
Do whatever it takes to get CI green, but prioritize **systemic, root-cause
fixes** over short-term band-aids that merely mask a deeper issue (skipping
tests, loosening thresholds, retry-until-green, swallowing errors). If a quick
fix is the only option under time pressure, say so explicitly and flag the debt.

### 6. Mandatory adversarial review before merge — and implement the fixes
At least **one round of adversarial review** must run against a PR **before it
merges**.
- Use `/pst:adversarial-review` and/or `/pst:code-review` (and a cluster QA audit
  for cluster apps, which includes a multi-agent adversarial review).
- When a review round produces findings, **implement the fixes** — do not just
  report them. Re-review until clean. Only then is the PR eligible to merge
  (and still only on green CI per Rule 4).

### 7. Local Kubernetes quality gate before any remote deploy
Remote/deployed environments (e.g. AWS, staging, prod) are **quality-gated on
local Kubernetes validation first**.

- If the app is configured in the **local k3s private cloud** as a shared
  local-dev resource, then after a merge ensure it **deploys successfully
  there**, and run **adversarial validations with real end-to-end testing** in
  the local cluster **before** anything promotes to a higher/remote environment.
- Use the cluster QA-audit capability (provisions an isolated per-PR copy
  in-cluster and runs Playwright E2E + a11y + ZAP + load + adversarial review)
  and the private-cloud deploy capability for the deploy.
- **Timing depends on the repo's GitHub Actions config.** For some repos the
  remote deploy fires automatically on merge — in those, do the local k8s deploy
  + validation **manually via the blue-green deployment capability BEFORE merging
  the PR**, so the remote env is never reached before local validation passes.
  Inspect `.github/workflows/` to decide: if merge → remote is automatic, gate
  pre-merge; otherwise gate post-merge but pre-promotion.

### 8. Git identity — anonymized GitHub no-reply on every commit
All commits (foreground AND every background agent) use Patrick's GitHub
anonymized no-reply email. Run this guard once when the skill is invoked and
ensure background agents inherit it:

```bash
EXPECTED="1963845+pstaylor-patrick@users.noreply.github.com"
CURRENT="$(git config --global user.email 2>/dev/null || true)"
if [ "$CURRENT" != "$EXPECTED" ]; then
  git config --global user.email "$EXPECTED"
  echo "git identity: set global user.email to $EXPECTED (was: ${CURRENT:-unset})"
else
  echo "git identity: OK ($EXPECTED)"
fi
```

When spawning background agents that commit, instruct them to use this same
email (it's the global default, so it's inherited unless a repo-local override
exists — check `git config user.email` inside a repo if a commit shows the wrong
author).

---

## Usage

```
/pst            # activate PST mode for the rest of this session
```

Once active, just keep working — every subsequent request is governed by the
doctrine above until the session ends or the user overrides a specific rule.

## Order of operations for a typical change under PST mode

1. Plan in the foreground (Opus). Fan implementation out to background Sonnet
   agents in **isolated worktrees** (Rules 1, 2).
2. Open a **PR** (Rule 4).
3. Get **CI green** with root-cause fixes (Rules 4, 5).
4. Run **adversarial review** and **implement** the fixes; re-review to clean
   (Rule 6).
5. If a cluster app whose CI auto-deploys to remote on merge: do the **local
   k8s blue-green deploy + adversarial E2E validation BEFORE merge** (Rule 7).
6. **Squash-merge via admin bypass — only on green CI** (Rule 4).
7. If not gated pre-merge: **local k8s deploy + adversarial E2E validation
   before any remote promotion** (Rule 7).
8. Offer to **prune orphaned worktrees** created along the way (Rule 3).
