# frozen_string_literal: true

require_relative "test_helpers"

class SkillRegistryTest < Minitest::Test
  include SkillFactory

  def setup
    @skills = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@skills)
  end

  def load = SkillRegistry.load(@skills)

  def test_loads_only_skills_with_an_auto_block
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    plain_skill("pst")
    assert_equal [ "ruby" ], load.map(&:name)
  end

  def test_matches_by_extension_case_insensitively
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    skill = load.first
    assert skill.matches?("/proj/lib/foo.RB")
    refute skill.matches?("/proj/README.md")
  end

  def test_matches_by_basename
    skill_dir("ruby", auto: { "extensions" => [ "rb" ], "basenames" => [ "Rakefile" ] })
    assert load.first.matches?("/proj/Rakefile")
  end

  def test_detected_by_marker_file
    skill_dir("ruby", auto: { "detect" => [ "Gemfile", "*.gemspec" ] })
    proj = Dir.mktmpdir
    refute load.first.detected?(proj)
    FileUtils.touch(File.join(proj, "Gemfile"))
    assert load.first.detected?(proj)
  ensure
    FileUtils.remove_entry(proj)
  end

  def test_all_code_matches_code_but_not_prose
    skill_dir("refactoring", auto: { "all_code" => true })
    skill = load.first
    assert skill.matches?("/proj/main.go")
    assert skill.matches?("/proj/app.py")
    refute skill.matches?("/proj/README.md")
    refute skill.matches?("/proj/data.json")
  end

  def test_all_files_matches_every_type
    skill_dir("ai-slop", auto: { "all_files" => true })
    skill = load.first
    assert skill.matches?("/proj/notes.md")
    assert skill.matches?("/proj/app.py")
    assert skill.matches?("/proj/Dockerfile")
    assert skill.matches?("/proj/lib/foo.rb")
  end

  def test_all_code_and_all_files_are_always_detected
    skill_dir("refactoring", auto: { "all_code" => true })
    skill_dir("ai-slop", auto: { "all_files" => true })
    by_name = load.to_h { |s| [ s.name, s ] }
    assert by_name["refactoring"].detected?(Dir.mktmpdir)
    assert by_name["ai-slop"].detected?(Dir.mktmpdir)
  end

  def test_scope_flags_do_not_leak_to_extension_skills
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    refute load.first.matches?("/proj/README.md")
  end

  def test_malformed_skill_is_skipped_not_fatal
    dir = File.join(@skills, "broken")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), "---\n: : not yaml :\n---\nbody")
    assert_equal [], load
  end

  def test_shipped_skills_declare_intended_scope
    by_name = SkillRegistry.load(REPO_SKILLS).to_h { |s| [ s.name, s ] }
    assert by_name["pst:ruby"].matches?("app/models/user.rb")
    assert by_name["pst:refactoring"].all_code?
    assert by_name["pst:refactoring"].matches?("src/main.go")
    refute by_name["pst:refactoring"].matches?("docs/notes.md")
    assert by_name["pst:ai-slop"].all_files?
    assert by_name["pst:ai-slop"].matches?("docs/notes.md")
    assert by_name["pst:ai-slop"].matches?("app/models/user.rb")
  end

  # Builds a throwaway project dir holding the given relative files (parents
  # created, contents empty) and returns its path; the caller removes it.
  def project_with(*relpaths)
    dir = Dir.mktmpdir
    relpaths.each do |rel|
      full = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(full))
      FileUtils.touch(full)
    end
    dir
  end

  def test_paths_glob_matches_nested_basename
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ] })
    skill = load.first
    assert skill.matches?("/p/src/db/schema.ts")
    refute skill.matches?("/p/src/db/schema.prisma")
    refute skill.matches?("/p/schemas.ts")
  end

  def test_paths_glob_directory_recursive
    skill_dir("drizzle", auto: { "paths" => [ "drizzle/**" ] })
    skill = load.first
    assert skill.matches?("/p/drizzle/0000.sql")
    assert skill.matches?("/p/drizzle/meta/snap.json")
    refute skill.matches?("/p/src/x.sql")
  end

  def test_paths_glob_anchored_to_directory
    skill_dir("gha", auto: { "paths" => [ ".github/workflows/*.yml" ] })
    skill = load.first
    assert skill.matches?("/p/.github/workflows/ci.yml")
    assert skill.matches?("/p/pkg/.github/workflows/ci.yml")
    refute skill.matches?("/p/docker-compose.yml")
    refute skill.matches?("/p/.github/workflows/sub/ci.yml")
  end

  def test_paths_glob_extglob_brace
    skill_dir("gha", auto: { "paths" => [ ".github/workflows/*.{yml,yaml}" ] })
    skill = load.first
    assert skill.matches?("/p/.github/workflows/ci.yaml")
    assert skill.matches?("/p/.github/workflows/ci.yml")
  end

  def test_paths_glob_matches_relative_path
    skill_dir("drizzle", auto: { "paths" => [ "src/**/db.ts" ] })
    assert load.first.matches?("src/server/db.ts")
  end

  def test_paths_compose_with_extensions_as_or
    skill_dir("drizzle", auto: { "extensions" => [ "sql" ], "paths" => [ "drizzle/**" ] })
    skill = load.first
    assert skill.matches?("/p/migrations/x.sql")
    assert skill.matches?("/p/drizzle/meta.json")
    refute skill.matches?("/p/app.ts")
  end

  def test_paths_absent_is_backward_compatible
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    refute load.first.matches?("/p/README.md")
  end

  def test_exclude_suppresses_match_when_root_given
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    proj = project_with("prisma/schema.prisma", "src/schema.ts")
    refute skill.matches?(File.join(proj, "src/schema.ts"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_exclude_is_inert_without_root
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    assert load.first.matches?("/p/src/schema.ts")
  end

  def test_exclude_does_not_suppress_when_marker_absent
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    proj = project_with("src/schema.ts")
    assert skill.matches?(File.join(proj, "src/schema.ts"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_detected_honors_exclude
    skill_dir("drizzle", auto: { "detect" => [ "drizzle.config.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    conflict = project_with("drizzle.config.ts", "prisma/schema.prisma")
    clean = project_with("drizzle.config.ts")
    refute skill.detected?(conflict)
    assert skill.detected?(clean)
  ensure
    FileUtils.remove_entry(conflict) if conflict
    FileUtils.remove_entry(clean) if clean
  end

  def test_empty_exclude_leaves_detect_unchanged
    skill_dir("ruby", auto: { "detect" => [ "Gemfile" ] })
    skill = load.first
    proj = project_with("Gemfile")
    assert skill.detected?(proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_shipped_drizzle_fires_on_drizzle_files_only
    by_name = SkillRegistry.load(REPO_SKILLS).to_h { |s| [ s.name, s ] }
    drizzle = by_name["pst:drizzle"]
    assert drizzle.matches?("src/db/schema.ts")
    assert drizzle.matches?("drizzle.config.ts")
    refute drizzle.matches?("src/components/Button.tsx")
  end

  def test_shipped_drizzle_suppressed_in_prisma_project
    drizzle = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:drizzle" }
    prisma = project_with("prisma/schema.prisma", "src/db/schema.ts")
    real = project_with("drizzle.config.ts", "src/db/schema.ts")
    refute drizzle.matches?(File.join(prisma, "src/db/schema.ts"), root: prisma)
    assert drizzle.matches?(File.join(real, "src/db/schema.ts"), root: real)
  ensure
    FileUtils.remove_entry(prisma) if prisma
    FileUtils.remove_entry(real) if real
  end

  def test_shipped_github_actions_fires_on_workflows_only
    gha = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:github-actions" }
    assert gha.matches?(".github/workflows/ci.yml")
    refute gha.matches?("docker-compose.yml")
    refute gha.matches?("config/app.yaml")
  end

  def test_require_gates_match_on_project_marker
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.js" ], "require" => [ "**/drizzle.config.*" ] })
    skill = load.first
    drz = project_with("drizzle.config.ts", "src/db/schema.js")
    plain = project_with("src/db/schema.js")
    assert skill.matches?(File.join(drz, "src/db/schema.js"), root: drz)
    refute skill.matches?(File.join(plain, "src/db/schema.js"), root: plain)
  ensure
    FileUtils.remove_entry(drz) if drz
    FileUtils.remove_entry(plain) if plain
  end

  def test_require_is_inert_without_root
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.js" ], "require" => [ "**/drizzle.config.*" ] })
    assert load.first.matches?("/p/src/db/schema.js")
  end

  def test_require_gates_detection
    skill_dir("drizzle", auto: { "detect" => [ "**/schema.js" ], "require" => [ "**/drizzle.config.*" ] })
    skill = load.first
    drz = project_with("drizzle.config.ts", "src/db/schema.js")
    plain = project_with("src/db/schema.js")
    assert skill.detected?(drz)
    refute skill.detected?(plain)
  ensure
    FileUtils.remove_entry(drz) if drz
    FileUtils.remove_entry(plain) if plain
  end

  def test_empty_require_is_backward_compatible
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    skill = load.first
    proj = project_with("app.rb")
    assert skill.matches?(File.join(proj, "app.rb"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_shipped_drizzle_fires_on_js_schema_in_drizzle_project
    drizzle = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:drizzle" }
    drz = project_with("drizzle.config.js", "src/db/schema.js")
    plain = project_with("src/db/schema.js")
    assert drizzle.matches?(File.join(drz, "src/db/schema.js"), root: drz),
           "fires on a plain-JS Drizzle schema in a Drizzle project"
    refute drizzle.matches?(File.join(plain, "src/db/schema.js"), root: plain),
           "stays off a schema.js in a project with no Drizzle marker"
  ensure
    FileUtils.remove_entry(drz) if drz
    FileUtils.remove_entry(plain) if plain
  end

  # A package.json body listing the given runtime and dev dependencies.
  def pkg(deps: [], dev: [])
    JSON.generate("dependencies" => deps.to_h { |d| [ d, "^1" ] },
                  "devDependencies" => dev.to_h { |d| [ d, "^1" ] })
  end

  # Builds a throwaway project from a { relative_path => contents } map, so a
  # case can give package.json real JSON rather than the empty files project_with
  # touches. Caller removes the dir.
  def project_with_files(files)
    dir = Dir.mktmpdir
    files.each do |rel, body|
      full = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, body)
    end
    dir
  end

  def dep_skill(deps)
    skill_dir("redis", auto: { "extensions" => [ "js" ], "require" => [ { "dep" => deps } ] })
    load.first
  end

  def test_dep_require_satisfied
    skill = dep_skill(%w[redis ioredis])
    proj = project_with_files("package.json" => pkg(deps: %w[ioredis]), "src/cache.js" => "")
    assert skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_unsatisfied
    skill = dep_skill(%w[redis ioredis])
    proj = project_with_files("package.json" => pkg(deps: %w[pg]), "src/cache.js" => "")
    refute skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_unions_nested_package_json
    skill = dep_skill(%w[redis])
    proj = project_with_files("package.json" => pkg(deps: %w[turbo]),
                              "apps/api/package.json" => pkg(deps: %w[redis]),
                              "apps/api/src/cache.js" => "")
    assert skill.matches?(File.join(proj, "apps/api/src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_counts_dev_dependencies
    skill = dep_skill(%w[redis])
    proj = project_with_files("package.json" => pkg(dev: %w[redis]), "src/cache.js" => "")
    assert skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_fails_open_on_unparseable_only
    skill = dep_skill(%w[redis])
    proj = project_with_files("package.json" => "{ not json", "src/cache.js" => "")
    assert skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_confident_negative_with_empty_deps
    skill = dep_skill(%w[redis])
    proj = project_with_files("package.json" => pkg(deps: []), "src/cache.js" => "")
    refute skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_dep_require_inert_without_root
    skill = dep_skill(%w[redis])
    assert skill.matches?("/p/src/cache.js")
  end

  def test_dep_require_ignores_node_modules
    skill = dep_skill(%w[redis])
    proj = project_with_files("package.json" => pkg(deps: %w[pg]),
                              "node_modules/redis/package.json" => pkg(deps: %w[redis]),
                              "src/cache.js" => "")
    refute skill.matches?(File.join(proj, "src/cache.js"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_require_mixes_glob_and_dep
    skill_dir("mix", auto: { "extensions" => [ "js" ],
                             "require" => [ "**/legacy.marker", { "dep" => %w[redis] } ] })
    skill = load.first
    by_dep = project_with_files("package.json" => pkg(deps: %w[redis]), "a.js" => "")
    by_glob = project_with_files("package.json" => pkg(deps: %w[pg]), "legacy.marker" => "", "a.js" => "")
    neither = project_with_files("package.json" => pkg(deps: %w[pg]), "a.js" => "")
    assert skill.matches?(File.join(by_dep, "a.js"), root: by_dep)
    assert skill.matches?(File.join(by_glob, "a.js"), root: by_glob)
    refute skill.matches?(File.join(neither, "a.js"), root: neither)
  ensure
    [ by_dep, by_glob, neither ].each { |d| FileUtils.remove_entry(d) if d }
  end

  def test_shipped_pdf_rendering_gates_on_puppeteer_not_pdfkit
    pdf = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:pdf-rendering" }
    pup = project_with_files("package.json" => pkg(deps: %w[puppeteer]), "src/invoice.js" => "")
    kit = project_with_files("package.json" => pkg(deps: %w[pdfkit]), "src/invoice.js" => "")
    assert pdf.matches?(File.join(pup, "src/invoice.js"), root: pup)
    refute pdf.matches?(File.join(kit, "src/invoice.js"), root: kit)
  ensure
    [ pup, kit ].each { |d| FileUtils.remove_entry(d) if d }
  end

  def test_shipped_express_gates_on_express_not_fastify
    exp = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:express-node" }
    e = project_with_files("package.json" => pkg(deps: %w[express]), "src/server.js" => "")
    f = project_with_files("package.json" => pkg(deps: %w[fastify]), "src/server.js" => "")
    assert exp.matches?(File.join(e, "src/server.js"), root: e)
    refute exp.matches?(File.join(f, "src/server.js"), root: f)
  ensure
    [ e, f ].each { |d| FileUtils.remove_entry(d) if d }
  end

  def test_shipped_js_testing_drops_bare_extension_overmatch
    jst = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:js-testing" }
    proj = project_with_files("package.json" => pkg(dev: %w[vitest]),
                              "src/foo.test.js" => "", "src/foo.js" => "")
    assert jst.matches?(File.join(proj, "src/foo.test.js"), root: proj)
    refute jst.matches?(File.join(proj, "src/foo.js"), root: proj),
           "a non-test .js no longer matches js-testing"
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_shipped_drizzle_covers_db_directory
    drizzle = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:drizzle" }
    drz = project_with_files("drizzle.config.js" => "", "src/db/client.js" => "", "src/db/migrate.js" => "")
    assert drizzle.matches?(File.join(drz, "src/db/client.js"), root: drz)
    assert drizzle.matches?(File.join(drz, "src/db/migrate.js"), root: drz)
    refute drizzle.matches?(File.join(drz, "src/components/Button.tsx"), root: drz)
  ensure
    FileUtils.remove_entry(drz) if drz
  end
end
