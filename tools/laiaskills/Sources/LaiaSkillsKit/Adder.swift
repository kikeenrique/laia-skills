import Foundation

/// A third-party source as typed by the user.
public struct SourceSpec: Sendable, Equatable {
    public let owner: String
    public let repository: String
    public let url: String
    /// Skill named with `owner/repo@skill`.
    public let skill: String?

    /// `third-party/<owner>__<repo>`.
    public var submodulePath: String { "third-party/\(owner)__\(repository)" }

    public init(owner: String, repository: String, url: String, skill: String? = nil) {
        self.owner = owner
        self.repository = repository
        self.url = url
        self.skill = skill
    }

    /// Accepts `owner/repo`, `owner/repo@skill`, `https://host/owner/repo(.git)`, or `git@host:owner/repo(.git)`.
    public init(_ text: String) throws {
        var body = text.trimmingCharacters(in: .whitespaces)
        var skill: String?
        var url: String?

        if body.contains("://") || (body.hasPrefix("git@") && body.contains(":")) {
            // URLs: owner/repo are the last two path segments (works for file:// and nested groups too).
            url = body
            let path = body.contains("://")
                ? String(body.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false).dropFirst(3).first ?? "")
                : String(body[body.index(after: body.firstIndex(of: ":")!)...])
            body = path.split(separator: "/").suffix(2).joined(separator: "/")
        } else if let at = body.lastIndex(of: "@") {
            skill = String(body[body.index(after: at)...])
            body = String(body[..<at])
        }

        let parts = body.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, skill?.isEmpty != true else {
            throw EditError.invalidSource(text)
        }
        let repository = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        owner = parts[0]
        self.repository = repository
        self.url = url ?? "https://github.com/\(parts[0])/\(repository).git"
        self.skill = skill
    }
}

public enum Adder {
    /// Adds the source as a submodule (or reuses it) pinned to its newest release tag, if it has one.
    /// Everything is staged. Returns the pinned tag.
    @discardableResult
    public static func addSource(_ spec: SourceSpec, repo: URL, shallow: Bool) throws -> String? {
        let git = Git(repo)
        let path = spec.submodulePath
        if try Submodules.load(repo: repo).contains(where: { $0.path == path }) {
            return Pins.releaseTag(at: try Pins.indexCommit(of: path, repo: repo), git: Git(repo.appendingPathComponent(path)))
        }
        try git.run(["submodule", "add", "--quiet"] + (shallow ? ["--depth", "1"] : []) + ["--", spec.url, path])
        if shallow {
            try git.run("config", "--file", ".gitmodules", "submodule.\(path).shallow", "true")
            try git.run("add", ".gitmodules")
        }
        let source = Git(repo.appendingPathComponent(path))
        // List tags without downloading them: for a shallow source, fetching every tag would pull a
        // snapshot per release.
        let newest = try remoteReleaseTags(source).max()
        if let newest {
            try source.run(["fetch", "--quiet", "--force", "origin", "tag", newest.tag] + (shallow ? ["--depth", "1"] : []))
            try source.run("checkout", "--quiet", newest.tag)
            try git.run("add", path)
        }
        return newest?.tag
    }

    /// Stable release tags on the remote, read with `git ls-remote` (nothing is downloaded).
    static func remoteReleaseTags(_ git: Git) throws -> [ReleaseVersion] {
        try git.run("ls-remote", "--tags", "--refs", "origin").split(separator: "\n").compactMap { line in
            guard let ref = line.split(separator: "\t").last, ref.hasPrefix("refs/tags/") else { return nil }
            return ReleaseVersion(tag: String(ref.dropFirst("refs/tags/".count)))
        }
    }

    /// Skills inside a source: name and folder relative to the source.
    public static func skills(in sourcePath: String, repo: URL) -> [(name: String, path: String)] {
        let root = repo.appendingPathComponent(sourcePath)
        return SkillDiscovery.allSkills(under: root).map { ($0.name, relativePath(of: $0.folder, to: root)) }
    }

    /// skills.json entries for the chosen skills, keyed by the lowercased name; `path` is only set for
    /// names found more than once.
    public static func entries(for chosen: [(name: String, path: String)], all: [(name: String, path: String)],
                               source: String) -> [String: SkillEntry] {
        var entries: [String: SkillEntry] = [:]
        for skill in chosen {
            let duplicated = all.filter { SkillDiscovery.matches($0.name, skill.name) }.count > 1
            entries[skill.name.lowercased()] = SkillEntry(source: source, path: duplicated ? skill.path : nil)
        }
        return entries
    }

    /// The skill in `available` that `name` refers to, ignoring case. When a repo has several copies
    /// (translations under `docs/ja-JP/skills/`, per-agent copies under `.github/skills/`), the shortest
    /// path wins, which is the canonical `skills/<name>` in the layouts seen so far.
    public static func find(_ name: String, in available: [(name: String, path: String)]) -> (name: String, path: String)? {
        available.filter { SkillDiscovery.matches($0.name, name) }
            .min { ($0.path.split(separator: "/").count, $0.path) < ($1.path.split(separator: "/").count, $1.path) }
    }
}
