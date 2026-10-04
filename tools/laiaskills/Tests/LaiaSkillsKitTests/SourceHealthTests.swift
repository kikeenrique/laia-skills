import Foundation
import Testing
@testable import LaiaSkillsKit
import LaiaSkillsTestSupport

@Suite struct RenameDetectorTests {
    @Test(arguments: [
        ("https://github.com/affaan-m/everything-claude-code.git", "https://github.com/affaan-m/everything-claude-code"),
        ("git@github.com:o/r.git", "https://github.com/o/r"),
        ("https://codeberg.org/CupertinoHQ/cupertino", "https://codeberg.org/CupertinoHQ/cupertino"),
    ])
    func derivesTheWebPage(_ remote: String, _ page: String) {
        #expect(RenameDetector.webURL(remote) == page)
    }

    @Test func ignoresLocalRemotes() {
        #expect(RenameDetector.webURL("file:///tmp/repo") == nil)
        #expect(RenameDetector.webURL("/tmp/repo") == nil)
    }

    @Test func aRedirectToAnotherPathIsARename() {
        let page = "https://github.com/affaan-m/everything-claude-code"
        #expect(RenameDetector.renamed(page: page, redirect: "https://github.com/affaan-m/ECC") == "https://github.com/affaan-m/ECC")
        // Case-only changes and trailing slashes are the same repository.
        #expect(RenameDetector.renamed(page: "https://github.com/avdlee/x", redirect: "https://github.com/AvdLee/x/") == nil)
        #expect(RenameDetector.renamed(page: page, redirect: "") == nil)
    }
}

@Suite struct ClaudePluginsTests {
    /// Two installed plugins from marketplace `m`; the marketplace clone lists a newer `a`.
    private func setUp() throws -> (Fixture, Environment) {
        let fixture = try Fixture()
        try fixture.write("home/.claude/plugins/installed_plugins.json", """
        {"version": 2, "plugins": {"a@m": [{"version": "1.0.3"}], "b@m": [{"version": "1.0.0"}]}}
        """)
        try fixture.write("home/.claude/plugins/known_marketplaces.json", """
        {"m": {"installLocation": "\(fixture.url("clones/m").path)"}}
        """)
        try fixture.write("clones/m/.claude-plugin/marketplace.json", """
        {"plugins": [{"name": "a", "version": "1.0.4"}, {"name": "b", "version": "1.0.0"}]}
        """)
        return (fixture, Environment(home: fixture.url("home")))
    }

    // The fixture is kept in a variable: releasing it deletes its folder.
    @Test func reportsNewerMarketplaceVersions() throws {
        let (fixture, environment) = try setUp()
        defer { withExtendedLifetime(fixture) {} }
        #expect(ClaudePlugins.updates(environment: environment)
            == [ClaudePluginUpdate(plugin: "a@m", installed: "1.0.3", available: "1.0.4")])
    }

    @Test func comparesInstalledPluginsWithTheDeclaredOnes() throws {
        let (fixture, environment) = try setUp()
        defer { withExtendedLifetime(fixture) {} }
        #expect(ClaudePlugins.findings(declared: nil, environment: environment).isEmpty)
        let findings = ClaudePlugins.findings(declared: ["a@m", "c@m"], environment: environment)
        #expect(findings.map(\.severity) == [.warning, .info])
        #expect(findings[0].message.hasPrefix("c@m is declared"))
        #expect(findings[1].message.hasPrefix("b@m is installed but not declared"))
    }

    @Test func manifestWritesDeclaredPlugins() throws {
        let fixture = try Fixture()
        let manifest = SkillsManifest(skills: ["a": SkillEntry(source: "first-party")], claudePlugins: ["swift-lsp@official"])
        try manifest.write(to: fixture.url("skills.json"))
        let text = try fixture.read("skills.json")
        #expect(text.contains("  \"claudePlugins\": [\"swift-lsp@official\"],\n  \"skills\": {"))
        let decoded = try JSONDecoder().decode(SkillsManifest.self, from: Data(text.utf8))
        #expect(decoded.claudePlugins == ["swift-lsp@official"])
    }
}
