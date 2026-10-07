import Foundation
import LaiaSkillsKit
import LaiaSkillsTestSupport
import Testing

/// `browse` and `find` end to end, without a terminal (tables and JSON). Offline: sources are local
/// origins and the skills.sh endpoint is a `file://` fixture.
@Suite struct BrowseCLITests {
    /// The standard fixture plus an unadded origin `origins/acme/tools` (v2.0.0) with skill `gamma`.
    private func setUp() throws -> (SkillsRepoFixture, String) {
        let setup = try SkillsRepoFixture()
        try setup.fixture.originRepo("origins/acme/tools", commits: [("README", nil)])
        try setup.fixture.skill("origins/acme/tools/skills/gamma", name: "gamma")
        try setup.fixture.write("origins/acme/tools/skills/gamma/scripts/setup.sh", "#!/bin/sh\n")
        try setup.fixture.git("add", ".", in: "origins/acme/tools")
        try setup.fixture.git("commit", "--quiet", "-m", "gamma", in: "origins/acme/tools")
        try setup.fixture.git("tag", "v2.0.0", in: "origins/acme/tools")
        return (setup, "file://\(setup.fixture.url("origins/acme/tools").path)")
    }

    @Test func browsesAnAddedSource() throws {
        let (setup, _) = try setUp()
        let report = try laiaskills(setup, "browse", "third-party/o__beta", "--json").jsonObject()
        #expect(report["preview"] as? Bool == false)
        #expect(report["version"] as? String == "v1.0.0")
        let skills = try #require(report["skills"] as? [[String: Any]])
        #expect(skills.map { $0["name"] as? String } == ["beta"])
        #expect(skills.first?["status"] as? String == "in skills.json")
    }

    @Test func browsesAnUnaddedRepoFromAThrowawayClone() throws {
        let (setup, url) = try setUp()
        let run = try laiaskills(setup, "browse", url, "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let report = try run.jsonObject()
        #expect(report["preview"] as? Bool == true)
        #expect(report["version"] as? String == "v2.0.0 (preview)")
        #expect((report["skills"] as? [[String: Any]])?.first?["status"] as? String == "—")
        #expect(!setup.fixture.exists("repo/tmp/laiaskills-browse"))
        // Looking never touches the repo.
        #expect(try setup.fixture.git("status", "--porcelain", in: "repo").isEmpty)

        let table = try laiaskills(setup, "browse", url)
        #expect(table.stdout.contains("gamma"))
        #expect(table.stdout.contains("laiaskills add \(url) --skill <name>"))
    }

    @Test func showsOneSkillWithItsFiles() throws {
        let (setup, url) = try setUp()
        let details = try laiaskills(setup, "browse", url, "--skill", "gamma", "--json").jsonObject()
        #expect((details["text"] as? String)?.contains("name: gamma") == true)
        let files = try #require(details["files"] as? [[String: Any]])
        #expect(files.map { $0["path"] as? String } == ["SKILL.md", "scripts/setup.sh"])

        let text = try laiaskills(setup, "browse", url, "--skill", "gamma")
        #expect(text.stdout.contains("# gamma"))
        #expect(text.stdout.contains("scripts/setup.sh"))

        let unknown = try laiaskills(setup, "browse", url, "--skill", "nope")
        #expect(unknown.status != 0)
        #expect(unknown.stderr.contains("available: gamma"))
    }

    @Test func findMarksWhatIsAlreadyHere() throws {
        let (setup, _) = try setUp()
        let catalog = try setup.fixture.write("catalog.json", """
        {"skills": [{"source": "o/beta", "skillId": "beta", "installs": 12},
                    {"source": "acme/tools", "skillId": "gamma", "installs": 3},
                    {"source": "example.com", "skillId": "site"}]}
        """)
        let environment = [Catalog.endpointVariable: catalog.absoluteString]
        let rows = try laiaskills(setup, environment: environment, ["find", "skills", "--json"]).jsonArray()
        #expect(rows.map { $0["status"] as? String } == ["managed", "—", Catalog.unsupported])
        #expect(rows.first?["installs"] as? Int == 12)

        let table = try laiaskills(setup, environment: environment, ["find", "skills"])
        #expect(table.stdout.contains("acme/tools"))
        #expect(table.stdout.contains("laiaskills browse owner/repo"))
    }

    @Test func findFailsWithAPointerToBrowse() throws {
        let (setup, _) = try setUp()
        let missing = try laiaskills(setup, environment: [Catalog.endpointVariable: "file:///nonexistent/catalog"], ["find", "skills"])
        #expect(missing.status != 0)
        #expect(missing.stderr.contains("laiaskills browse owner/repo"))
        #expect(try laiaskills(setup, "find", "x").stderr.contains("at least 2 characters"))
    }

    @Test func findWithoutAQueryNeedsATerminal() throws {
        let (setup, _) = try setUp()
        let result = try laiaskills(setup, "find")
        #expect(result.status != 0)
        #expect(result.stderr.contains("no terminal to ask in"))
    }
}
