import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

@Suite struct BrowserTests {
    /// The standard fixture plus an origin `origins/acme/tools` (tagged v2.0.0) holding `alpha` (a name
    /// the fixture already manages), `gamma` (also in the hub, put there by another tool), and `delta`
    /// (two copies, with a reference file and an executable script).
    private func setUp() throws -> SkillsRepoFixture {
        let setup = try SkillsRepoFixture()
        let fixture = setup.fixture
        try fixture.originRepo("origins/acme/tools", commits: [("README", nil)])
        try fixture.skill("origins/acme/tools/skills/alpha", name: "alpha")
        try fixture.skill("origins/acme/tools/skills/gamma", name: "gamma")
        try fixture.write("origins/acme/tools/skills/delta/SKILL.md",
                          "---\nname: delta\ndescription: >-\n  Folded\n  description.\n---\n\n# delta\n")
        try fixture.write("origins/acme/tools/skills/delta/references/notes.md", "notes")
        try fixture.write("origins/acme/tools/skills/delta/scripts/run.sh", "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: fixture.url("origins/acme/tools/skills/delta/scripts/run.sh").path)
        try fixture.skill("origins/acme/tools/docs/ja/skills/delta", name: "delta")
        try fixture.git("add", ".", in: "origins/acme/tools")
        try fixture.git("commit", "--quiet", "-m", "skills", in: "origins/acme/tools")
        try fixture.git("tag", "v2.0.0", in: "origins/acme/tools")
        try fixture.write("home/.agents/skills/gamma/SKILL.md", "installed by another tool")
        return setup
    }

    private func spec(_ setup: SkillsRepoFixture) throws -> SourceSpec {
        try SourceSpec("file://\(setup.fixture.url("origins/acme/tools").path)")
    }

    @Test func rowsShowEachSkillsStatus() throws {
        let setup = try setUp()
        let (repository, skills) = try setup.load()
        let installer = Installer(repo: repository, environment: setup.environment)
        let inspector = InstallInspector(agents: repository.agents, environment: setup.environment)

        let rows = Browser.rows(under: setup.fixture.url("origins/acme/tools"), source: "third-party/acme__tools",
                                skills: skills, installer: installer, inspector: inspector)
        #expect(rows.map(\.name) == ["alpha", "delta", "gamma"])
        #expect(rows.map(\.status) == [.nameTaken, .available, .otherTool])
        #expect(rows.map(\.status.canAdd) == [false, true, true])
        let delta = try #require(rows.first { $0.name == "delta" })
        #expect(delta.path == "skills/delta")
        #expect(delta.copies == 2)
        #expect(delta.description == "Folded description.")

        // The fixture's own submodule: listed until installed.
        let beta = { Browser.rows(under: setup.repo.appendingPathComponent("third-party/o__beta"), source: "third-party/o__beta",
                                  skills: skills, installer: Installer(repo: repository, environment: setup.environment),
                                  inspector: inspector).first?.status }
        #expect(beta() == .listed)
        var writer = installer
        try writer.install(try #require(skills.first { $0.name == "beta" }))
        #expect(beta() == .installed)
    }

    @Test func previewClonesOnlyTheSkillFilesAtTheNewestTag() throws {
        let setup = try setUp()
        let preview = try PreviewClone.make(try spec(setup), repo: setup.repo)
        #expect(preview.tag == "v2.0.0")
        #expect(preview.versionLabel == "v2.0.0 (preview)")
        #expect(preview.folder.path.hasPrefix(setup.repo.appendingPathComponent("tmp/laiaskills-browse").path))
        #expect(FileManager.default.fileExists(atPath: preview.folder.appendingPathComponent("skills/delta/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: preview.folder.appendingPathComponent("skills/delta/references/notes.md").path))
        #expect(Adder.skills(under: preview.folder).count == 4)

        // ls-tree lists the files that weren't checked out, with the executable bit.
        let files = try Browser.files(of: "skills/delta", in: preview.folder)
        #expect(files.map(\.path) == ["SKILL.md", "references/notes.md", "scripts/run.sh"])
        #expect(files.filter(\.needsAudit).map(\.path) == ["scripts/run.sh"])
        #expect(files.first { $0.path == "scripts/run.sh" }?.executable == true)

        preview.remove()
        #expect(!setup.fixture.exists("repo/tmp/laiaskills-browse"))
    }

    @Test func previewOfAnUntaggedRepoUsesTheBranchHead() throws {
        let setup = try setUp()
        try setup.fixture.git("tag", "-d", "v2.0.0", in: "origins/acme/tools")
        let preview = try PreviewClone.make(try spec(setup), repo: setup.repo)
        defer { preview.remove() }
        #expect(preview.tag == nil)
        #expect(preview.versionLabel == "\(preview.commit.prefix(7)) (preview)")
    }

    @Test func leftoversAreDeletedOnlyOnceTheyAreOld() throws {
        let setup = try SkillsRepoFixture()
        try setup.fixture.mkdir("repo/tmp/laiaskills-browse/acme__tools-1234")
        PreviewClone.cleanLeftovers(repo: setup.repo)
        #expect(setup.fixture.exists("repo/tmp/laiaskills-browse/acme__tools-1234"))
        PreviewClone.cleanLeftovers(repo: setup.repo, now: Date().addingTimeInterval(7200))
        #expect(!setup.fixture.exists("repo/tmp/laiaskills-browse/acme__tools-1234"))
    }

    @Test func readsTheCanonicalNameFromOgURL() {
        let html = #"<head><meta property="og:url" content="https://github.com/AvdLee/SwiftUI-Agent-Skill" /></head>"#
        #expect(Browser.ogURL(in: html) == "https://github.com/AvdLee/SwiftUI-Agent-Skill")
        #expect(Browser.ogURL(in: #"<meta property="og:url" content="https://github.com/AvdLee" />"#) == nil)
        #expect(Browser.ogURL(in: "<html></html>") == nil)
    }

    @Test func frontmatterReadsBlockScalars() {
        let text = "---\nname: x\ndescription: |-\n  First line\n  second line.\nmetadata: y\n---\n"
        #expect(SkillDiscovery.frontmatterValue("description", in: text) == "First line second line.")
        #expect(SkillDiscovery.frontmatterValue("metadata", in: text) == "y")
    }
}

@Suite struct CatalogTests {
    @Test func decodesResultsAndSkipsIncompleteOnes() throws {
        let json = """
        {"query": "swiftui", "skills": [
          {"id": "a/b/c", "source": "avdlee/swiftui-agent-skill", "skillId": "swiftui-expert-skill", "name": "x", "installs": 33718},
          {"source": "o/r", "skillId": "minimal"},
          {"source": "o/r"}
        ], "count": 3}
        """
        let results = try Catalog.decode(Data(json.utf8))
        #expect(results == [
            CatalogResult(source: "avdlee/swiftui-agent-skill", skillId: "swiftui-expert-skill", name: "x", installs: 33718),
            CatalogResult(source: "o/r", skillId: "minimal"),
        ])
        #expect(throws: CatalogError.self) { try Catalog.decode(Data("<html>".utf8)) }
        #expect(throws: CatalogError.self) { try Catalog.decode(Data(#"{"results": []}"#.utf8)) }
    }

    @Test func rejectsShortQueriesAndEncodesTheRest() throws {
        #expect(throws: CatalogError.self) { try Catalog.search(" a ", limit: 5, endpoint: "file:///nowhere") }
        #expect(Catalog.url("swift & ui", limit: 5, endpoint: "https://e/api") == "https://e/api?q=swift%20%26%20ui&limit=5")
    }

    @Test func statusComparesIgnoringCase() {
        let skills = ["swiftui-expert-skill": SkillEntry(source: "third-party/AvdLee__SwiftUI-Agent-Skill"),
                      "pdf": SkillEntry(source: "third-party/someone__else")]
        let submodules = [Submodule(name: "s", path: "third-party/AvdLee__SwiftUI-Agent-Skill", url: "u", branch: nil, shallow: false)]
        func status(_ source: String, _ skill: String) -> String {
            Catalog.status(of: CatalogResult(source: source, skillId: skill), skills: skills, submodules: submodules)
        }
        #expect(status("avdlee/swiftui-agent-skill", "swiftui-expert-skill") == "managed")
        #expect(status("avdlee/swiftui-agent-skill", "update-swiftui-apis") == "source added")
        #expect(status("anthropics/skills", "pdf") == "name taken")
        #expect(status("anthropics/skills", "docx") == "—")
        #expect(status("uizze.sh", "ios-design") == Catalog.unsupported)
    }
}
