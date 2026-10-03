import Foundation

/// Changes to skills.json and third-party submodules, all staged and never committed here.
public enum SourceEditor {
    /// Removes a skill from skills.json (staged). Drops its third-party submodule when nothing else uses it,
    /// unless `keepSource`. Returns the dropped submodule path, if any.
    @discardableResult
    public static func removeSkill(_ name: String, repo: Repository, keepSource: Bool) throws -> String? {
        var manifest = repo.manifest
        guard let entry = manifest.skills.removeValue(forKey: name) else {
            throw EditError.unknownSkill(name)
        }
        try manifest.write(to: repo.root.appendingPathComponent(Repository.manifestFile))
        let git = Git(repo.root)
        try git.run("add", Repository.manifestFile)

        let stillUsed = manifest.skills.values.contains { $0.source == entry.source }
        guard !keepSource, !stillUsed, entry.source.hasPrefix("third-party/") else { return nil }
        try git.run("submodule", "deinit", "--quiet", "--force", "--", entry.source)
        try git.run("rm", "--quiet", "--force", "--", entry.source)
        return entry.source
    }

    /// Adds skills to skills.json (staged).
    public static func addSkills(_ entries: [String: SkillEntry], repo: Repository) throws {
        var manifest = repo.manifest
        for (name, entry) in entries {
            if manifest.skills[name] != nil { throw EditError.duplicateSkill(name) }
            manifest.skills[name] = entry
        }
        try manifest.write(to: repo.root.appendingPathComponent(Repository.manifestFile))
        try Git(repo.root).run("add", Repository.manifestFile)
    }
}

public enum EditError: Error, CustomStringConvertible {
    case unknownSkill(String)
    case duplicateSkill(String)
    case invalidSource(String)
    case noSkills(String)
    case unknownSkillInSource(String, String, [String])

    public var description: String {
        switch self {
        case let .unknownSkill(name): return "`\(name)` is not in skills.json"
        case let .duplicateSkill(name): return "`\(name)` is already in skills.json"
        case let .invalidSource(text): return "cannot read `\(text)` as owner/repo, owner/repo@skill, or a git URL"
        case let .noSkills(source): return "no skills found in `\(source)`"
        case let .unknownSkillInSource(name, source, available):
            return "no skill `\(name)` in `\(source)`; available: \(available.joined(separator: ", "))"
        }
    }
}
