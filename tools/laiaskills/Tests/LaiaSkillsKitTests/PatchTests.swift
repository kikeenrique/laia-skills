import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

@Suite struct PatchTests {
    /// Installs beta (pinned at v1.0.0), edits the installed copy, and saves the edit as a patch.
    private func patchedBeta(_ setup: SkillsRepoFixture, edit: (URL) throws -> Void, reason: String) throws -> URL {
        var (installer, skills) = try setup.installer()
        let beta = try #require(skills["beta"])
        try installer.install(beta)
        try edit(setup.fixture.url("home/.agents/skills/beta"))
        let (repository, _) = try setup.load()
        let file = try Patches.save(skill: beta, reason: reason, from: nil, repo: repository,
                                    hub: installer.hub, date: "2026-10-04")
        try installer.install(beta)
        return file
    }

    @Test func savesEditsAsAPatchAndReappliesItOnInstall() throws {
        let setup = try SkillsRepoFixture()
        let file = try patchedBeta(setup, edit: { folder in
            try "---\nname: beta\ndescription: \"Patched.\"\n---\n".write(
                to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }, reason: "Avoid eval on user input (audit 2026-06)")

        #expect(file.lastPathComponent == "0001-avoid-eval-on-user-input-audit-2026-06.patch")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("Reason: Avoid eval on user input (audit 2026-06)\nDate: 2026-10-04\n\ndiff --git a/SKILL.md b/SKILL.md"))
        #expect(try setup.fixture.read("home/.agents/skills/beta/SKILL.md").contains("Patched."))

        var (installer, skills) = try setup.installer()
        let beta = try #require(skills["beta"])
        #expect(installer.status(of: beta) == .upToDate)
        #expect(InstallState.load(setup.environment)?.skills["beta"]?.patches?.keys.first == file.lastPathComponent)

        // Removing the patch makes the copy out of date; a reinstall restores upstream's text.
        try FileManager.default.removeItem(at: file)
        (installer, skills) = try setup.installer()
        #expect(installer.status(of: beta) == .notSynced)
        try installer.install(beta)
        #expect(try !setup.fixture.read("home/.agents/skills/beta/SKILL.md").contains("Patched."))
    }

    @Test func refusesFirstPartySkillsAndCopiesWithoutEdits() throws {
        let setup = try SkillsRepoFixture()
        var (installer, skills) = try setup.installer()
        let (repository, _) = try setup.load()
        #expect(throws: PatchError.self) {
            try Patches.save(skill: try #require(skills["alpha"]), reason: "x", from: nil, repo: repository,
                             hub: installer.hub, date: "2026-10-04")
        }
        let beta = try #require(skills["beta"])
        try installer.install(beta)
        #expect(throws: PatchError.self) {
            try Patches.save(skill: beta, reason: "x", from: nil, repo: repository, hub: installer.hub, date: "2026-10-04")
        }
    }

    /// v1.1.0 adds `references/notes.md` with "v1.1 notes": a patch adding the same file is dropped on
    /// upgrade, a patch adding different content conflicts.
    @Test(arguments: [("v1.1 notes", true), ("our own notes", false)])
    func upgradeDropsPatchesUpstreamContainsAndReportsConflicts(_ content: String, _ fixedUpstream: Bool) throws {
        let setup = try SkillsRepoFixture()
        let file = try patchedBeta(setup, edit: { folder in
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("references"), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: folder.appendingPathComponent("references/notes.md"))
        }, reason: "add notes")
        try setup.fixture.git("add", "patches", in: "repo")
        try setup.fixture.git("commit", "--quiet", "-m", "patch", in: "repo")

        try setup.fixture.git("checkout", "--quiet", "v1.1.0", in: "repo/third-party/o__beta")
        try setup.fixture.git("add", "third-party/o__beta", in: "repo")
        let (installer, skills) = try setup.installer()
        let review = try Patches.review(try #require(skills["beta"]), repo: setup.repo, scratch: installer.hub)

        if fixedUpstream {
            #expect(review == Patches.Review(dropped: ["patches/beta/\(file.lastPathComponent)"], conflicts: []))
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(try setup.fixture.git("diff", "--cached", "--name-status", "--", "patches", in: "repo").hasPrefix("D"))
        } else {
            #expect(review.dropped.isEmpty)
            #expect(review.conflicts.count == 1)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func commitsPatchesAndDroppedPatches() {
        let pending = PendingChanges(changes: [
            PendingChange(kind: .patch, skills: ["beta"], source: "third-party/o__beta", to: "v1.0.0",
                          patch: "patches/beta/0001-avoid-eval.patch", reason: "avoid eval on user input"),
            PendingChange(kind: .upgrade, skills: ["gamma"], source: "third-party/o__gamma", from: "v1", to: "v2",
                          droppedPatches: ["patches/gamma/0001-fix.patch"]),
        ])
        let groups = Committer.plan(pending, upstreamNames: [:])
        let patch = groups.first { $0.subject.hasPrefix("fix(") }
        #expect(patch?.subject == "fix(beta): avoid eval on user input")
        #expect(patch?.paths == ["patches/beta/0001-avoid-eval.patch"])
        let bump = groups.first { $0.subject.hasPrefix("chore(third-party)") }
        // The skill's whole patch folder rides along, for patches edited or deleted by hand after a
        // stopped upgrade.
        #expect(bump?.paths == ["third-party/o__gamma", "patches/gamma/0001-fix.patch", "patches/gamma"])
        #expect(bump?.body.contains("Drops patches the new version already contains") == true)
    }

    @Test func aBumpLeavesASkillsPendingPatchToItsOwnCommit() {
        let pending = PendingChanges(changes: [
            PendingChange(kind: .upgrade, skills: ["beta", "delta"], source: "third-party/o__beta", from: "v1", to: "v2"),
            PendingChange(kind: .patch, skills: ["beta"], source: "third-party/o__beta", to: "v2",
                          patch: "patches/beta/0002-new-fix.patch", reason: "new fix"),
        ])
        let groups = Committer.plan(pending, upstreamNames: [:])
        let bump = groups.first { $0.subject.hasPrefix("chore(third-party)") }
        #expect(bump?.paths == ["third-party/o__beta", "patches/delta"])
        #expect(groups.first { $0.subject.hasPrefix("fix(") }?.paths == ["patches/beta/0002-new-fix.patch"])
    }

    @Test(arguments: [
        ("Avoid eval on user input (audit 2026-06)", "avoid-eval-on-user-input-audit-2026-06"),
        ("¡¡!!", "patch"),
        ("use printf -v instead of eval on user input (security audit)", "use-printf-v-instead-of-eval-on-user-input"),
    ])
    func slugsReasons(_ reason: String, _ expected: String) {
        #expect(Patches.slug(reason) == expected)
    }
}
