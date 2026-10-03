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
        let output = try Git(repo).run(
            "config", "--file", ".gitmodules", "--get-regexp", #"^submodule\..*\.(path|url|branch|shallow)$"#
        )
        return parse(output)
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

    /// All skill folders under `root` whose frontmatter `name` equals `name`.
    public static func folders(named name: String, under root: URL, skipping extraFolders: Set<String> = []) -> [URL] {
        allSkills(under: root, skipping: extraFolders).filter { $0.name == name }.map(\.folder)
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
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }
            guard line.hasPrefix("name:") else { continue }
            var value = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
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
                guard SkillDiscovery.frontmatterName(of: folder.appendingPathComponent("SKILL.md")) == name else { return nil }
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
            guard found == name else {
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

func relativePath(of url: URL, to base: URL) -> String {
    let path = url.standardizedFileURL.path
    let basePath = base.standardizedFileURL.path
    guard path.hasPrefix(basePath + "/") else { return path }
    return String(path.dropFirst(basePath.count + 1))
}
