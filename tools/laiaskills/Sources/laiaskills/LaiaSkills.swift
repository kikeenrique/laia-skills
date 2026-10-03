import ArgumentParser
import Foundation
import LaiaSkillsKit

@main
struct LaiaSkills: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "laiaskills",
        abstract: "Manage agent skills pinned in this repo and installed into ~/.agents/skills.",
        subcommands: [ListCommand.self, CheckCommand.self, DoctorCommand.self]
    )
}

/// Options shared by every subcommand.
struct GlobalOptions: ParsableArguments {
    @Option(help: "Path to the skills repo. Defaults to the nearest folder containing skills.json.")
    var repo: String?

    @Flag(help: "Print machine-readable JSON instead of tables.")
    var json = false

    func repository() throws -> Repository {
        let start = URL(fileURLWithPath: repo ?? FileManager.default.currentDirectoryPath)
        return repo == nil ? try Repository.locate(from: start) : try Repository(root: start)
    }
}

/// Everything the read-only commands need, loaded once.
struct Context {
    let repo: Repository
    let environment: Environment
    let submodules: [Submodule]
    let skills: [ResolvedSkill]
    let inspector: InstallInspector

    init(_ options: GlobalOptions) throws {
        repo = try options.repository()
        environment = .current
        submodules = try Submodules.load(repo: repo.root)
        skills = SkillResolver.resolve(repo, submodules: submodules)
        inspector = InstallInspector(agents: repo.agents, environment: environment)
    }

    /// `version` of a first-party plugin, from its plugin.json.
    func pluginVersion(_ plugin: String) -> String? {
        let manifest = repo.root.appendingPathComponent("first-party/\(plugin)/.claude-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }
}

func statusLabel(_ status: SourceStatus) -> String {
    switch (status.state, status.mode) {
    case (.upToDate, _): return "up to date"
    case (.outdated, .tagged): return "update: \(status.pinnedLabel) → \(status.latest ?? "?")"
    case (.outdated, .branch): return "\(status.commitsBehind ?? 0) commits behind origin/\(status.latest ?? "?")"
    case (.unknown, _): return "unknown"
    }
}
