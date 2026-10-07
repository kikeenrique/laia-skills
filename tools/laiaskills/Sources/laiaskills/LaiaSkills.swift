import ArgumentParser
import Foundation
import LaiaSkillsKit

@main
struct LaiaSkills: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "laiaskills",
        abstract: "Manage agent skills pinned in this repo and installed into ~/.agents/skills.",
        subcommands: [
            ListCommand.self, ShowCommand.self, SourcesCommand.self, BrowseCommand.self, FindCommand.self,
            CheckCommand.self, DoctorCommand.self,
            SyncCommand.self, InstallCommand.self, RemoveCommand.self, AddCommand.self,
            UpgradeCommand.self, CommitCommand.self, ImportCommand.self, PatchCommand.self,
        ]
    )
}

/// Gets approval for a risky step: `--yes`, or an interactive prompt. Non-interactive runs without
/// `--yes` stop with an explanation instead of guessing.
func approve(_ ui: UI, _ question: String, yes: Bool) throws -> Bool {
    if yes { return true }
    guard ui.isInteractive else {
        throw ValidationError("\(question) Re-run with --yes to confirm (no terminal to ask in).")
    }
    return ui.confirm(question, default: false)
}

/// Looks up skills by name in the resolved list, failing on unknown names.
func select(_ names: [String], from skills: [ResolvedSkill]) throws -> [ResolvedSkill] {
    try names.map { name in
        guard let skill = skills.first(where: { $0.name == name }) else {
            throw ValidationError("`\(name)` is not in skills.json")
        }
        return skill
    }
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

/// A skill's state in one mirror, noting when the skill skips that mirror (`skipMirrors`).
func mirrorLabel(_ name: String, mirror: (name: String, url: URL), entry: SkillEntry?, _ context: Context) -> String {
    let state = context.inspector.mirrorState(name, in: mirror.url)
    guard entry?.skips(mirror: mirror.name) == true else { return state.rawValue }
    return state == .linked ? "linked, but skipped (run sync)" : "skipped"
}

func statusLabel(_ status: SourceStatus) -> String {
    switch (status.state, status.mode) {
    case (.upToDate, _): return "up to date"
    case (.outdated, .tagged): return "update: \(status.pinnedLabel) → \(status.latest ?? "?")"
    case (.outdated, .branch):
        guard let behind = status.commitsBehind else { return "newer commits on origin/\(status.latest ?? "?")" }
        return "\(behind) commits behind origin/\(status.latest ?? "?")"
    case (.unknown, _): return "unknown"
    }
}
