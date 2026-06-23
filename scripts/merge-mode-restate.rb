#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

class MergeModeStore
  def initialize(session_id)
    @session_id = session_id.to_s
  end

  def mode
    return nil if @session_id.empty?

    path = File.join(Dir.home, ".claude", "pst", "sessions", @session_id, "merge-mode")
    File.exist?(path) ? File.read(path).strip : nil
  end
end

class MergeModeRestate
  EVENT = "UserPromptSubmit"

  def initialize(event)
    @event = event
  end

  def emit(io = $stdout)
    mode = MergeModeStore.new(@event["session_id"]).mode
    return unless mode

    io.puts(JSON.generate(payload(mode)))
  end

  private

  def payload(mode)
    { hookSpecificOutput: { hookEventName: EVENT, additionalContext: context(mode) } }
  end

  def context(mode)
    "[pst] Active merge mode: #{mode}. Honor it for this turn per the /pst rules."
  end
end

if __FILE__ == $PROGRAM_NAME
  raw = $stdin.read
  MergeModeRestate.new(raw.empty? ? {} : JSON.parse(raw)).emit
end
