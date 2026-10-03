import Foundation
import Testing
@testable import LaiaSkillsKit

@Suite struct FrontmatterTests {
    @Test func readsUnquotedName() {
        #expect(SkillDiscovery.frontmatterName(in: "---\nname: mise\ndescription: x\n---\n") == "mise")
    }

    @Test(arguments: ["\"mise\"", "'mise'"])
    func readsQuotedName(_ value: String) {
        #expect(SkillDiscovery.frontmatterName(in: "---\nname: \(value)\n---\n") == "mise")
    }

    @Test func ignoresFilesWithoutFrontmatter() {
        #expect(SkillDiscovery.frontmatterName(in: "# mise\nname: mise\n") == nil)
    }

    @Test func ignoresNameAfterFrontmatter() {
        #expect(SkillDiscovery.frontmatterName(in: "---\ndescription: x\n---\nname: mise\n") == nil)
    }

    @Test func ignoresIndentedNameKeys() {
        #expect(SkillDiscovery.frontmatterName(in: "---\nmetadata:\n  name: nested\nname: top\n---\n") == "top")
    }
}

@Suite struct ReleaseVersionTests {
    @Test(arguments: ["v1.4.2", "0.6.0", "v2026.9.4", "1.0"])
    func acceptsStableReleases(_ tag: String) {
        #expect(ReleaseVersion(tag: tag) != nil)
    }

    @Test(arguments: ["v1.0.0-rc1", "latest", "1", "v1..2", "release-1.0"])
    func rejectsOtherTags(_ tag: String) {
        #expect(ReleaseVersion(tag: tag) == nil)
    }

    @Test func comparesNumerically() throws {
        let older = try #require(ReleaseVersion(tag: "v1.9.0"))
        let newer = try #require(ReleaseVersion(tag: "v1.10.0"))
        #expect(older < newer)
        #expect(try #require(ReleaseVersion(tag: "v2026.9.4")) < #require(ReleaseVersion(tag: "v2026.10.0")))
        #expect(try #require(ReleaseVersion(tag: "1.2")) == #require(ReleaseVersion(tag: "v1.2.0")))
    }
}

@Suite struct ConfigTests {
    @Test func parsesGitmodules() {
        let output = """
        submodule.replay/upstream.path first-party/replay/upstream
        submodule.replay/upstream.url https://github.com/mattt/Replay.git
        submodule.big.path third-party/github__awesome-copilot
        submodule.big.url https://github.com/github/awesome-copilot
        submodule.big.shallow true
        submodule.big.branch main
        """
        let modules = Submodules.parse(output)
        #expect(modules.count == 2)
        #expect(modules[0] == Submodule(name: "replay/upstream", path: "first-party/replay/upstream",
                                        url: "https://github.com/mattt/Replay.git", branch: nil, shallow: false))
        #expect(modules[0].isFirstPartyUpstream)
        #expect(modules[1].shallow && modules[1].branch == "main" && !modules[1].isFirstPartyUpstream)
    }

    @Test func expandsTilde() {
        let home = URL(fileURLWithPath: "/home/someone")
        #expect(expandTilde("~/.agents/skills", home: home).path == "/home/someone/.agents/skills")
        #expect(expandTilde("/opt/skills", home: home).path == "/opt/skills")
    }

    @Test func decodesManifest() throws {
        let json = #"{"skills": {"mise": {"source": "first-party"}, "x": {"source": "third-party/a__b", "path": "x"}}}"#
        let manifest = try JSONDecoder().decode(SkillsManifest.self, from: Data(json.utf8))
        #expect(manifest.skills["mise"] == SkillEntry(source: "first-party"))
        #expect(manifest.skills["x"]?.path == "x")
    }
}
