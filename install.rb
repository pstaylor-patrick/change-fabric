#!/usr/bin/env ruby
# frozen_string_literal: true

# Merge-mode shim installer.
#
# Durable + idempotent:
#   1. Copies hook scripts into ~/.claude/pst/bin/ (survives this repo moving
#      or being deleted — settings.json points at the copy, not the repo).
#   2. Symlinks SKILL.md for the /pst manual re-invoke path.
#   3. Patches ~/.claude/settings.json to wire the SessionStart hook, leaving
#      every other configured hook untouched.

require "json"
require "fileutils"
require "rbconfig"

# Knows where every install artifact lives. One reason to change: the on-disk
# layout of the repo or of ~/.claude.
class Paths
  def initialize(repo:, home:)
    @repo = repo
    @home = home
  end

  def hook_source  = File.join(@repo, "scripts", "session-start.rb")
  def skill_source = File.join(@repo, "skills", "pst", "SKILL.md")
  def bin          = File.join(@home, ".claude", "pst", "bin")
  def skills       = File.join(@home, ".claude", "skills", "pst")
  def settings     = File.join(@home, ".claude", "settings.json")
  def hook_dest    = File.join(bin, "session-start.rb")
  def skill_dest   = File.join(skills, "SKILL.md")
end

# Resolves the ruby interpreter the hook command should invoke. Prefers the one
# running this installer, so the hook uses the same ruby the user installed with.
module RubyInterpreter
  def self.path
    resolved = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
    raise "could not resolve a ruby interpreter" unless File.executable?(resolved)

    resolved
  end
end

# Owns the SessionStart section of settings.json. Tell it to wire a command and
# it loads, edits, backs up, and writes atomically — callers never touch the JSON.
class SettingsFile
  def initialize(path, managed_dir:)
    @path = path
    @managed_dir = managed_dir
  end

  def wire_session_start(command)
    data = load
    section = (data["hooks"] ||= {})["SessionStart"] ||= []
    drop_managed_hooks(section)
    section << { "hooks" => [{ "type" => "command", "command" => command }] }
    persist(data)
  end

  private

  def load
    File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
  end

  # Remove any hook whose command points into our managed bin dir (prior installs
  # under any script name), then prune emptied groups. Other tools' hooks survive.
  def drop_managed_hooks(section)
    section.each do |group|
      next unless group.is_a?(Hash) && group["hooks"].is_a?(Array)

      group["hooks"].reject! { |hook| hook["command"].to_s.include?(@managed_dir) }
    end
    section.reject! { |group| group.is_a?(Hash) && (group["hooks"] || []).empty? }
  end

  # Back up, then write via temp file + rename so an interrupt can't corrupt it.
  def persist(data)
    FileUtils.cp(@path, "#{@path}.bak") if File.exist?(@path)
    tmp = "#{@path}.tmp"
    File.write(tmp, JSON.pretty_generate(data) + "\n")
    File.rename(tmp, @path)
  end
end

# Orchestrates the install steps and reports the result.
class Installer
  def initialize(paths:, ruby:)
    @paths = paths
    @ruby = ruby
  end

  def install
    place_hook
    link_skill
    wire_settings
    report
  end

  private

  def place_hook
    FileUtils.mkdir_p(@paths.bin)
    FileUtils.cp(@paths.hook_source, @paths.hook_dest)
    FileUtils.chmod(0o755, @paths.hook_dest)
  end

  def link_skill
    FileUtils.mkdir_p(@paths.skills)
    FileUtils.ln_sf(@paths.skill_source, @paths.skill_dest)
  end

  def wire_settings
    SettingsFile.new(@paths.settings, managed_dir: @paths.bin)
                .wire_session_start("#{@ruby} #{@paths.hook_dest}")
  end

  def report
    puts "merge-mode shim installed:"
    puts "  hook script -> #{@paths.hook_dest}"
    puts "  skill       -> #{@paths.skill_dest}"
    puts "  settings    -> #{@paths.settings} (SessionStart wired; backup at #{@paths.settings}.bak)"
  end
end

if __FILE__ == $PROGRAM_NAME
  paths = Paths.new(repo: __dir__, home: Dir.home)
  Installer.new(paths: paths, ruby: RubyInterpreter.path).install
end
