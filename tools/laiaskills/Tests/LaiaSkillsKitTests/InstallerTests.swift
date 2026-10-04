import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

@Suite struct InstallerTests {
    @Test func installsCommittedFilesWithModesLinksAndMirrors() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        let record = try installer.install(alpha)

        let installed = setup.fixture.url("home/.agents/skills/alpha")
        #expect(FileManager.default.isExecutableFile(atPath: installed.appendingPathComponent("scripts/run.sh").path))
        #expect(try Data(contentsOf: installed.appendingPathComponent("icon.png")) == Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF]))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: installed.appendingPathComponent("LINK.md").path) == "SKILL.md")
        #expect(record.files?.count == 4)
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: setup.fixture.url("home/.claude/skills/alpha").path) == "../../.agents/skills/alpha")
        #expect(installer.status(of: alpha) == .upToDate)
        #expect(InstallState.load(setup.environment)?.skills["alpha"] == record)
    }

    @Test func detectsEditsAndOnlyOverwritesThemWhenForced() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        try installer.install(alpha)
        try "edited".write(to: setup.fixture.url("home/.agents/skills/alpha/SKILL.md"), atomically: true, encoding: .utf8)

        #expect(installer.status(of: alpha) == .modified(["SKILL.md"]))
        #expect(installer.plan([alpha], force: false).first?.action == .skipModified(["SKILL.md"]))
        #expect(installer.plan([alpha], force: true).first?.action == .reinstall)
    }

    @Test func comparesContentNotCommits() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        try installer.install(try #require(skills["alpha"]))

        // An unrelated commit leaves the skill up to date.
        try setup.fixture.write("repo/README.md", "unrelated")
        try setup.fixture.git("add", ".", in: "repo")
        try setup.fixture.git("commit", "--quiet", "-m", "readme", in: "repo")
        (installer, skills) = try setup.installer()
        #expect(installer.status(of: try #require(skills["alpha"])) == .upToDate)

        // A committed change to the skill makes it not synced; reinstalling backs up the old copy.
        try setup.fixture.write("repo/first-party/alpha/skills/alpha/references/new.md", "new")
        try setup.fixture.git("add", ".", in: "repo")
        try setup.fixture.git("commit", "--quiet", "-m", "alpha change", in: "repo")
        (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        #expect(installer.status(of: alpha) == .notSynced)
        try installer.install(alpha)
        #expect(installer.status(of: alpha) == .upToDate)
        #expect(try FileManager.default.contentsOfDirectory(atPath: installer.backups.path).count == 1)
    }

    @Test func submoduleSkillsInstallFromTheStagedPin() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let beta = try #require(skills["beta"])
        let first = try installer.install(beta)
        #expect(first.tag == "v1.0.0")

        // Move the pin and stage it, without committing: the staged pin is what installs.
        try setup.fixture.git("checkout", "--quiet", "v1.1.0", in: "repo/third-party/o__beta")
        try setup.fixture.git("add", "third-party/o__beta", in: "repo")
        (installer, skills) = try setup.installer()
        #expect(installer.status(of: try #require(skills["beta"])) == .notSynced)
        let second = try installer.install(try #require(skills["beta"]))
        #expect(second.tag == "v1.1.0")
        #expect(FileManager.default.fileExists(atPath: setup.fixture.url("home/.agents/skills/beta/references/notes.md").path))
    }

    @Test func replacesForeignCopiesAndRemovesUnlistedSkills() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.skill("home/.agents/skills/beta", name: "beta")
        var (installer, skills) = try setup.installer()
        let beta = try #require(skills["beta"])
        #expect(installer.status(of: beta) == .foreign)
        #expect(installer.plan([beta], force: false).first?.action == .replaceForeign)
        try installer.install(beta)
        #expect(installer.status(of: beta) == .upToDate)

        // Once beta leaves skills.json, the plan removes it.
        let removal = installer.plan([try #require(skills["alpha"])], force: false)
        #expect(removal.contains { $0.name == "beta" && $0.action == .remove })
        try installer.uninstall("beta")
        #expect(!FileManager.default.fileExists(atPath: setup.fixture.url("home/.agents/skills/beta").path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: setup.fixture.url("home/.claude/skills/beta").path)) == nil)
        #expect(InstallState.load(setup.environment)?.skills["beta"] == nil)
    }

    @Test func workingTreeInstallsAreMarkedAndReinstalledBySync() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.write("repo/first-party/alpha/skills/alpha/draft.md", "uncommitted")
        var (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        try installer.install(alpha, workingTree: true)
        #expect(FileManager.default.fileExists(atPath: setup.fixture.url("home/.agents/skills/alpha/draft.md").path))
        #expect(installer.status(of: alpha) == .workingTree)
        #expect(installer.plan([alpha], force: false).first?.action == .reinstall)
    }

    @Test func uncommittedSkillsCannotBeInstalledFromAPin() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.skill("repo/first-party/gamma/skills/gamma", name: "gamma")
        let skill = SkillResolver.resolve(name: "gamma", entry: SkillEntry(source: "first-party"),
                                          repo: setup.repo, submodules: [])
        #expect(throws: PinError.self) { try Pins.pin(for: skill, repo: setup.repo) }
    }

    @Test func skippedMirrorsGetNoLinkAndSyncRemovesOldOnes() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        try installer.install(try #require(skills["alpha"]))
        #expect(setup.fixture.exists("home/.claude/skills/alpha"))

        // Opting alpha out of the claude mirror makes sync remove the link, and only the link.
        try setup.fixture.write("repo/skills.json", """
        {"skills": {"alpha": {"source": "first-party", "skipMirrors": ["claude"]}, "beta": {"source": "third-party/o__beta"}}}
        """)
        (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        #expect(installer.status(of: alpha) == .upToDate)
        #expect(installer.plan([alpha], force: false).first?.action == .relink)
        try installer.linkMirrors(alpha)
        #expect(!setup.fixture.exists("home/.claude/skills/alpha"))
        #expect(setup.fixture.exists("home/.agents/skills/alpha/SKILL.md"))
        #expect(installer.plan([alpha], force: false).first?.action == .keep)

        // Claude's own copy in the skipped mirror is left alone by install and uninstall.
        try setup.fixture.skill("home/.claude/skills/alpha", name: "alpha")
        try installer.install(alpha)
        #expect(installer.mirrorsLinked(alpha))
        try installer.uninstall("alpha")
        #expect(setup.fixture.exists("home/.claude/skills/alpha/SKILL.md"))
    }

    @Test func syncRelinksAMissingMirrorLink() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let beta = try #require(skills["beta"])
        try installer.install(beta)
        try FileManager.default.removeItem(at: setup.fixture.url("home/.claude/skills/beta"))
        #expect(installer.plan([beta], force: false).first?.action == .relink)
        try installer.linkMirrors(beta)
        #expect(installer.plan([beta], force: false).first?.action == .keep)
    }

    @Test func manifestWritesSkipMirrors() throws {
        let fixture = try Fixture()
        let manifest = SkillsManifest(skills: ["a": SkillEntry(source: "first-party", skipMirrors: ["claude"])])
        try manifest.write(to: fixture.url("skills.json"))
        #expect(try fixture.read("skills.json").contains(#""a": { "source": "first-party", "skipMirrors": ["claude"] }"#))
        let decoded = try JSONDecoder().decode(SkillsManifest.self, from: Data(contentsOf: fixture.url("skills.json")))
        #expect(decoded.skills["a"]?.skips(mirror: "claude") == true)
    }

    @Test func keepsOnlyTheNewestBackups() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let alpha = try #require(skills["alpha"])
        for _ in 0..<5 { try installer.install(alpha) }
        let backups = try FileManager.default.contentsOfDirectory(atPath: installer.backups.path)
        #expect(backups.count == Installer.backupsKept)
    }

    @Test(arguments: [
        ("/h/.claude/skills", "/h/.agents/skills/x", "../../.agents/skills/x"),
        ("/h/a", "/h/a/b", "b"),
        ("/h/a/b", "/h/c", "../../c"),
    ])
    func computesRelativeLinks(_ from: String, _ to: String, _ expected: String) {
        #expect(relativeLink(from: URL(fileURLWithPath: from), to: URL(fileURLWithPath: to)) == expected)
    }
}
