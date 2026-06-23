#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"

class MergeModeAnswer
  HEADER = "Merge mode"
  KNOWN = ["Local only", "Merge ready", "Admin bypass"].freeze

  def initialize(tool_response)
    @tool_response = tool_response
  end

  def label
    [answers_map, question_list, content_scan].each do |source|
      found = source.call
      return found if found
    end
    nil
  end

  private

  def content_scan
    lambda do
      content = dig("content")
      text = content.is_a?(Array) ? content.map { |p| p.is_a?(Hash) ? p["text"] : p }.join(" ") : @tool_response.to_s
      KNOWN.find { |mode| text.include?(mode) }
    end
  end

  def answers_map
    lambda do
      answers = dig("answers")
      return nil unless answers.is_a?(Hash)

      value = answers.values.first
      normalize(value)
    end
  end

  def question_list
    lambda do
      list = @tool_response.is_a?(Array) ? @tool_response : dig("questions")
      return nil unless list.is_a?(Array)

      entry = list.find { |q| q.is_a?(Hash) && q["header"] == HEADER } || list.first
      normalize(entry && (entry["answer"] || entry["selected"] || entry["chosen"]))
    end
  end

  def dig(key)
    @tool_response.is_a?(Hash) ? @tool_response[key] : nil
  end

  def normalize(value)
    value = value.first if value.is_a?(Array)
    value if value.is_a?(String) && !value.empty?
  end
end

class MergeModeRecord
  def initialize(event)
    @event = event
  end

  def call
    return unless @event["tool_name"] == "AskUserQuestion"

    label = MergeModeAnswer.new(@event["tool_response"]).label
    return unless label

    write(label)
  end

  private

  def write(label)
    dir = File.join(Dir.home, ".claude", "pst", "sessions", session_id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "merge-mode"), label + "\n")
  end

  def session_id
    id = @event["session_id"].to_s
    id.empty? ? "unknown" : id
  end
end

if __FILE__ == $PROGRAM_NAME
  raw = $stdin.read
  MergeModeRecord.new(raw.empty? ? {} : JSON.parse(raw)).call
end
