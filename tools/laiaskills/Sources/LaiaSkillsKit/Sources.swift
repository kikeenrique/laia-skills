import Foundation

/// One entry of `.gitmodules`.
public struct Submodule: Sendable, Equatable {
    public let name: String
    public let path: String
    public let url: String
    public let branch: String?
    public let shallow: Bool

    /// `first-party/<plugin>/upstream` pins document a project; `third-party/…` are skill sources.
    public var isFirstPartyUpstream: Bool { path.hasPrefix("first-party/") }
}

public enum Submodules {
    /// Reads `.gitmodules` with `git config`, so git's own parsing rules apply.
    public static func load(repo: URL) throws -> [Submodule] {
        let file = repo.appendingPathComponent(".gitmodules")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let arguments = ["git", "config", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.(path|url|branch|shallow)$"#]
        let result = try Shell.run(arguments, in: repo)
        // Exit status 1 means "no matching keys", e.g. an empty .gitmodules after the last submodule went.
        if result.status == 1 { return [] }
        guard result.succeeded else {
            throw ShellError.failed(command: arguments.joined(separator: " "), status: result.status, stderr: result.stderr)
        }
        return parse(result.stdout)
    }

    /// Parses `submodule.<name>.<key> <value>` lines.
    static func parse(_ output: String) -> [Submodule] {
        var fields: [String: [String: String]] = [:]
        var order: [String] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("submodule.") else { continue }
            let keyPath = parts[0].dropFirst("submodule.".count)
            guard let dot = keyPath.lastIndex(of: ".") else { continue }
            let name = String(keyPath[..<dot])
            let key = String(keyPath[keyPath.index(after: dot)...])
            if fields[name] == nil { order.append(name) }
            fields[name, default: [:]][key] = parts[1]
        }
        return order.compactMap { name in
            guard let values = fields[name], let path = values["path"], let url = values["url"] else { return nil }
            return Submodule(
                name: name,
                path: path,
                url: url,
                branch: values["branch"],
                shallow: values["shallow"] == "true"
            )
        }
    }
}

/// Finds skills by the `name` in their `SKILL.md` frontmatter, never by folder path.
public enum SkillDiscovery {
    /// Folders never searched: VCS data, dependencies, test fixtures.
    static let skippedFolders: Set<String> = [".git", "node_modules", ".build", "evals", "tests", "Tests"]

    /// All skill folders under `root` whose frontmatter `name` matches `name`.
    public static func folders(named name: String, under root: URL, skipping extraFolders: Set<String> = []) -> [URL] {
        allSkills(under: root, skipping: extraFolders).filter { matches($0.name, name) }.map(\.folder)
    }

    /// Whether a frontmatter `name` is the skill `name`. Ignores case: names should be lowercase, but some
    /// upstreams write e.g. `watchOS`, which other installers file under `watchos` as well.
    public static func matches(_ frontmatterName: String?, _ name: String) -> Bool {
        frontmatterName?.lowercased() == name.lowercased()
    }

    public static func allSkills(under root: URL, skipping extraFolders: Set<String> = []) -> [(name: String, folder: URL)] {
        let skipped = skippedFolders.union(extraFolders)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var found: [(String, URL)] = []
        for case let url as URL in enumerator {
            if skipped.contains(url.lastPathComponent) {
                // Only skip directories: calling skipDescendants() on a file (e.g. a submodule's `.git`
                // file) makes Foundation skip the wrong subtree.
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.lastPathComponent == "SKILL.md", let name = frontmatterName(of: url) else { continue }
            found.append((name, url.deletingLastPathComponent().standardizedFileURL))
        }
        return found.sorted { $0.1.path < $1.1.path }
    }

    /// The `name:` value from a `SKILL.md` YAML frontmatter block, unquoted.
    public static func frontmatterName(of file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return frontmatterName(in: text)
    }

    static func frontmatterName(in text: String) -> String? {
        frontmatterValue("name", in: text)
    }

    /// A top-level scalar from the YAML frontmatter, unquoted. Enough for `name` and `description`,
    /// including block scalars (`>`, `|-`, …), whose indented lines are joined with spaces.
    public static func frontmatterValue(_ key: String, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for (index, line) in lines.enumerated().dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }
            guard line.hasPrefix("\(key):") else { continue }
            var value = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if let marker = value.first, marker == ">" || marker == "|", value.count <= 2 {
                let block = lines[(index + 1)...].prefix { $0.isEmpty || $0.first == " " || $0.first == "\t" }
                value = block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
                return value.isEmpty ? nil : value
            }
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

/// Where a skill lives, after resolving its `skills.json` entry.
public struct ResolvedSkill: Sendable {
    public let name: String
    public let entry: SkillEntry
    /// Folder holding `SKILL.md`, or nil when resolution failed.
    public let folder: URL?
    /// Why resolution failed.
    public let problem: String?
    /// The submodule pinning this skill's files (nil for first-party skills, which are versioned by their plugin).
    public let submodulePath: String?
    /// The first-party plugin folder name, for first-party skills.
    public let plugin: String?
}

public enum SkillResolver {
    public static func resolve(_ repo: Repository, submodules: [Submodule]) -> [ResolvedSkill] {
        repo.manifest.skills.keys.sorted().map { name in
            resolve(name: name, entry: repo.manifest.skills[name]!, repo: repo.root, submodules: submodules)
        }
    }

    static func resolve(name: String, entry: SkillEntry, repo: URL, submodules: [Submodule]) -> ResolvedSkill {
        func failure(_ problem: String, submodule: String? = nil) -> ResolvedSkill {
            ResolvedSkill(name: name, entry: entry, folder: nil, problem: problem, submodulePath: submodule, plugin: nil)
        }

        if entry.source == SkillEntry.firstParty {
            // first-party/<plugin>/skills/<name>/SKILL.md; upstream/ pins are never searched.
            let root = repo.appendingPathComponent("first-party")
            let plugins = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let matches = plugins.sorted().compactMap { plugin -> (String, URL)? in
                let folder = root.appendingPathComponent(plugin).appendingPathComponent("skills").appendingPathComponent(name)
                guard SkillDiscovery.matches(SkillDiscovery.frontmatterName(of: folder.appendingPathComponent("SKILL.md")), name) else {
                    return nil
                }
                return (plugin, folder.standardizedFileURL)
            }
            guard let match = matches.first else { return failure("no first-party skill named `\(name)`") }
            if matches.count > 1 {
                return failure("ambiguous: found in plugins \(matches.map(\.0).joined(separator: ", "))")
            }
            return ResolvedSkill(name: name, entry: entry, folder: match.1, problem: nil, submodulePath: nil, plugin: match.0)
        }

        guard submodules.contains(where: { $0.path == entry.source }) else {
            return failure("source `\(entry.source)` is not a submodule in .gitmodules")
        }
        let sourceRoot = repo.appendingPathComponent(entry.source)
        guard FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(".git").path) else {
            return failure("submodule `\(entry.source)` is not checked out (git submodule update --init \(entry.source))", submodule: entry.source)
        }

        if let path = entry.path {
            let folder = sourceRoot.appendingPathComponent(path).standardizedFileURL
            let found = SkillDiscovery.frontmatterName(of: folder.appendingPathComponent("SKILL.md"))
            guard SkillDiscovery.matches(found, name) else {
                return failure(found.map { "`\(path)` holds skill `\($0)`, not `\(name)`" } ?? "no SKILL.md at `\(path)`", submodule: entry.source)
            }
            return ResolvedSkill(name: name, entry: entry, folder: folder, problem: nil, submodulePath: entry.source, plugin: nil)
        }

        let matches = SkillDiscovery.folders(named: name, under: sourceRoot)
        guard let folder = matches.first else {
            return failure("no skill named `\(name)` in `\(entry.source)` (moved or removed upstream?)", submodule: entry.source)
        }
        if matches.count > 1 {
            let paths = matches.map { relativePath(of: $0, to: sourceRoot) }
            return failure("ambiguous: set `path` to one of \(paths.joined(separator: ", "))", submodule: entry.source)
        }
        return ResolvedSkill(name: name, entry: entry, folder: folder, problem: nil, submodulePath: entry.source, plugin: nil)
    }
}

public func relativePath(of url: URL, to base: URL) -> String {
    let path = url.standardizedFileURL.path
    let basePath = base.standardizedFileURL.path
    // A skill at a repo's root (`SKILL.md` next to the README) is the base itself.
    if path == basePath { return "" }
    guard path.hasPrefix(basePath + "/") else { return path }
    return String(path.dropFirst(basePath.count + 1))
}
