#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"
require "pathname"
require "yaml"

ROOT = File.expand_path("..", __dir__)
STRICT_AGENT_NEUTRAL = ENV.fetch("STRICT_AGENT_NEUTRAL", "0") == "1"
SEMVER_RE = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/

CORE_FRONTMATTER_KEYS = %w[name description license metadata].freeze
LEGACY_AGENT_KEYS = %w[allowed-tools disable-model-invocation].freeze
AGENT_SIDECAR = "agents/openai.yaml"
AGENT_TOP_LEVEL_KEYS = %w[interface policy dependencies].freeze
AGENT_INTERFACE_KEYS = %w[display_name short_description icon_small icon_large brand_color default_prompt].freeze
HEX_COLOR_RE = /\A#[0-9A-Fa-f]{6}\z/
MAX_DESCRIPTION_LENGTH = 1024

@errors = []
@warnings = []

def error(message)
  @errors << message
end

def warning(message)
  @warnings << message
end

def relative(path)
  Pathname.new(path).relative_path_from(Pathname.new(ROOT)).to_s
end

def read(path)
  File.read(path, mode: "r:BOM|UTF-8")
rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
  File.read(path)
end

def parse_frontmatter(skill_md)
  content = read(skill_md)
  unless content.start_with?("---\n")
    error("#{relative(skill_md)}: missing YAML frontmatter")
    return nil
  end

  match = content.match(/\A---\n(.*?)\n---/m)
  unless match
    error("#{relative(skill_md)}: invalid YAML frontmatter delimiter")
    return nil
  end

  frontmatter = YAML.safe_load(match[1])
  unless frontmatter.is_a?(Hash)
    error("#{relative(skill_md)}: frontmatter must be a YAML mapping")
    return nil
  end

  frontmatter
rescue Psych::SyntaxError => e
  error("#{relative(skill_md)}: invalid YAML frontmatter: #{e.message}")
  nil
end

def validate_skill(skill_dir)
  skill_md = File.join(skill_dir, "SKILL.md")
  frontmatter = parse_frontmatter(skill_md)
  return unless frontmatter

  rel_skill_md = relative(skill_md)
  folder_name = File.basename(skill_dir)
  keys = frontmatter.keys.map(&:to_s)

  unexpected = keys - CORE_FRONTMATTER_KEYS - LEGACY_AGENT_KEYS
  error("#{rel_skill_md}: unexpected frontmatter keys: #{unexpected.join(', ')}") unless unexpected.empty?

  legacy = keys & LEGACY_AGENT_KEYS
  unless legacy.empty?
    message = "#{rel_skill_md}: legacy agent-specific frontmatter keys: #{legacy.join(', ')}"
    STRICT_AGENT_NEUTRAL ? error(message) : warning(message)
  end

  name = frontmatter["name"]
  description = frontmatter["description"]

  unless name.is_a?(String) && !name.strip.empty?
    error("#{rel_skill_md}: missing string frontmatter field `name`")
  end

  if name.is_a?(String)
    normalized = name.strip
    if normalized != folder_name
      error("#{rel_skill_md}: frontmatter name `#{normalized}` must match folder `#{folder_name}`")
    end
    unless normalized.match?(/\A[a-z0-9-]+\z/) && !normalized.start_with?("-") && !normalized.end_with?("-") && !normalized.include?("--")
      error("#{rel_skill_md}: frontmatter name must be lowercase hyphen-case")
    end
    if normalized.length > 64
      error("#{rel_skill_md}: frontmatter name is too long (#{normalized.length}, max 64)")
    end
  end

  unless description.is_a?(String) && !description.strip.empty?
    error("#{rel_skill_md}: missing string frontmatter field `description`")
  end

  if description.is_a?(String)
    stripped = description.strip
    if stripped.length > MAX_DESCRIPTION_LENGTH
      error("#{rel_skill_md}: description is too long (#{stripped.length}, max #{MAX_DESCRIPTION_LENGTH})")
    end
    if stripped.include?("<") || stripped.include?(">")
      error("#{rel_skill_md}: description cannot contain angle brackets")
    end
  end

  validate_agent_sidecar(skill_dir)
end

def validate_agent_sidecar(skill_dir)
  sidecar_path = File.join(skill_dir, AGENT_SIDECAR)
  return unless File.exist?(sidecar_path)

  rel = relative(sidecar_path)
  begin
    payload = YAML.safe_load(read(sidecar_path))
  rescue Psych::SyntaxError => e
    error("#{rel}: invalid YAML: #{e.message}")
    return
  end

  unless payload.is_a?(Hash)
    error("#{rel}: must be a YAML mapping")
    return
  end

  unexpected = payload.keys.map(&:to_s) - AGENT_TOP_LEVEL_KEYS
  error("#{rel}: unexpected top-level keys: #{unexpected.join(', ')}") unless unexpected.empty?

  interface = payload["interface"]
  unless interface.is_a?(Hash)
    error("#{rel}: missing mapping field `interface`")
    return
  end

  unexpected_interface = interface.keys.map(&:to_s) - AGENT_INTERFACE_KEYS
  unless unexpected_interface.empty?
    error("#{rel}: unexpected interface keys: #{unexpected_interface.join(', ')}")
  end

  %w[display_name short_description].each do |field|
    value = interface[field]
    unless value.is_a?(String) && !value.strip.empty?
      error("#{rel}: missing non-empty string field `interface.#{field}`")
    end
  end

  default_prompt = interface["default_prompt"]
  if !default_prompt.nil? && (!default_prompt.is_a?(String) || default_prompt.strip.empty?)
    error("#{rel}: field `interface.default_prompt` must be a non-empty string")
  end

  brand_color = interface["brand_color"]
  if !brand_color.nil? && (!brand_color.is_a?(String) || brand_color !~ HEX_COLOR_RE)
    error("#{rel}: field `interface.brand_color` must use `#RRGGBB`")
  end

  %w[icon_small icon_large].each do |field|
    validate_agent_asset_path(skill_dir, rel, field, interface[field])
  end
end

def validate_agent_asset_path(skill_dir, rel, field, value)
  return if value.nil?

  unless value.is_a?(String) && !value.strip.empty?
    error("#{rel}: field `interface.#{field}` must be a non-empty string")
    return
  end

  unless value.start_with?("./")
    error("#{rel}: field `interface.#{field}` must be a relative path starting with `./`")
  end

  if value.include?("..")
    error("#{rel}: field `interface.#{field}` cannot contain `..`")
    return
  end

  root = File.expand_path(skill_dir)
  resolved = File.expand_path(value, skill_dir)
  unless resolved == root || resolved.start_with?("#{root}#{File::SEPARATOR}")
    error("#{rel}: field `interface.#{field}` must resolve inside the skill directory")
    return
  end

  unless File.exist?(resolved)
    error("#{rel}: field `interface.#{field}` points to missing asset: #{value}")
    return
  end

  extension = File.extname(resolved).downcase
  return if %w[.png .svg .jpg .jpeg .webp].include?(extension)

  error("#{rel}: field `interface.#{field}` must point to a PNG, SVG, JPEG, or WebP asset")
end

def skill_dirs
  Dir.glob(File.join(ROOT, "*", "skills", "*", "SKILL.md"))
     .map { |path| File.dirname(path) }
     .sort
end

def plugin_dirs
  Dir.glob(File.join(ROOT, "*", ".claude-plugin", "plugin.json"))
     .map { |path| File.dirname(File.dirname(path)) }
     .sort
end

def validate_plugin(plugin_dir)
  manifest_path = File.join(plugin_dir, ".claude-plugin", "plugin.json")
  rel = relative(manifest_path)
  folder = File.basename(plugin_dir)

  begin
    manifest = JSON.parse(read(manifest_path))
  rescue JSON::ParserError => e
    error("#{rel}: invalid JSON: #{e.message}")
    return
  end

  unless manifest.is_a?(Hash)
    error("#{rel}: must be a JSON object")
    return
  end

  name = manifest["name"]
  version = manifest["version"]
  description = manifest["description"]

  if !name.is_a?(String) || name.strip.empty?
    error("#{rel}: missing string field `name`")
  elsif name != folder
    error("#{rel}: name `#{name}` must match folder `#{folder}`")
  end

  if !version.is_a?(String) || version.strip.empty?
    error("#{rel}: missing string field `version`")
  elsif version !~ SEMVER_RE
    error("#{rel}: version `#{version}` is not valid semver (MAJOR.MINOR.PATCH)")
  end

  if !description.is_a?(String) || description.strip.empty?
    error("#{rel}: missing string field `description`")
  end

  skill_md = File.join(plugin_dir, "skills", folder, "SKILL.md")
  unless File.exist?(skill_md)
    error("#{rel}: expected skill at skills/#{folder}/SKILL.md")
  end
end

def validate_marketplace(plugins)
  manifest_path = File.join(ROOT, ".claude-plugin", "marketplace.json")
  rel = relative(manifest_path)
  unless File.exist?(manifest_path)
    error("#{rel}: missing")
    return
  end

  begin
    manifest = JSON.parse(read(manifest_path))
  rescue JSON::ParserError => e
    error("#{rel}: invalid JSON: #{e.message}")
    return
  end

  unless manifest.is_a?(Hash) && manifest["plugins"].is_a?(Array)
    error("#{rel}: must have a `plugins` array")
    return
  end

  listed = manifest["plugins"].map { |p| p.is_a?(Hash) ? p["name"] : nil }.compact
  expected = plugins.map { |dir| File.basename(dir) }

  (expected - listed).each { |n| error("#{rel}: plugin `#{n}` not listed in marketplace") }
  (listed - expected).each { |n| error("#{rel}: marketplace lists unknown plugin `#{n}`") }
end

def markdown_files(skill_dirs)
  paths = []
  readme = File.join(ROOT, "README.md")
  paths << readme if File.exist?(readme)
  skill_dirs.each do |dir|
    paths.concat(Dir.glob(File.join(dir, "**", "*.md")))
  end
  paths.uniq.sort
end

def validate_no_todos(markdown_paths)
  markdown_paths.each do |path|
    read(path).each_line.with_index(1) do |line, number|
      next unless line.match?(/\[?TODO\]?/i)

      error("#{relative(path)}:#{number}: unresolved TODO marker")
    end
  end
end

def local_markdown_link?(target)
  return false if target.empty?
  return false if target.start_with?("#")
  return false if target.match?(/\A[a-z][a-z0-9+.-]*:/i)
  return false if target.start_with?("//")

  true
end

def strip_link_target(raw_target)
  target = raw_target.strip
  target = target[1..-2] if target.start_with?("<") && target.end_with?(">")
  target = target.split(/[[:space:]]+/, 2).first || ""
  target = target.split("#", 2).first
  target
end

def validate_markdown_links(markdown_paths)
  markdown_paths.each do |path|
    content = read(path)
    content.scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
      target = strip_link_target(raw_target)
      next unless local_markdown_link?(target)

      decoded = CGI.unescape(target)
      resolved = File.expand_path(decoded, File.dirname(path))
      unless File.exist?(resolved)
        error("#{relative(path)}: broken local Markdown link: #{target}")
      end
    end
  end
end

def validate_readme(plugin_dirs)
  readme = File.join(ROOT, "README.md")
  unless File.exist?(readme)
    error("README.md: missing")
    return
  end

  content = read(readme)
  plugin_dirs.each do |dir|
    name = File.basename(dir)
    expected = "#{name}/skills/#{name}/SKILL.md"
    unless content.include?("(#{expected})") || content.include?("(<#{expected}>)")
      error("README.md: missing skill link to #{expected}")
    end
  end

  content.scan(/\[[^\]]+\]\(([^)]+\/SKILL\.md)\)/).flatten.each do |target|
    target = strip_link_target(target)
    next unless local_markdown_link?(target)

    resolved = File.expand_path(CGI.unescape(target), ROOT)
    error("README.md: skill link does not exist: #{target}") unless File.exist?(resolved)
  end
end

skills = skill_dirs
plugins = plugin_dirs
if skills.empty?
  error("No skill directories found")
else
  skills.each { |dir| validate_skill(dir) }
end

plugins.each { |dir| validate_plugin(dir) }
validate_marketplace(plugins)

docs = markdown_files(skills)
validate_no_todos(docs)
validate_markdown_links(docs)
validate_readme(plugins)

@warnings.each { |message| warn("warning: #{message}") }

if @errors.empty?
  puts "Validated #{skills.length} skills and #{docs.length} Markdown files."
  exit 0
end

warn "Validation failed:"
@errors.each { |message| warn("- #{message}") }
exit 1
