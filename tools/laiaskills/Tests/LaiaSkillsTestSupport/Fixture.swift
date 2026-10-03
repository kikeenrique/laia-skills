import Foundation
import LaiaSkillsKit

/// A scratch folder under the repo's `tmp/`, removed when the fixture is released.
public final class Fixture {
    public let root: URL

    /// Settings every git process in the test run sees, including ones started by the laiaskills binary:
    /// clone submodules from local paths (blocked by default), and a fixed identity without signing so
    /// commits work on CI machines that have no git identity configured. Set once, process-wide, before
    /// any fixture runs git.
    private static let configureGit: Void = {
        let settings = [
            ("protocol.file.allow", "always"),
            ("user.name", "Test"),
            ("user.email", "test@example.com"),
            ("commit.gpgsign", "false"),
            ("tag.gpgsign", "false"),
            ("init.defaultBranch", "main"),
        ]
        setenv("GIT_CONFIG_COUNT", "\(settings.count)", 1)
        for (index, setting) in settings.enumerated() {
            setenv("GIT_CONFIG_KEY_\(index)", setting.0, 1)
            setenv("GIT_CONFIG_VALUE_\(index)", setting.1, 1)
        }
    }()

    public init(_ name: String = #function) throws {
        _ = Self.configureGit
        // Tests/LaiaSkillsTestSupport/Fixture.swift → the repo root is five folders up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let safeName = name.filter { $0.isLetter || $0.isNumber }
        root = repoRoot.appendingPathComponent("tmp/laiaskills-tests/\(safeName)-\(UUID().uuidString.prefix(8))")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    public func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    @discardableResult
    public func write(_ path: String, _ content: String) throws -> URL {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    public func read(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    public func exists(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url(path).path)) != nil
    }

    public func skill(_ folder: String, name: String) throws {
        try write("\(folder)/SKILL.md", "---\nname: \(name)\ndescription: \"Test skill.\"\n---\n\n# \(name)\n")
    }

    public func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
    }

    public func symlink(_ path: String, to destination: String) throws {
        try FileManager.default.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url(path).path, withDestinationPath: destination)
    }

    @discardableResult
    public func git(_ arguments: String..., in path: String = "") throws -> String {
        try Git(path.isEmpty ? root : url(path)).run(arguments)
    }

    /// An "origin" repo with one commit per entry; entries with a tag get tagged.
    public func originRepo(_ path: String, commits: [(file: String, tag: String?)]) throws {
        try mkdir(path)
        try git("init", "--quiet", in: path)
        for commit in commits {
            try write("\(path)/\(commit.file)", commit.file)
            try git("add", ".", in: path)
            try git("commit", "--quiet", "-m", commit.file, in: path)
            if let tag = commit.tag { try git("tag", tag, in: path) }
        }
    }
}

/// A skills repo with one first-party skill (`alpha`) and one third-party skill (`beta`) in a submodule
/// pinned at v1.0.0 (v1.1.0 adds `references/notes.md`). Home is `home/`.
public struct SkillsRepoFixture {
    public let fixture: Fixture
    public var repo: URL { fixture.url("repo") }
    public var home: URL { fixture.url("home") }
    public var environment: Environment { Environment(home: home) }

    public init(_ name: String = #function) throws {
        fixture = try Fixture(name)
        try fixture.originRepo("origin-beta", commits: [("README", nil)])
        try fixture.skill("origin-beta/skills/beta", name: "beta")
        try fixture.git("add", ".", in: "origin-beta")
        try fixture.git("commit", "--quiet", "-m", "beta 1", in: "origin-beta")
        try fixture.git("tag", "v1.0.0", in: "origin-beta")
        try fixture.write("origin-beta/skills/beta/references/notes.md", "v1.1 notes")
        try fixture.git("add", ".", in: "origin-beta")
        try fixture.git("commit", "--quiet", "-m", "beta 2", in: "origin-beta")
        try fixture.git("tag", "v1.1.0", in: "origin-beta")

        try fixture.mkdir("repo")
        try fixture.git("init", "--quiet", in: "repo")
        try fixture.skill("repo/first-party/alpha/skills/alpha", name: "alpha")
        try fixture.write("repo/first-party/alpha/skills/alpha/scripts/run.sh", "#!/bin/sh\necho hi\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: fixture.url("repo/first-party/alpha/skills/alpha/scripts/run.sh").path)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF]).write(to: fixture.url("repo/first-party/alpha/skills/alpha/icon.png"))
        try fixture.symlink("repo/first-party/alpha/skills/alpha/LINK.md", to: "SKILL.md")
        try fixture.write("repo/skills.json", """
        {"skills": {"alpha": {"source": "first-party"}, "beta": {"source": "third-party/o__beta"}}}
        """)
        try fixture.write("repo/tools/config/agents.json", """
        {"hub": {"path": "~/.agents/skills"}, "mirrors": {"claude": {"path": "~/.claude/skills"}}}
        """)
        try fixture.git("submodule", "add", "--quiet", fixture.url("origin-beta").path, "third-party/o__beta", in: "repo")
        try fixture.git("checkout", "--quiet", "v1.0.0", in: "repo/third-party/o__beta")
        try fixture.git("add", ".", in: "repo")
        try fixture.git("commit", "--quiet", "-m", "init", in: "repo")
    }

    public func load() throws -> (Repository, [ResolvedSkill]) {
        let repository = try Repository(root: repo)
        return (repository, SkillResolver.resolve(repository, submodules: try Submodules.load(repo: repo)))
    }

    public func installer() throws -> (Installer, [String: ResolvedSkill]) {
        let (repository, skills) = try load()
        return (Installer(repo: repository, environment: environment), Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0) }))
    }
}
