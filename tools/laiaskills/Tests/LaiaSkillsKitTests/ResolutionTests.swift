import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

@Suite struct ResolutionTests {
    let source = Submodule(name: "s", path: "third-party/o__r", url: "https://example.com/o/r", branch: nil, shallow: false)

    @Test func discoverySkipsVendoredAndFixtureFolders() throws {
        let fixture = try Fixture()
        try fixture.skill("src/skills/a", name: "a")
        try fixture.skill("src/node_modules/pkg/a", name: "a")
        try fixture.skill("src/.git/a", name: "a")
        try fixture.skill("src/evals/a", name: "a")
        let found = SkillDiscovery.folders(named: "a", under: fixture.url("src"))
        #expect(found.map { relativePath(of: $0, to: fixture.root) } == ["src/skills/a"])
    }

    @Test func resolvesFirstPartySkill() throws {
        let fixture = try Fixture()
        try fixture.skill("first-party/mise/skills/mise", name: "mise")
        try fixture.skill("first-party/mise/upstream/skills/mise", name: "mise")
        let skill = SkillResolver.resolve(name: "mise", entry: SkillEntry(source: "first-party"),
                                          repo: fixture.root, submodules: [])
        #expect(skill.problem == nil)
        #expect(skill.plugin == "mise")
        #expect(skill.folder.map { relativePath(of: $0, to: fixture.root) } == "first-party/mise/skills/mise")
    }

    @Test func resolvesSubmoduleSkillByName() throws {
        let fixture = try Fixture()
        try fixture.write("third-party/o__r/.git", "gitdir: elsewhere")
        try fixture.skill("third-party/o__r/deep/folder/b", name: "b")
        let skill = SkillResolver.resolve(name: "b", entry: SkillEntry(source: source.path),
                                          repo: fixture.root, submodules: [source])
        #expect(skill.problem == nil)
        #expect(skill.submodulePath == source.path)
    }

    /// Some upstreams capitalize the name (`watchOS`); the skills.json key is the lowercase form.
    @Test func matchesNamesIgnoringCase() throws {
        let fixture = try Fixture()
        try fixture.write("third-party/o__r/.git", "gitdir: elsewhere")
        try fixture.skill("third-party/o__r/skills/watchos", name: "watchOS")
        let skill = SkillResolver.resolve(name: "watchos", entry: SkillEntry(source: source.path),
                                          repo: fixture.root, submodules: [source])
        #expect(skill.problem == nil)

        let available = Adder.skills(in: source.path, repo: fixture.root)
        let found = try #require(Adder.find("watchos", in: available))
        #expect(Array(Adder.entries(for: [found], all: available, source: source.path).keys) == ["watchos"])
    }

    @Test func reportsAmbiguousAndMissingSkills() throws {
        let fixture = try Fixture()
        try fixture.write("third-party/o__r/.git", "gitdir: elsewhere")
        try fixture.skill("third-party/o__r/b", name: "b")
        try fixture.skill("third-party/o__r/b/skills/b", name: "b")
        let ambiguous = SkillResolver.resolve(name: "b", entry: SkillEntry(source: source.path),
                                              repo: fixture.root, submodules: [source])
        #expect(ambiguous.problem?.contains("ambiguous") == true)

        let pinned = SkillResolver.resolve(name: "b", entry: SkillEntry(source: source.path, path: "b"),
                                           repo: fixture.root, submodules: [source])
        #expect(pinned.problem == nil)

        let missing = SkillResolver.resolve(name: "c", entry: SkillEntry(source: source.path),
                                            repo: fixture.root, submodules: [source])
        #expect(missing.problem?.contains("moved or removed") == true)
    }

    @Test func rejectsSourcesThatAreNotSubmodules() throws {
        let fixture = try Fixture()
        let skill = SkillResolver.resolve(name: "b", entry: SkillEntry(source: "third-party/unknown"),
                                          repo: fixture.root, submodules: [source])
        #expect(skill.problem?.contains("not a submodule") == true)
    }
}

@Suite struct InstallInspectorTests {
    @Test func classifiesHubAndMirrorEntries() throws {
        let fixture = try Fixture()
        try fixture.skill("home/.agents/skills/managed", name: "managed")
        try fixture.skill("home/.agents/skills/foreign", name: "foreign")
        try fixture.write("home/.agents/.laiaskills.json", #"{"skills": {"managed": {"commit": "abc"}}}"#)
        try fixture.symlink("home/.claude/skills/managed", to: "../../.agents/skills/managed")
        try fixture.symlink("home/.claude/skills/gone", to: "../../.agents/skills/gone")
        try fixture.skill("home/.claude/skills/foreign", name: "foreign")

        let agents = AgentsConfig(hub: AgentTarget(path: "~/.agents/skills"),
                                  mirrors: ["claude": AgentTarget(path: "~/.claude/skills")])
        let inspector = InstallInspector(agents: agents, environment: Environment(home: fixture.url("home")))
        let mirror = fixture.url("home/.claude/skills")

        #expect(inspector.hubState("managed") == .managed)
        #expect(inspector.hubState("foreign") == .foreign)
        #expect(inspector.hubState("absent") == .missing)
        #expect(inspector.mirrorState("managed", in: mirror) == .linked)
        #expect(inspector.mirrorState("gone", in: mirror) == .broken)
        #expect(inspector.mirrorState("foreign", in: mirror) == .bypass)
        #expect(inspector.mirrorState("absent", in: mirror) == .missing)
        #expect(inspector.entries(in: mirror) == ["foreign", "gone", "managed"])
    }
}
