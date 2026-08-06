Fill every `{{placeholder}}`, then pass the result as the `Agent` prompt. Use
the research-agent section for a fan-out agent and the writing-agent section
for the agent that lands the files. A single-agent run gets both sections
concatenated.

## Research agent (fan-out only, writes nothing)

```
Research one question in support of a larger plan.

Question: {{sub_question}}
Larger goal: {{goal_description}}
Repo or area: {{repo_path}}

Investigate thoroughly: read the real files, run read-only commands, check how
the thing actually works rather than how it is documented to work. Cite
absolute file paths for anything load-bearing.

Write no files. Return your findings as your report: what is true, what the
options are, what you would recommend and why, and what you could not settle.
Name the open questions explicitly rather than papering over them.
```

## Writing agent (lands the pair)

```
Design a plan for this goal and land two files.

Goal: {{goal_description}}
Repo or area: {{repo_path}}
Plan directory (already created): {{plan_dir}}

{{research_findings_or_empty}}

Write exactly two files.

1. {{plan_dir}}/plan.md - the full technical plan. No length cap. It must be
   detailed enough that a separate agent, with none of your context, can turn
   it directly into real work. That means:
   - the decisions already made, each with a one-line reason, not a list of
     options left open;
   - exact file paths for everything created or edited;
   - exact commands, config, and code where the code is what makes the plan
     unambiguous;
   - how the change is verified (the actual test, build, or check command);
   - a phased rollout, each phase small enough to be one commit or one PR,
     ordered so each phase leaves the tree working;
   - the failure modes and what to do about each.
   Resolve open questions rather than listing them. Where something genuinely
   cannot be settled without the user, say so explicitly and say what you would
   do by default.

2. {{plan_dir}}/goal.md - the short vision statement. What done looks like and
   why it matters. Deliberately no implementation detail: it exists to orient
   a reader in under two minutes.

   HARD CAP: 4000 characters. Before writing it, count the characters of your
   draft. If it is over, trim by cutting implementation detail (that content
   belongs in plan.md), not by compressing prose into abbreviations or
   dropping the "why". Re-count after trimming.

Before you report done, run:

    ruby ~/.claude/cf/bin/plan_check.rb {{plan_dir}}

It must exit zero. If it does not, fix what it names and run it again.

Authored-output rules for both files: no em-dash, no unicode bullet
character (a plain "-" list is fine), no ellipsis character, no smart or curly
quotes. Plain ASCII hyphens and straight quotes only. Write plainly, no
marketing language.

Report back: both absolute paths, goal.md's character count, and a short
summary of the plan's shape.
```
