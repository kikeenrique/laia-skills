import Foundation

/// `tools/config/recheck.json`: which AI agent CLI re-checks first-party skills, and how to call it.
public struct RecheckConfig: Codable, Sendable {
    public var agent: String
    /// Agent id → command; `{prompt}` is replaced with the rendered prompt.
    public var commands: [String: [String]]
    public var timeoutMinutes: Int

    public static let file = "tools/config/recheck.json"
    public static let promptFile = "tools/config/prompts/recheck.md"

    public static func load(repo: URL) throws -> RecheckConfig {
        try Repository.decode(RecheckConfig.self, at: repo.appendingPathComponent(file))
    }
}

public struct RecheckResult: Sendable {
    public let outcome: PendingChange.Recheck
    /// Files the agent changed outside the allowed folder, which were put back.
    public let reverted: [String]
    /// Skill files the agent changed (now staged).
    public let changed: [String]
}

public enum RecheckError: Error, CustomStringConvertible {
    case dirty(String, [String])
    case unknownAgent(String)
    case agentFailed(String, Int32)
    case validationFailed(String)

    public var description: String {
        switch self {
        case let .dirty(folder, paths):
            return "\(folder) has uncommitted changes (\(paths.prefix(5).joined(separator: ", "))); commit or stash them first"
        case let .unknownAgent(agent): return "no command for agent `\(agent)` in \(RecheckConfig.file)"
        case let .agentFailed(agent, status): return "\(agent) exited with status \(status); changes left unstaged for inspection"
        case let .validationFailed(output): return "the skill validator failed after the re-check; changes left for inspection:\n\(output)"
        }
    }
}

/// Runs an AI agent to re-check a first-party skill after its upstream pin moved, then guards the result.
public enum Rechecker {
    public typealias AgentRunner = @Sendable (_ command: [String], _ directory: URL, _ timeoutMinutes: Int) throws -> Int32
    /// Returns nil when the repo validates, else the validator's output.
    public typealias Validator = @Sendable (_ repo: URL) throws -> String?

    public static let skillValidator: Validator = { repo in
        let result = try Shell.run(["ruby", "tools/scripts/validate_skills.rb"], in: repo)
        return result.succeeded ? nil : result.stdout + result.stderr
    }

    public static func run(
        plan: UpgradePlan,
        repo: URL,
        config: RecheckConfig,
        runAgent: AgentRunner = { try Shell.runAttached($0, in: $1, timeoutMinutes: $2) },
        validate: Validator = skillValidator
    ) throws -> RecheckResult {
        guard let plugin = plan.plugin else { return RecheckResult(outcome: .skipped, reverted: [], changed: []) }
        let skillsFolder = "first-party/\(plugin)/skills/"
        let git = Git(repo)

        let before = try dirtyPaths(git)
        let dirtySkillFiles = before.filter { $0.hasPrefix(skillsFolder) }
        guard dirtySkillFiles.isEmpty else { throw RecheckError.dirty(skillsFolder, dirtySkillFiles.sorted()) }

        guard let template = config.commands[config.agent] else { throw RecheckError.unknownAgent(config.agent) }
        let prompt = try renderPrompt(plan: plan, plugin: plugin, repo: repo)
        let command = template.map { $0 == "{prompt}" ? prompt : $0 }
        let status = try runAgent(command, repo, config.timeoutMinutes)

        // Put back anything the agent touched outside the plugin's skills folder.
        let touched = try dirtyPaths(git).subtracting(before)
        var reverted: [String] = []
        for path in touched.sorted() where !path.hasPrefix(skillsFolder) {
            try revert(path, git: git, repo: repo)
            reverted.append(path)
        }
        guard status == 0 else { throw RecheckError.agentFailed(config.agent, status) }

        if let failure = try validate(repo) { throw RecheckError.validationFailed(failure) }

        let changed = touched.filter { $0.hasPrefix(skillsFolder) }.sorted()
        if !changed.isEmpty { try git.run("add", "--all", "--", skillsFolder) }
        return RecheckResult(outcome: changed.isEmpty ? .unchanged : .changed, reverted: reverted, changed: changed)
    }

    static func renderPrompt(plan: UpgradePlan, plugin: String, repo: URL) throws -> String {
        let template = try String(contentsOf: repo.appendingPathComponent(RecheckConfig.promptFile), encoding: .utf8)
        let values = [
            "plugin": plugin,
            "upstream": plan.upstreamName,
            "upstreamPath": plan.source.path,
            "from": plan.fromLabel,
            "to": plan.toLabel,
            "skillsPath": "first-party/\(plugin)/skills",
        ]
        return values.reduce(template) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    /// Paths with staged, unstaged, or untracked changes.
    static func dirtyPaths(_ git: Git) throws -> Set<String> {
        let output = try git.data(["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"])
        return Set(String(decoding: output, as: UTF8.self).split(separator: "\0").compactMap { entry in
            entry.count > 3 ? String(entry.dropFirst(3)) : nil
        })
    }

    static func revert(_ path: String, git: Git, repo: URL) throws {
        let submodules = try Submodules.load(repo: repo).map(\.path)
        if submodules.contains(path) {
            try git.run("submodule", "update", "--checkout", "--quiet", "--", path)
        } else if git.attempt("ls-files", "--error-unmatch", "--", path) != nil {
            try git.run("checkout", "--", path)
        } else {
            try FileManager.default.removeItem(at: repo.appendingPathComponent(path))
        }
    }
}
