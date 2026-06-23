#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "rbconfig"

class Paths
  def initialize(repo:, home:)
    @repo = repo
    @home = home
  end

  def scripts      = File.join(@repo, "scripts")
  def skill_source = File.join(@repo, "skills", "pst", "SKILL.md")
  def bin          = File.join(@home, ".claude", "pst", "bin")
  def skills       = File.join(@home, ".claude", "skills", "pst")
  def settings     = File.join(@home, ".claude", "settings.json")
  def skill_dest   = File.join(skills, "SKILL.md")

  def script_source(name) = File.join(scripts, name)
  def script_dest(name)   = File.join(bin, name)
end

module RubyInterpreter
  def self.path
    resolved = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
    raise "could not resolve a ruby interpreter" unless File.executable?(resolved)

    resolved
  end
end

class SettingsFile
  def initialize(path, managed_dir:)
    @path = path
    @managed_dir = managed_dir
  end

  def wire(events)
    data = load
    hooks = (data["hooks"] ||= {})
    events.each do |event, command|
      section = (hooks[event] ||= [])
      drop_managed_hooks(section)
      section << { "hooks" => [{ "type" => "command", "command" => command }] }
    end
    persist(data)
  end

  def backup_path = "#{@path}.bak"

  private

  def load
    File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
  end

  def drop_managed_hooks(section)
    section.each do |group|
      next unless group.is_a?(Hash) && group["hooks"].is_a?(Array)

      group["hooks"].reject! { |hook| hook["command"].to_s.include?(@managed_dir) }
    end
    section.reject! { |group| group.is_a?(Hash) && (group["hooks"] || []).empty? }
  end

  def persist(data)
    FileUtils.cp(@path, backup_path) if File.exist?(@path)
    tmp = "#{@path}.tmp"
    File.write(tmp, JSON.pretty_generate(data) + "\n")
    File.rename(tmp, @path)
  end
end

class Installer
  HOOKS = {
    "SessionStart"     => "session-start.rb",
    "PostToolUse"      => "merge-mode-record.rb",
    "UserPromptSubmit" => "merge-mode-restate.rb"
  }.freeze

  def initialize(paths:, ruby:)
    @paths = paths
    @ruby = ruby
  end

  def install
    place_hooks
    link_skill
    wire_settings
    report
  end

  private

  def place_hooks
    FileUtils.mkdir_p(@paths.bin)
    HOOKS.each_value do |name|
      dest = @paths.script_dest(name)
      FileUtils.cp(@paths.script_source(name), dest)
      FileUtils.chmod(0o755, dest)
    end
  end

  def link_skill
    FileUtils.mkdir_p(@paths.skills)
    FileUtils.ln_sf(@paths.skill_source, @paths.skill_dest)
  end

  def wire_settings
    @settings_file = SettingsFile.new(@paths.settings, managed_dir: @paths.bin)
    @settings_file.wire(commands)
  end

  def commands
    HOOKS.map { |event, name| [event, "#{@ruby} #{@paths.script_dest(name)}"] }.to_h
  end

  def report
    puts "merge-mode shim installed:"
    puts "  hooks    -> #{@paths.bin} (#{HOOKS.keys.join(", ")})"
    puts "  skill    -> #{@paths.skill_dest}"
    puts "  settings -> #{@paths.settings} (backup at #{@settings_file.backup_path})"
  end
end

if __FILE__ == $PROGRAM_NAME
  paths = Paths.new(repo: __dir__, home: Dir.home)
  Installer.new(paths: paths, ruby: RubyInterpreter.path).install
end
