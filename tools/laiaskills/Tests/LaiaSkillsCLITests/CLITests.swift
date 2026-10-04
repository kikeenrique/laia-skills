import Foundation
import LaiaSkillsKit
import LaiaSkillsTestSupport
import Testing

/// End-to-end tests: run the built `laiaskills` binary against fixture repos with a fake HOME.
/// Everything is local (no network); a shell script stands in for the AI agent.
@Suite struct CLITests {
    // MARK: Install and drift

    @Test func syncInstallsEverythingAndListReportsIt() throws {
        let setup = try SkillsRepoFixture()
        let sync = try laiaskills(setup, "sync", "--yes", "--json")
        #expect(sync.status == 0, "\(sync.stderr)")
        #expect(setup.fixture.exists("home/.agents/skills/alpha/scripts/run.sh"))
        #expect(setup.fixture.exists("home/.agents/skills/beta/SKILL.md"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: setup.fixture.url("home/.claude/skills/beta").path)
            == "../../.agents/skills/beta")

        let rows = try laiaskills(setup, "list", "--json").jsonArray()
        #expect(rows.map { $0["hub"] as? String } == ["up to date", "up to date"])
        #expect(rows.first { $0["name"] as? String == "beta" }?["version"] as? String == "v1.0.0")
    }

    @Test func refusesToReplaceAnotherToolsCopyWithoutConfirmation() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.write("home/.agents/skills/beta/SKILL.md", "installed by another tool")

        let plan = try laiaskills(setup, "sync", "--dry-run", "--json").jsonArray()
        #expect(plan.contains { $0["name"] as? String == "beta" && $0["action"] as? String == "replace other tool's copy" })

        let sync = try laiaskills(setup, "sync")
        #expect(sync.status != 0)
        #expect(sync.stderr.contains("--yes"))
        #expect(try setup.fixture.read("home/.agents/skills/beta/SKILL.md") == "installed by another tool")
    }

    @Test func checkReportsEditedCopiesAndOnlyForceRestoresThem() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        try setup.fixture.write("home/.agents/skills/alpha/SKILL.md", "edited in place")

        let check = try laiaskills(setup, "check", "--offline", "--exit-code", "--json")
        #expect(check.status == 1)
        let installs = try check.jsonObject()["installs"] as? [[String: Any]]
        #expect(installs?.first?["skill"] as? String == "alpha")

        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        #expect(try setup.fixture.read("home/.agents/skills/alpha/SKILL.md") == "edited in place")

        #expect(try laiaskills(setup, "sync", "--yes", "--force").status == 0)
        #expect(try setup.fixture.read("home/.agents/skills/alpha/SKILL.md").contains("name: alpha"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.fixture.url("home/.agents/.laiaskills/backups").path).count == 1)
    }

    @Test func skipMirrorsKeepsTheHubCopyButNoLink() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        try setup.fixture.write("repo/skills.json", """
        {"skills": {"alpha": {"source": "first-party"}, "beta": {"source": "third-party/o__beta", "skipMirrors": ["claude"]}}}
        """)

        let plan = try laiaskills(setup, "sync", "--dry-run", "--json").jsonArray()
        #expect(plan.map { $0["action"] as? String } == ["relink mirrors"])
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        #expect(setup.fixture.exists("home/.agents/skills/beta/SKILL.md"))
        #expect(!setup.fixture.exists("home/.claude/skills/beta"))

        let rows = try laiaskills(setup, "list", "--json").jsonArray()
        let beta = rows.first { $0["name"] as? String == "beta" }
        #expect((beta?["mirrors"] as? [String: String])?["claude"] == "skipped")
    }

    @Test func importPruneRemovesLockEntriesOnceSynced() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        try setup.fixture.write("home/.agents/.skill-lock.json", #"{"skills": {"beta": {}, "gone": {}}}"#)

        #expect(try laiaskills(setup, "import", "--prune").stderr.contains("--yes"))
        let pruned = try laiaskills(setup, "import", "--prune", "--yes", "--json")
        #expect(pruned.status == 0, "\(pruned.stderr)")
        #expect(try pruned.jsonArray().map { $0["name"] as? String } == ["beta", "gone"])
        let lock = try setup.fixture.read("home/.agents/.skill-lock.json")
        #expect(!lock.contains("beta") && !lock.contains("gone"))
        #expect(try laiaskills(setup, "import", "--prune", "--apply").status != 0)
    }

    // MARK: Sources

    @Test func addInstallsAndCommitsALocalSource() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.originRepo("origins/acme/gamma", commits: [("README", nil)])
        try setup.fixture.skill("origins/acme/gamma/skills/gamma", name: "gamma")
        try setup.fixture.git("add", ".", in: "origins/acme/gamma")
        try setup.fixture.git("commit", "--quiet", "-m", "gamma", in: "origins/acme/gamma")
        try setup.fixture.git("tag", "v2.0.0", in: "origins/acme/gamma")

        let add = try laiaskills(setup, "add", "file://\(setup.fixture.url("origins/acme/gamma").path)", "--skill", "gamma", "--json")
        #expect(add.status == 0, "\(add.stderr)")
        #expect(try add.jsonObject()["tag"] as? String == "v2.0.0")
        #expect(try setup.fixture.read("repo/skills.json").contains(#""gamma": { "source": "third-party/acme__gamma" }"#))
        #expect(setup.fixture.exists("home/.agents/skills/gamma/SKILL.md"))

        #expect(try laiaskills(setup, "commit", "--yes").status == 0)
        #expect(try lastSubject(setup) == "feat(skills): add gamma")
        #expect(try setup.fixture.git("status", "--porcelain", in: "repo").isEmpty)
    }

    @Test func upgradesAndCommitsAThirdPartySource() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)

        let upgrade = try laiaskills(setup, "upgrade", "beta", "--yes")
        #expect(upgrade.status == 0, "\(upgrade.stderr)")
        #expect(setup.fixture.exists("home/.agents/skills/beta/references/notes.md"))

        #expect(try laiaskills(setup, "commit", "--yes").status == 0)
        #expect(try lastSubject(setup) == "chore(third-party): bump o__beta to v1.1.0")
        #expect(try laiaskills(setup, "upgrade", "beta", "--yes").stdout.contains("up to date"))
    }

    @Test func removeDropsTheUnusedSourceAndCommits() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)
        #expect(try laiaskills(setup, "remove", "beta", "--yes").status == 0)
        #expect(!setup.fixture.exists("home/.agents/skills/beta"))
        #expect(!setup.fixture.exists("home/.claude/skills/beta"))

        #expect(try laiaskills(setup, "commit", "--yes").status == 0)
        #expect(try lastSubject(setup) == "chore(skills): remove beta")
        #expect(try !setup.fixture.read("repo/.gitmodules").contains("o__beta"))
    }

    // MARK: First-party re-check

    @Test func upgradeRunsTheAgentKeepsOnlySkillEditsAndCommitsThePlugin() throws {
        let setup = try SkillsRepoFixture()
        try addFirstPartyUpstream(setup, validatorExit: 0)
        #expect(try laiaskills(setup, "sync", "--yes").status == 0)

        let upgrade = try laiaskills(setup, "upgrade", "first-party/alpha/upstream", "--yes", "--commit")
        #expect(upgrade.status == 0, "\(upgrade.stderr)")
        #expect(try setup.fixture.read("prompt.txt").contains("against origin-beta v1.1.0"))
        #expect(!setup.fixture.exists("repo/STRAY.md"))

        #expect(try lastSubject(setup) == "docs(alpha): refresh guidance for origin-beta v1.1.0")
        #expect(try setup.fixture.read("repo/first-party/alpha/.claude-plugin/plugin.json").contains(#""version": "0.1.1""#))
        // First-party skills install from HEAD, so the committed edit reaches the hub.
        #expect(try setup.fixture.read("home/.agents/skills/alpha/SKILL.md").contains("updated by agent"))
    }

    @Test func upgradeStopsWhenTheValidatorFails() throws {
        let setup = try SkillsRepoFixture()
        try addFirstPartyUpstream(setup, validatorExit: 1)
        let head = try setup.fixture.git("rev-parse", "HEAD", in: "repo")

        let upgrade = try laiaskills(setup, "upgrade", "first-party/alpha/upstream", "--yes", "--commit")
        #expect(upgrade.status != 0)
        #expect(upgrade.stderr.contains("validator"))
        #expect(try setup.fixture.git("rev-parse", "HEAD", in: "repo") == head)
    }

    // MARK: Read-only commands

    @Test func importPlansFromTheLockFile() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.git("clone", "--quiet", setup.fixture.url("origin-beta").path, "clones/beta-tools")
        try setup.fixture.git("remote", "set-url", "origin", "https://github.com/acme/beta-tools.git", in: "clones/beta-tools")
        try setup.fixture.write("home/.agents/.skill-lock.json", """
        {"skills": {
          "beta": {"sourceType": "github", "source": "o/beta"},
          "from-github": {"sourceType": "github", "source": "acme/tools", "skillPath": "skills/x/SKILL.md"},
          "from-clone": {"sourceType": "local", "sourceUrl": "\(setup.fixture.url("clones/beta-tools").path)"},
          "gone": {"sourceType": "local", "sourceUrl": "\(setup.fixture.url("clones/missing").path)"}
        }}
        """)
        let items = try laiaskills(setup, "import", "--json").jsonArray()
        let plan = Dictionary(uniqueKeysWithValues: items.map { ($0["name"] as! String, $0) })
        #expect(plan["beta"]?["disposition"] as? String == "managed")
        #expect(plan["from-github"]?["source"] as? String == "acme/tools")
        #expect(plan["from-clone"]?["source"] as? String == "acme/beta-tools")
        #expect(plan["gone"]?["disposition"] as? String == "unknown")
    }

    @Test func doctorFailsOnSkillsThatDoNotResolve() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.write("repo/skills.json", """
        {"skills": {"alpha": {"source": "first-party"}, "beta": {"source": "third-party/o__beta"}, "ghost": {"source": "first-party"}}}
        """)
        let doctor = try laiaskills(setup, "doctor", "--json")
        #expect(doctor.status == 1)
        #expect(try doctor.jsonArray().contains { $0["severity"] as? String == "error" && ($0["message"] as? String)?.hasPrefix("ghost") == true })
    }

    @Test func commitRefusesWithoutConfirmationAndWithNothingPending() throws {
        let setup = try SkillsRepoFixture()
        #expect(try laiaskills(setup, "commit", "--yes").stderr.contains("nothing to commit"))
        #expect(try laiaskills(setup, "remove", "beta").stderr.contains("--yes"))
    }
}

// MARK: - Helpers

struct Run {
    let status: Int32
    let stdout: String
    let stderr: String

    func jsonArray() throws -> [[String: Any]] {
        try #require(JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [[String: Any]], "not a JSON array: \(stdout)\(stderr)")
    }

    func jsonObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any], "not a JSON object: \(stdout)\(stderr)")
    }
}

/// Runs the binary with the fixture's HOME, against the fixture repo.
func laiaskills(_ setup: SkillsRepoFixture, _ arguments: String...) throws -> Run {
    let result = try Shell.run(["HOME=\(setup.home.path)", binary.path] + arguments + ["--repo", setup.repo.path],
                               in: setup.repo)
    return Run(status: result.status, stdout: result.stdout, stderr: result.stderr)
}

func lastSubject(_ setup: SkillsRepoFixture) throws -> String {
    try setup.fixture.git("log", "-1", "--format=%s", in: "repo")
}

/// The `laiaskills` executable from this package's debug build. `.build/debug` links to the active
/// products folder on macOS and Linux; `swift test` builds the binary first because this target depends on it.
let binary: URL = {
    if let override = ProcessInfo.processInfo.environment["LAIASKILLS_BINARY"] { return URL(fileURLWithPath: override) }
    // Tests/LaiaSkillsCLITests/CLITests.swift → the package root is three folders up.
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let binary = package.appendingPathComponent(".build/debug/laiaskills")
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
        fatalError("laiaskills binary not found at \(binary.path); build it or set LAIASKILLS_BINARY")
    }
    return binary
}()

/// Gives `alpha` an `upstream/` pin (origin-beta at v1.0.0), plugin manifests, a stub agent, and a stub
/// validator exiting with `validatorExit`. The agent records its prompt in `prompt.txt` (outside the
/// repo), edits the skill, and drops a stray file that must be reverted.
func addFirstPartyUpstream(_ setup: SkillsRepoFixture, validatorExit: Int) throws {
    let fixture = setup.fixture
    try fixture.write("repo/first-party/alpha/.claude-plugin/plugin.json", "{\n  \"name\": \"alpha\",\n  \"version\": \"0.1.0\"\n}\n")
    try fixture.write("repo/.claude-plugin/marketplace.json", #"{"plugins": [{"name": "alpha", "version": "0.1.0"}]}"#)
    let agent = try fixture.write("agent.sh", """
    #!/bin/sh
    printf '%s' "$1" > "\(fixture.url("prompt.txt").path)"
    echo "updated by agent" >> first-party/alpha/skills/alpha/SKILL.md
    echo stray > STRAY.md
    """)
    try fixture.write("repo/tools/config/recheck.json", """
    {"agent": "stub", "commands": {"stub": ["sh", "\(agent.path)", "{prompt}"]}, "timeoutMinutes": 1}
    """)
    try fixture.write("repo/tools/config/prompts/recheck.md", "Re-check {{plugin}} against {{upstream}} {{to}}.")
    try fixture.write("repo/tools/scripts/validate_skills.rb", "exit \(validatorExit)\n")
    try fixture.git("submodule", "add", "--quiet", fixture.url("origin-beta").path, "first-party/alpha/upstream", in: "repo")
    try fixture.git("checkout", "--quiet", "v1.0.0", in: "repo/first-party/alpha/upstream")
    try fixture.git("add", ".", in: "repo")
    try fixture.git("commit", "--quiet", "-m", "alpha upstream", in: "repo")
}
