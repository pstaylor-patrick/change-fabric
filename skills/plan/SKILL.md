---
name: cf:plan
description: Turns a described goal into a landed planning pair (a detailed plan.md and a goal.md capped at 4000 characters) under the user's plans tree, researched and written by background Opus agents, then emits a ready-to-paste handoff prompt for a separate session to execute the plan with the Workflow tool. It plans only; it never implements the plan or runs the Workflow itself.
---

# CF Plan

Trigger: `/cf:plan <goal description>` (optionally `--area <name>`).

Question: is there a plan on disk detailed enough that a separate agent, with
none of this session's context, could turn it straight into real work?

## What it produces

Two files, always both, in one directory:

- `<root>/<area>/plans/<slug>/plan.md` - the full technical plan. No length
  cap. Execution-ready: named files, named commands, ordered phases.
- `<root>/<area>/plans/<slug>/goal.md` - the short vision statement. What done
  looks like and why it matters, with implementation detail deliberately left
  out. **Hard cap 4000 characters**, enforced mechanically.

`<root>` is `$CF_PLANS_ROOT`, defaulting to `~/1-areas/pst`.

Then one more thing, to the user only: a fenced handoff prompt to paste into a
fresh session that will execute the plan.

## Reference files

- `reference/research-prompt.md`: the prompt given to the background agents.
  Read it and fill its placeholders; do not paraphrase it.
- `reference/handoff-prompt.md`: the handoff template emitted at step 8. Read
  it and fill its placeholders verbatim.

## Boundaries

- This skill writes only under `<root>`. It never edits a repo, never commits,
  never pushes. The session's cf merge mode is therefore irrelevant to it.
- It never calls `Workflow`. Executing the plan is a separate session's job,
  started by the user pasting the step-8 prompt.
- `cf:ctx` and this skill do not overlap: `.ctx` holds small durable notes in
  the shim store keyed by cwd; `cf:plan` writes large documents in the user's
  own areas tree. Step 7 links the two with a one-line pointer doc.

## Workflow

1. **Resolve the destination.** Derive a 2 to 5 word kebab slug from the goal.
   Then run:

   ```bash
   ruby ~/.claude/cf/bin/plan_paths.rb resolve --slug <slug> [--area <area>]
   ```

   It prints JSON: `root`, `area`, `area_dir`, `area_exists`, `slug`,
   `plan_dir`, `plan_dir_exists`, `plan_md`, `goal_md`, `suggested_slug`,
   `siblings`. Use `--area` only when the invocation named one.

2. **Ask only if you must.** At most one `AskUserQuestion` in the whole run,
   and only when `area_exists` is false or `plan_dir_exists` is true.
   - New area: confirm the area name before creating a new top-level
     directory. Offer the inferred name and the nearest existing sibling.
   - Existing plan directory: offer "extend the existing plan in place" and
     "use `<suggested_slug>`". Never overwrite silently, never delete.
   When both are fine, proceed with no question at all.

3. **Restate and create.** State the goal in two or three sentences, the
   chosen area, slug, and both absolute paths. Then:

   ```bash
   ruby ~/.claude/cf/bin/plan_paths.rb mkdir --area <area> --slug <slug>
   ```

4. **Decide the shape of the research pass.**
   - Default: one agent, which researches and writes both files.
   - Fan out only when the goal splits into three or more genuinely
     independent research questions (different subsystems, different repos,
     different third-party services, or a comparison across distinct
     vendors). Then: at most four parallel research agents, each scoped to one
     question and each told to write no files and return findings in its
     report, plus exactly one synthesis agent afterwards that writes the pair.
   - Never more than four research agents. Never two writers.

5. **Spawn.** Use the `Agent` tool, `subagent_type: general-purpose`,
   `model: opus`, `run_in_background: true`. Build each prompt from
   `reference/research-prompt.md`. Parallel research agents go out in one
   message so they run concurrently. The synthesis agent is spawned after they
   all report, with every finding pasted in verbatim.

6. **Verify what landed.** After the writing agent reports:

   ```bash
   ruby ~/.claude/cf/bin/plan_check.rb <plan_dir>
   ```

   It fails on a missing or empty file, a `goal.md` over 4000 characters, or
   an AI-slop glyph in either file, and prints the character count either way.
   Do not report success until it exits zero.

   On failure, `SendMessage` the writing agent with the checker's exact output
   and have it fix and re-run the checker. Up to two rounds. If `goal.md` is
   still over cap after that, trim it yourself (cut implementation detail,
   which belongs in `plan.md`) and say so in the final report.

7. **Record a pointer.** One short `active`-class `.ctx` doc so a later
   session finds this plan:

   ```bash
   printf '%s' "Plan and goal for <slug>: <plan_dir>" | \
     ruby ~/.claude/cf/bin/ctx_store.rb capture \
       --name plan-<slug> --class active \
       --desc "Planning pair for <one-line goal>, in flight."
   ```

8. **Emit the handoff.** Fill `reference/handoff-prompt.md` and print it as the
   final message, in one fenced block, ready to copy. Say plainly that this
   skill has not run anything and that pasting the block into a fresh session
   is what starts execution. Stop here.

## Failure modes

- Ambiguous or one-line goal with nothing to research: say so and ask for the
  missing detail rather than spawning an agent to guess.
- A research agent returns nothing useful: report which question went
  unanswered and let the synthesis agent record it in `plan.md` as an open
  question. Do not fabricate the answer.
- `plan_check.rb` still failing after two trim rounds: handled inline at step
  6.
- `plan_paths.rb` cannot resolve an area (cwd outside any project, no
  `--area`): ask for the area explicitly. That is the one extra question this
  case earns.
- The writing agent errors or never reports: say so explicitly and stop. Do
  not silently hand-write the plan yourself.
