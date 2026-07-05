---
name: pst:code-review
description: Review a pull request, branch, file set, or feature description for correctness bugs and refactor opportunities. Verifies each candidate finding in an isolated worktree before posting only the ones that survive, so PR feedback is curated instead of noisy.
---

# PST Code Review

Trigger: `/pst:code-review <scope>`.

Question: does this finding survive an isolated attempt to refute it? A
plausible-sounding comment that was never checked against the real code is the
AI slop this skill exists to filter out. Silence beats a wrong or nitpicky
comment; when in doubt, drop it.

## Scope

Accepted forms, resolved in this order:

1. A PR URL or `owner/repo#123` / bare `#123` (current repo when owner/repo is
   omitted). Resolve via `pull_request_read`.
2. A branch or ref: diff against the default branch.
3. An explicit file list or glob.
4. A semantic description of a feature ("the auth refactor", "the caching
   layer"): locate the files with Explore/Grep, list what was found, and
   confirm the set before reviewing.
5. The whole repository: only on explicit request. State the file count
   before proceeding, given the cost; the workflow in step 2 shards it
   automatically once that count crosses its threshold.

If scope is ambiguous, ask which PR or files are meant. Do not guess.

## Workflow

1. **Resolve scope to files, a repo, and a head commit.** PR: `pull_request_
   read` with `get_diff`, `get_files`, and `get_comments`/`get_review_
   comments` so ground already covered by a human or a prior review is not
   re-flagged; if the PR's head is not already fetched locally, fetch it
   (e.g. `git fetch origin pull/<N>/head`) so it resolves to a real local
   commit. Everything else: `git diff`, `git show`, or plain reads. Record
   `repoPath` (the local clone's absolute path) and `headSha` (the commit
   whose code is under review, i.e. the PR's head or the branch tip, never
   the merge-base) alongside the file list; step 2 needs a real commit
   worktrees can check out, not a moving branch name.
2. **Run the review workflow.** Call `Workflow` with the script under
   Review workflow script and `args: { files, repoPath, headSha, cap }`
   (`cap` optional, defaults to 15). Invoking this skill is what authorizes
   the `Workflow` call, so no separate orchestration opt-in is needed. The
   script shards a large file set into semantic sections, finds candidates
   per shard (folding the rubric and general lenses into one pass, or
   splitting the rubric lens onto its own cheap-tier call only when a
   shard's file count makes that split a real, separable job), verifies
   every candidate by trying to refute it inside its own throwaway `git
   worktree` of `repoPath` at `headSha`, and independently rechecks every
   P1 before it is allowed to keep that tier. It returns `{ shards, posted,
   droppedForVolume }`; `posted` is the deduped, ranked, capped finding
   list. On a repeat run against the same scope, pass the `scriptPath` the
   first call returned instead of resending `script`, so unchanged stages
   replay from cache.

   `repoPath` matters because the `Agent` tool's `isolation: "worktree"`
   option only ever isolates the *session's own primary repository* (where
   the session started), not an arbitrary path named in a script's args;
   passing it something else silently isolates the wrong tree. When
   `repoPath` is that primary repository this is harmless, but it is not
   what makes verification correct, so the script does not rely on it: every
   Verify and Recheck P1 call is told to create and clean up its own `git
   worktree add`/`remove` of `repoPath` explicitly, which works the same way
   whether `repoPath` is the session's own repo or a separate clone.
3. **Report before posting.** Show `posted` (`path:line`, tier, one line
   each) plus the shard summary and `droppedForVolume` count, and ask
   whether to post. Skip the ask only when the invocation said to post
   automatically.
4. **Post.**
   - PR scope: `pull_request_review_write` with `create` (no `event`, so it
     stays pending), then `add_comment_to_pending_review` per finding in
     `posted`, anchored to `path`/`line`, then `submit_pending` with
     `event: "COMMENT"`. Never `REQUEST_CHANGES` or `APPROVE` unless asked.
   - Non-PR scope: there is nothing to post to. The curated report to the
     user is the deliverable.

## Review workflow script

Pass this verbatim as `Workflow`'s `script`. It owns everything the old
per-step `Agent` instructions used to describe by hand: sharding, model
tiers, background/parallel dispatch, the P1 double-check, and the
dedupe/rank/cap that turns raw candidates into `posted`. Comment text and
the actual PR post stay outside it (step 3 and 4 above), since posting
needs a human ask this script has no tool to make.

```js
export const meta = {
  name: "pst-code-review-scope",
  description: "Shard, find, worktree-verify, and rank code review findings for one scope",
  phases: [
    { title: "Shard" },
    { title: "Find" },
    { title: "Verify" },
    { title: "Recheck P1", model: "opus" }
  ]
}

const SHARD_SCHEMA = {
  type: "object",
  properties: {
    shards: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          rationale: { type: "string" },
          files: { type: "array", items: { type: "string" } }
        },
        required: [ "name", "files" ]
      }
    }
  },
  required: [ "shards" ]
}

const CANDIDATES_SCHEMA = {
  type: "object",
  properties: {
    candidates: {
      type: "array",
      items: {
        type: "object",
        properties: {
          file: { type: "string" },
          line: { type: "number" },
          scenario: { type: "string" },
          source: { type: "string" }
        },
        required: [ "file", "line", "scenario" ]
      }
    }
  },
  required: [ "candidates" ]
}

const VERDICT_SCHEMA = {
  type: "object",
  properties: {
    reproduced: { type: "boolean" },
    evidence: { type: "string" },
    tier: { type: "string", enum: [ "P1", "P2", "P3" ] },
    suggestion: { type: "string" }
  },
  required: [ "reproduced", "evidence", "tier" ]
}

const RECHECK_SCHEMA = {
  type: "object",
  properties: {
    reproduced: { type: "boolean" },
    evidence: { type: "string" }
  },
  required: [ "reproduced", "evidence" ]
}

// Some hosts hand this script a JSON-encoded string instead of the parsed
// object the Workflow contract promises; tolerate both.
const scope = typeof args === "string" ? JSON.parse(args) : args

const files = scope.files
const repoPath = scope.repoPath
const headSha = scope.headSha
const shardThreshold = scope.shardThreshold ?? 40
const rubricThreshold = scope.rubricThreshold ?? 25
const cap = scope.cap ?? 15

// isolation: "worktree" on the Agent calls below only isolates this
// session's own primary repo, not repoPath, so it is not used here.
// Verify and Recheck P1 manage their own git worktree of repoPath instead,
// which is correct whether repoPath is the primary repo or a separate one.
function worktreeSetup() {
  return "Before doing anything else, create a throwaway checkout: run " +
    "`d=$(mktemp -d) && git -C " + repoPath + " worktree add \"$d\" " + headSha +
    " && echo \"$d\"`, then do every reproduction step inside that echoed path, " +
    "never in " + repoPath + " itself. Remove it when done with `git -C " + repoPath +
    " worktree remove \"<path>\" --force`. "
}

phase("Shard")
let shards
if (files.length <= shardThreshold) {
  shards = [ { name: "scope", files: files, rationale: "small enough for one pass" } ]
} else {
  const map = await agent(
    "Map this file list into coherent semantic sections a reviewer would treat as one unit " +
    "(e.g. auth, billing, the caching layer), not directory splits. Give each section a short " +
    "name, a one-line rationale, and its file list.\n\nFiles:\n" + files.join("\n"),
    { model: "opus", phase: "Shard", schema: SHARD_SCHEMA }
  )
  shards = map.shards
}
log(shards.length + " shard(s): " + shards.map((s) => s.name + " (" + s.files.length + ")").join(", "))

const shardResults = await pipeline(
  shards,
  async (shard) => {
    if (shard.files.length <= rubricThreshold) {
      const found = await agent(
        "Review these files for correctness bugs, security issues, missing or wrong test " +
        "coverage, and refactor opportunities. Apply the matched skill rubrics from " +
        "`ruby ~/.claude/pst/bin/skill_route.rb <files>` where they cover a file, plus general " +
        "judgment where they do not. Every candidate needs a concrete failure scenario, not a " +
        "vague quality note.\n\nFiles:\n" + shard.files.join("\n"),
        { phase: "Find", label: shard.name, schema: CANDIDATES_SCHEMA }
      )
      return { shard: shard, candidates: found.candidates }
    }
    const lensResults = await parallel([
      () => agent(
        "Route these files with `ruby ~/.claude/pst/bin/skill_route.rb <files>` and apply " +
        "each matched skill principles verbatim. Files:\n" + shard.files.join("\n"),
        { model: "haiku", phase: "Find", label: shard.name + ":rubric", schema: CANDIDATES_SCHEMA }
      ),
      () => agent(
        "General review pass, unscoped to any named rubric: correctness bugs, security, " +
        "API and contract breaks, missing or wrong test coverage, performance. Files:\n" +
        shard.files.join("\n"),
        { phase: "Find", label: shard.name + ":general", schema: CANDIDATES_SCHEMA }
      )
    ])
    const candidates = lensResults.filter(Boolean).flatMap((r) => r.candidates)
    return { shard: shard, candidates: candidates }
  },
  async (found) => {
    const seenKeys = new Set()
    const uniqueCandidates = found.candidates.filter((c) => {
      const key = c.file + ":" + c.line
      if (seenKeys.has(key)) return false
      seenKeys.add(key)
      return true
    })
    const verified = await parallel(uniqueCandidates.map((c) => () =>
      agent(
        worktreeSetup() +
        "Try to refute this finding by reproducing it against the real code: " + c.file + ":" +
        c.line + " - " + c.scenario + ". Reproduce with a failing test, an actual invocation, " +
        "or by applying a refactor and confirming behavior holds; do not just re-read the code " +
        "and agree.",
        { phase: "Verify", label: c.file + ":" + c.line, schema: VERDICT_SCHEMA }
      ).then((v) => (v ? { ...c, ...v } : null))
    ))
    const survivors = verified.filter(Boolean).filter((f) => f.reproduced)
    return { shard: found.shard, findings: survivors }
  },
  async (verified) => {
    const p1s = verified.findings.filter((f) => f.tier === "P1")
    const rechecks = await parallel(p1s.map((f) => () =>
      agent(
        worktreeSetup() +
        "Independently try to reproduce this finding with no prior context: " + f.file + ":" +
        f.line + " - " + f.scenario,
        { model: "opus", phase: "Recheck P1", label: f.file + ":" + f.line, schema: RECHECK_SCHEMA }
      ).then((r) => ({ key: f.file + ":" + f.line, confirmed: Boolean(r && r.reproduced) }))
    ))
    const confirmedKeys = new Set(rechecks.filter((r) => r.confirmed).map((r) => r.key))
    const findings = verified.findings.map((f) => {
      if (f.tier !== "P1") return f
      const key = f.file + ":" + f.line
      return confirmedKeys.has(key) ? f : { ...f, tier: "P2", suggestion: undefined }
    })
    return { shard: verified.shard, findings: findings }
  }
)

const all = shardResults.filter(Boolean).flatMap((r) => r.findings)
const byKey = new Map()
for (const f of all) {
  const key = f.file + ":" + f.line
  if (!byKey.has(key)) byKey.set(key, f)
}
const rank = { P1: 0, P2: 1, P3: 2 }
const eligible = [ ...byKey.values() ].filter((f) => f.tier !== "P3" || f.suggestion)
const ranked = eligible.sort((a, b) => rank[a.tier] - rank[b.tier])

return {
  shards: shards.map((s) => ({ name: s.name, files: s.files.length })),
  posted: ranked.slice(0, cap),
  droppedForVolume: Math.max(0, ranked.length - cap)
}
```

## Model tiers

The script picks a model per call so the cheap tier is used only where the
work is itself high-volume and mechanically separable, never as a reflex:

| Call | Model | Why |
|---|---|---|
| Shard mapping | `opus` | One call gates the whole run; needs real semantic boundaries, not directory splits |
| Find, folded (small shard) | inherit | One pass covering both lenses; no checklist-only slice big enough to split out |
| Find, rubric split (large shard) | `haiku` | Applies an already-written skill's rules across enough files to be its own job |
| Find, general split (large shard) | inherit | No checklist; needs full reasoning to name what a rubric cannot |
| Verify | inherit | Must write and run a real repro or refactor correctly |
| Recheck P1 | `opus` | Low volume, highest stakes: gates a red, auto-apply-diff finding |

## Priority

Assign a tier from what the Verify stage actually proved, never from how
severe it sounds:

| Tier | Bar | Requires |
|---|---|---|
| P1 (red) | Confirmed break: crash, wrong output, security hole, data loss | A reproduction, plus Recheck P1 agreement |
| P2 (yellow) | Confirmed but bounded: real bug/smell needing specific input, config, or scale; or a refactor with verified payoff | A reproduction from Verify |
| P3 (green) | Real but low blast radius, and only worth interrupting for because the fix is a one-line, unambiguous diff | A reproduction from Verify, and a suggestion block (see below) |

Drop anything that only clears the P3 bar and has no suggestion block; it is
noise, not feedback. Prefix each posted comment with its tier (`**P1**`,
`**P2**`, `**P3**`).

## Posting style

One finding, one comment: tier prefix, the concrete failure scenario, then
the fix. Hard cap 640 characters per comment body; target roughly 240. No
summary of the summary, no praise, no restating the diff. Apply
`pst:ai-slop`'s punctuation and tone rules to anything written into a
comment body. Before calling `add_comment_to_pending_review`, check the
body's length; if it is over budget, cut prose before cutting the concrete
scenario, and drop the suggestion block if it still does not fit rather
than splitting into a second comment.

Add a GitHub suggestion block only when the fix is mechanical and
unambiguous from the finding alone (a rename, a null check, an off-by-one,
a dead branch, the exact rubric move a matched skill names) and touches
only the lines already in the diff:

    ```suggestion
    <replacement line(s)>
    ```

Never suggest a diff for anything needing a judgment call, multiple files,
or unclear intent; post the finding without one instead.
