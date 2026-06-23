#!/usr/bin/env ruby
# frozen_string_literal: true

# Merge-mode shim — SessionStart hook.
#
# Fires automatically on session start, resume, and /clear (Claude Code's
# SessionStart matchers: startup | resume | clear). Injects a directive that
# tells the model to ask the user how to handle merging changes from the
# session, before doing anything else.
#
# A hook cannot literally force a tool call, but SessionStart additionalContext
# is injected deterministically on every relevant event — so the instruction
# always arrives, which is far more durable than relying on a static SKILL.md.

require "json"

# Builds and emits the SessionStart hook payload. One reason to change: the
# merge-mode directive or the hook output contract.
class MergeModeHook
  EVENT = "SessionStart"

  DIRECTIVE = <<~TEXT.strip
    [pst] Before responding to anything else, call the AskUserQuestion tool to set the session's MERGE MODE.

    Question: "How should I handle changes from this session?"
    Header: "Merge mode"
    Options:
      1. "Local only" — No push, no PR. Changes stay on disk.
      2. "Merge ready" — Push branch, open PR, ensure CI is green. The user merges manually.
      3. "Admin bypass" — Push branch, open PR, then squash-merge via `gh pr merge --squash --admin` once CI is green. No other quality passes.

    After the user answers, acknowledge the choice in one line, then proceed. Apply the chosen mode for the rest of the session unless /pst changes it.
  TEXT

  def payload
    {
      hookSpecificOutput: {
        hookEventName: EVENT,
        additionalContext: DIRECTIVE
      }
    }
  end

  def emit(io = $stdout)
    io.puts(JSON.generate(payload))
  end
end

MergeModeHook.new.emit if __FILE__ == $PROGRAM_NAME
