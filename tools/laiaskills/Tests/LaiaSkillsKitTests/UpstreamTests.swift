import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

/// Uses real git repos: an "origin" plus a clone standing in for a submodule checkout.
@Suite struct UpstreamTests {
    @Test func taggedPinReportsNewerRelease() throws {
        let fixture = try Fixture()
        try fixture.originRepo("origin", commits: [("a", "v1.0.0"), ("b", "v1.1.0-rc1"), ("c", "v1.1.0")])
        try fixture.git("clone", "--quiet", fixture.url("origin").path, "repo/source")
        try fixture.git("checkout", "--quiet", "v1.0.0", in: "repo/source")

        let submodule = Submodule(name: "s", path: "source", url: "", branch: nil, shallow: false)
        let status = UpstreamChecker.status(of: submodule, repo: fixture.url("repo"), fetch: false)
        #expect(status.mode == .tagged)
        #expect(status.pinnedTag == "v1.0.0")
        #expect(status.latest == "v1.1.0")
        #expect(status.state == .outdated)
    }

    @Test func taggedPinOnNewestReleaseIsUpToDate() throws {
        let fixture = try Fixture()
        try fixture.originRepo("origin", commits: [("a", "v1.0.0"), ("b", "v1.1.0")])
        try fixture.git("clone", "--quiet", fixture.url("origin").path, "repo/source")
        try fixture.git("checkout", "--quiet", "v1.1.0", in: "repo/source")

        let submodule = Submodule(name: "s", path: "source", url: "", branch: nil, shallow: false)
        let status = UpstreamChecker.status(of: submodule, repo: fixture.url("repo"), fetch: true)
        #expect(status.state == .upToDate)
        #expect(status.note == nil)
    }

    @Test func untaggedPinComparesWithBranch() throws {
        let fixture = try Fixture()
        try fixture.originRepo("origin", commits: [("a", nil), ("b", nil), ("c", nil)])
        try fixture.git("clone", "--quiet", fixture.url("origin").path, "repo/source")
        try fixture.git("checkout", "--quiet", "HEAD~2", in: "repo/source")

        let submodule = Submodule(name: "s", path: "source", url: "", branch: nil, shallow: false)
        let status = UpstreamChecker.status(of: submodule, repo: fixture.url("repo"), fetch: false)
        #expect(status.mode == .branch)
        #expect(status.latest == "main")
        #expect(status.commitsBehind == 2)
        #expect(status.state == .outdated)
    }

    @Test func missingCheckoutIsUnknown() throws {
        let fixture = try Fixture()
        let submodule = Submodule(name: "s", path: "absent", url: "", branch: nil, shallow: false)
        let status = UpstreamChecker.status(of: submodule, repo: fixture.root, fetch: false)
        #expect(status.state == .unknown)
        #expect(status.note == "not checked out")
    }
}

@Suite struct DoctorTests {
    @Test func flagsDuplicateClaudePluginSkills() throws {
        let fixture = try Fixture()
        try fixture.skill("plugins/cache/visionos/skills/spatial", name: "spatial")
        try fixture.write("home/.claude/plugins/installed_plugins.json", """
        {"version": 2, "plugins": {"visionos@market": [{"installPath": "\(fixture.url("plugins/cache/visionos").path)"}]}}
        """)
        let findings = Doctor.claudePluginFindings(managedNames: ["spatial"],
                                                   environment: Environment(home: fixture.url("home")))
        #expect(findings.count == 1)
        #expect(findings.first?.message.contains("visionos@market") == true)
    }

    /// A marketplace whose plugins use the whole repo as their root and pick skills by path.
    @Test func readsPluginSkillsFromMarketplaceEntry() throws {
        let fixture = try Fixture()
        let install = fixture.url("cache/market/bundle/1.0.0")
        try fixture.skill("cache/market/bundle/1.0.0/first-party/bundle/skills/spatial", name: "spatial")
        try fixture.skill("cache/market/bundle/1.0.0/first-party/other/skills/mise", name: "mise")
        try fixture.write("clones/market/.claude-plugin/marketplace.json", """
        {"plugins": [{"name": "bundle", "skills": ["./first-party/bundle/skills/spatial"]}]}
        """)
        try fixture.write("home/.claude/plugins/known_marketplaces.json", """
        {"market": {"installLocation": "\(fixture.url("clones/market").path)"}}
        """)
        try fixture.write("home/.claude/plugins/installed_plugins.json", """
        {"version": 2, "plugins": {"bundle@market": [{"installPath": "\(install.path)"}]}}
        """)
        let findings = Doctor.claudePluginFindings(managedNames: ["spatial", "mise"],
                                                   environment: Environment(home: fixture.url("home")))
        #expect(findings.count == 1)
        #expect(findings.first?.message.contains("spatial") == true)
        #expect(findings.first?.message.contains("mise") == false)
    }

    @Test func flagsStaleSkillsCLILockEntries() throws {
        let fixture = try Fixture()
        try fixture.skill("home/.agents/skills/kept", name: "kept")
        try fixture.write("home/.agents/.skill-lock.json", #"{"skills": {"gone": {}, "kept": {}}}"#)
        let environment = Environment(home: fixture.url("home"))
        let inspector = InstallInspector(
            agents: AgentsConfig(hub: AgentTarget(path: "~/.agents/skills"), mirrors: [:]),
            environment: environment
        )
        let findings = Doctor.skillsCLIFindings(managedNames: ["kept"], inspector: inspector, environment: environment)
        #expect(findings.map(\.severity) == [.warning, .info])
        #expect(findings[0].message.hasPrefix("gone:"))
    }
}
