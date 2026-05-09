#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "pathname"
require "yaml"

ROOT = File.expand_path("..", __dir__)
STRICT_AGENT_NEUTRAL = ENV.fetch("STRICT_AGENT_NEUTRAL", "0") == "1"

CORE_FRONTMATTER_KEYS = %w[name description license metadata].freeze
LEGACY_AGENT_KEYS = %w[allowed-tools disable-model-invocation].freeze
VENDOR_SIDECARS = [
  "agents/openai.yaml"
].freeze
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

  VENDOR_SIDECARS.each do |sidecar|
    sidecar_path = File.join(skill_dir, sidecar)
    error("#{relative(sidecar_path)}: vendor-specific sidecar is not allowed") if File.exist?(sidecar_path)
  end
end

def skill_dirs
  Dir.glob(File.join(ROOT, "*", "SKILL.md"))
     .map { |path| File.dirname(path) }
     .sort
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

def validate_readme(skill_dirs)
  readme = File.join(ROOT, "README.md")
  unless File.exist?(readme)
    error("README.md: missing")
    return
  end

  content = read(readme)
  skill_dirs.each do |dir|
    name = File.basename(dir)
    expected = "#{name}/SKILL.md"
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
if skills.empty?
  error("No skill directories found")
else
  skills.each { |dir| validate_skill(dir) }
end

docs = markdown_files(skills)
validate_no_todos(docs)
validate_markdown_links(docs)
validate_readme(skills)

@warnings.each { |message| warn("warning: #{message}") }

if @errors.empty?
  puts "Validated #{skills.length} skills and #{docs.length} Markdown files."
  exit 0
end

warn "Validation failed:"
@errors.each { |message| warn("- #{message}") }
exit 1
