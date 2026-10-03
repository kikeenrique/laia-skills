import Foundation
import Testing
@testable import LaiaSkillsKit

@Suite struct SourceSpecTests {
    @Test func parsesGitHubShorthand() throws {
        let spec = try SourceSpec("twostraws/SwiftUI-Agent-Skill@swiftui-pro")
        #expect(spec.url == "https://github.com/twostraws/SwiftUI-Agent-Skill.git")
        #expect(spec.skill == "swiftui-pro")
        #expect(spec.submodulePath == "third-party/twostraws__SwiftUI-Agent-Skill")
    }

    @Test func parsesURLs() throws {
        let https = try SourceSpec("https://codeberg.org/CupertinoHQ/cupertino.git")
        #expect(https.owner == "CupertinoHQ" && https.repository == "cupertino" && https.url.hasPrefix("https://codeberg.org/"))
        let ssh = try SourceSpec("git@github.com:affaan-m/ECC.git")
        #expect(ssh.owner == "affaan-m" && ssh.repository == "ECC" && ssh.url == "git@github.com:affaan-m/ECC.git")
    }

    @Test(arguments: ["justone", "a/b/c", "owner/repo@", ""])
    func rejectsOtherText(_ text: String) {
        #expect(throws: EditError.self) { try SourceSpec(text) }
    }
}

@Suite struct ManifestWriterTests {
    @Test func writesOneLinePerSkillAndRoundTrips() throws {
        let fixture = try Fixture()
        let manifest = SkillsManifest(skills: [
            "b": SkillEntry(source: "third-party/o__r", path: "skills/b"),
            "a": SkillEntry(source: "first-party"),
        ])
        let file = fixture.url("skills.json")
        try manifest.write(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains(#"    "a": { "source": "first-party" },"#))
        #expect(text.contains(#"    "b": { "source": "third-party/o__r", "path": "skills/b" }"#))
        let decoded = try JSONDecoder().decode(SkillsManifest.self, from: Data(contentsOf: file))
        #expect(decoded.skills == manifest.skills)
    }
}

@Suite struct EditAndUpgradeTests {
    @Test func addsThirdPartySourceAtNewestRelease() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.originRepo("origin-gamma", commits: [("README", "v0.9.0")])
        try setup.fixture.skill("origin-gamma/gamma", name: "gamma")
        try setup.fixture.git("add", ".", in: "origin-gamma")
        try setup.fixture.git("commit", "--quiet", "-m", "gamma", in: "origin-gamma")
        try setup.fixture.git("tag", "v1.0.0", in: "origin-gamma")
        try setup.fixture.git("commit", "--quiet", "--allow-empty", "-m", "unreleased", in: "origin-gamma")

        // A local origin stands in for owner/repo; the spec only needs a URL and a name.
        let spec = SourceSpec(owner: "o", repository: "gamma", url: setup.fixture.url("origin-gamma").path)
        let tag = try Adder.addSource(spec, repo: setup.repo, shallow: false)
        #expect(tag == "v1.0.0")
        let available = Adder.skills(in: spec.submodulePath, repo: setup.repo)
        #expect(available.map(\.name) == ["gamma"])

        try SourceEditor.addSkills(Adder.entries(for: available, all: available, source: spec.submodulePath),
                                   repo: try Repository(root: setup.repo))
        #expect(try Repository(root: setup.repo).manifest.skills["gamma"] == SkillEntry(source: spec.submodulePath))
    }

    @Test func removingTheLastSkillOfASourceDropsTheSubmodule() throws {
        let setup = try SkillsRepoFixture()
        let dropped = try SourceEditor.removeSkill("beta", repo: try Repository(root: setup.repo), keepSource: false)
        #expect(dropped == "third-party/o__beta")
        #expect(try Submodules.load(repo: setup.repo).isEmpty)
        #expect(try Repository(root: setup.repo).manifest.skills["beta"] == nil)
    }

    @Test func plansAndAppliesATaggedUpgrade() throws {
        let setup = try SkillsRepoFixture()
        let (repository, skills) = try setup.load()
        let source = try #require(try Submodules.load(repo: setup.repo).first)
        let plan = try #require(try Upgrader.plan(source: source, repo: repository, skills: skills, to: nil))
        #expect(plan.fromLabel == "v1.0.0" && plan.toLabel == "v1.1.0")
        #expect(plan.skills == ["beta"])
        #expect(plan.log.count == 1)
        try Upgrader.apply(plan, repo: setup.repo)
        #expect(try Pins.indexCommit(of: source.path, repo: setup.repo) == plan.toCommit)
        #expect(try Upgrader.plan(source: source, repo: repository, skills: skills, to: nil) == nil)
    }

    @Test func refusesToUpgradeFirstPartySkills() throws {
        let setup = try SkillsRepoFixture()
        let (repository, skills) = try setup.load()
        #expect(throws: UpgradeError.self) {
            try Upgrader.sources(for: ["alpha"], repo: repository, submodules: try Submodules.load(repo: setup.repo), skills: skills)
        }
    }

    @Test func pendingUpgradesOfTheSameSourceMerge() throws {
        let setup = try SkillsRepoFixture()
        try PendingChanges.record(PendingChange(kind: .upgrade, skills: ["beta"], source: "s", from: "v1", to: "v2"), repo: setup.repo)
        try PendingChanges.record(PendingChange(kind: .upgrade, skills: ["beta"], source: "s", from: "v2", to: "v3"), repo: setup.repo)
        let pending = PendingChanges.load(repo: setup.repo)
        #expect(pending.changes.count == 1)
        #expect(pending.changes[0].from == "v1" && pending.changes[0].to == "v3")
    }
}

/// A first-party plugin whose `upstream/` pin moves, re-checked by a stub agent.
@Suite struct RecheckAndCommitTests {
    struct PluginFixture {
        let setup: SkillsRepoFixture
        let plan: UpgradePlan

        init(_ name: String = #function) throws {
            setup = try SkillsRepoFixture(name)
            let fixture = setup.fixture
            try fixture.write("repo/first-party/alpha/.claude-plugin/plugin.json", "{\n  \"name\": \"alpha\",\n  \"version\": \"0.1.0\"\n}\n")
            try fixture.write("repo/.claude-plugin/marketplace.json", """
            {"plugins": [{"name": "other", "version": "9.9.9"}, {"name": "alpha", "source": {}, "version": "0.1.0"}]}
            """)
            try fixture.write("repo/tools/config/recheck.json", #"{"agent": "stub", "commands": {"stub": ["stub", "{prompt}"]}, "timeoutMinutes": 1}"#)
            try fixture.write("repo/tools/config/prompts/recheck.md", "Re-check {{plugin}} against {{upstream}} {{to}} (was {{from}}) in {{skillsPath}}.")
            try fixture.git("-c", "protocol.file.allow=always", "submodule", "add", "--quiet",
                            fixture.url("origin-beta").path, "first-party/alpha/upstream", in: "repo")
            try fixture.git("checkout", "--quiet", "v1.0.0", in: "repo/first-party/alpha/upstream")
            try fixture.git("add", ".", in: "repo")
            try fixture.git("commit", "--quiet", "-m", "alpha upstream", in: "repo")

            let (repository, skills) = try setup.load()
            let source = try #require(try Submodules.load(repo: setup.repo).first { $0.path == "first-party/alpha/upstream" })
            plan = try #require(try Upgrader.plan(source: source, repo: repository, skills: skills, to: nil))
            try Upgrader.apply(plan, repo: setup.repo)
        }

        func recheck(_ agent: @escaping @Sendable (URL) throws -> Void, validate: Rechecker.Validator = { _ in nil }) throws -> RecheckResult {
            let config = try RecheckConfig.load(repo: setup.repo)
            return try Rechecker.run(plan: plan, repo: setup.repo, config: config, runAgent: { command, directory, _ in
                #expect(command.last == "Re-check alpha against origin-beta v1.1.0 (was v1.0.0) in first-party/alpha/skills.")
                try agent(directory)
                return 0
            }, validate: validate)
        }
    }

    @Test func keepsSkillEditsAndRevertsEverythingElse() throws {
        let plugin = try PluginFixture()
        let result = try plugin.recheck { repo in
            try "updated".write(to: repo.appendingPathComponent("first-party/alpha/skills/alpha/SKILL.md"), atomically: true, encoding: .utf8)
            try "stray".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            try "stray".write(to: repo.appendingPathComponent("skills.json"), atomically: true, encoding: .utf8)
        }
        #expect(result.outcome == .changed)
        #expect(result.changed == ["first-party/alpha/skills/alpha/SKILL.md"])
        #expect(result.reverted == ["README.md", "skills.json"])
        #expect(!FileManager.default.fileExists(atPath: plugin.setup.repo.appendingPathComponent("README.md").path))
        #expect(try String(contentsOf: plugin.setup.repo.appendingPathComponent("skills.json"), encoding: .utf8).contains("alpha"))
    }

    @Test func reportsUnchangedAndFailsOnValidation() throws {
        let plugin = try PluginFixture()
        #expect(try plugin.recheck { _ in }.outcome == .unchanged)
        #expect(throws: RecheckError.self) { try plugin.recheck({ _ in }, validate: { _ in "broken" }) }
    }

    @Test func commitsPluginWithVersionBumpAndLeavesOtherChangesStaged() throws {
        let plugin = try PluginFixture()
        let repo = plugin.setup.repo
        _ = try plugin.recheck { repo in
            try "updated".write(to: repo.appendingPathComponent("first-party/alpha/skills/alpha/SKILL.md"), atomically: true, encoding: .utf8)
        }
        try plugin.setup.fixture.write("repo/unrelated.txt", "keep me staged")
        try plugin.setup.fixture.git("add", "unrelated.txt", in: "repo")

        let pending = PendingChanges(changes: [PendingChange(kind: .upgrade, skills: [], source: plugin.plan.source.path,
                                                             from: "v1.0.0", to: "v1.1.0", plugin: "alpha", recheck: .changed)])
        let groups = Committer.plan(pending, upstreamNames: [plugin.plan.source.path: "Beta"])
        #expect(groups.count == 1)
        #expect(groups[0].subject == "docs(alpha): refresh guidance for Beta v1.1.0")

        let (old, new) = try Committer.bumpVersion(plugin: "alpha", bump: .minor, repo: repo)
        #expect(old == "0.1.0" && new == "0.2.0")
        let marketplace = try String(contentsOf: repo.appendingPathComponent(".claude-plugin/marketplace.json"), encoding: .utf8)
        #expect(marketplace.contains(#""name": "other", "version": "9.9.9""#))
        #expect(marketplace.contains(#""name": "alpha", "source": {}, "version": "0.2.0""#))

        _ = try Committer.commit(groups[0], repo: repo)
        let git = Git(repo)
        #expect(try git.run("log", "-1", "--format=%s") == "docs(alpha): refresh guidance for Beta v1.1.0")
        let committed = try git.run("show", "--name-only", "--format=", "HEAD").split(separator: "\n").map(String.init).sorted()
        #expect(committed == [".claude-plugin/marketplace.json", "first-party/alpha/.claude-plugin/plugin.json",
                              "first-party/alpha/skills/alpha/SKILL.md", "first-party/alpha/upstream"])
        #expect(try git.run("diff", "--cached", "--name-only") == "unrelated.txt")
    }

    @Test(arguments: [(VersionBump.patch, "1.2.4"), (.minor, "1.3.0"), (.major, "2.0.0")])
    func bumpsSemver(_ bump: VersionBump, _ expected: String) {
        #expect(bump.apply(to: "1.2.3") == expected)
    }
}
