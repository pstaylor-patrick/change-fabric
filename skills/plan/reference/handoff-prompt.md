Fill every `{{placeholder}}` from this run, then print the fenced block below
as the final message. Do not add commentary inside the fence.

```markdown
Execute the plan at {{plan_path}}.

Read these two files first, in this order:

1. {{goal_path}} - what done looks like and why it matters. Short by design.
2. {{plan_path}} - the full technical plan. This is the source of truth for
   what to build.

Then design and run a `Workflow` that implements the plan.

Workflow expectations:

- Write the script with the standard shape: an `export const meta = {...}`
  header naming the phases, then `agent()`, `pipeline()`, `parallel()`, and
  `phase()` calls. Scope it to the plan, not to a fixed template: phases
  should map to the plan's own phases.
- Fan out with `parallel()` only where the plan's units of work are genuinely
  independent. Fan back in to a single sequential stage wherever two units
  would otherwise write the same files.
- Include a verification pass per phase: the plan names the tests, builds, or
  checks that prove that phase landed. Run them, do not assume them.
- Check in with me at phase boundaries. Report what landed, what is next, and
  anything the plan got wrong, then wait for my go-ahead. Do not run the whole
  workflow end to end unsupervised.

Ground rules:

- The plan is a plan, not a contract. If reality contradicts it, stop and say
  so rather than forcing the plan through. Record the divergence.
- Anything the plan leaves genuinely open is a question for me, not a guess
  for you.
- Honor this session's cf merge mode for anything that pushes, opens a PR, or
  merges.

Repo: {{repo_path}}
Goal in one line: {{goal_one_liner}}
```
