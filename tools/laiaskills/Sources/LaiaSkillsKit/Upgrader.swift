import Foundation

/// A pending move of one submodule pin.
public struct UpgradePlan: Sendable {
    public let source: Submodule
    public let fromCommit: String
    public let fromLabel: String
    public let toCommit: String
    public let toLabel: String
    /// skills.json skills that come from this source.
    public let skills: [String]
    /// Set when the source is a first-party plugin's `upstream/` pin.
    public let plugin: String?
    /// `git log --oneline` between the pins, limited to the skills' folders for skill sources.
    public let log: [String]
    /// Last line of `git diff --stat` (e.g. "3 files changed, 20 insertions(+)").
    public let diffSummary: String?

    /// Upstream project name from the URL, e.g. `mise` or `AXe`.
    public var upstreamName: String {
        let last = source.url.split(separator: "/").last.map(String.init) ?? source.path
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }
}

public enum UpgradeError: Error, CustomStringConvertible {
    case firstPartySkill(String, String?)
    case unknownTarget(String)
    case unknownRevision(String, String)

    public var description: String {
        switch self {
        case let .firstPartySkill(name, plugin):
            return "\(name) is a first-party skill; it changes by editing it"
                + (plugin.map { ". Its upstream pin is first-party/\($0)/upstream" } ?? "")
        case let .unknownTarget(text): return "`\(text)` is neither a skill in skills.json nor a submodule path"
        case let .unknownRevision(revision, source): return "`\(revision)` not found in \(source)"
        }
    }
}

public enum Upgrader {
    /// Fetches the source and works out where its pin would move. Returns nil when already there.
    /// - Parameter to: an explicit tag or commit; otherwise the newest release tag, or the branch head for untagged pins.
    public static func plan(source: Submodule, repo: Repository, skills: [ResolvedSkill], to: String?) throws -> UpgradePlan? {
        let root = repo.root
        let git = Git(root.appendingPathComponent(source.path))
        let current = try Pins.indexCommit(of: source.path, repo: root)
        let currentTag = Pins.releaseTag(at: current, git: git)
        let branch = source.branch ?? UpstreamChecker.defaultBranch(git) ?? "main"
        let depth = source.shallow ? ["--depth", "1"] : []

        let targetRef: String
        if let to {
            // `to` may be a tag or a commit; try both fetch forms and use whichever resolves.
            _ = try? git.run(["fetch", "--quiet", "--force", "origin", "tag", to] + depth)
            if git.attempt("rev-parse", "--verify", "--quiet", "\(to)^{commit}") == nil {
                _ = try? git.run(["fetch", "--quiet", "origin", to] + depth)
            }
            targetRef = git.attempt("rev-parse", "--verify", "--quiet", "\(to)^{commit}") != nil ? to : "FETCH_HEAD"
        } else if currentTag != nil, let newest = try Adder.remoteReleaseTags(git).max() {
            try git.run(["fetch", "--quiet", "--force", "origin", "tag", newest.tag] + depth)
            targetRef = newest.tag
        } else {
            try git.run(["fetch", "--quiet", "origin", branch] + depth)
            targetRef = "FETCH_HEAD"
        }
        guard let target = git.attempt("rev-parse", "\(targetRef)^{commit}") else {
            throw UpgradeError.unknownRevision(to ?? targetRef, source.path)
        }
        if target == current { return nil }

        let fromSource = skills.filter { $0.submodulePath == source.path }
        let paths = fromSource.compactMap { $0.folder.map { relativePath(of: $0, to: git.directory) } }
        let scope = paths.isEmpty ? [] : ["--"] + paths
        let log = (git.attempt(["log", "--oneline", "--no-decorate", "-n", "30", "\(current)..\(target)"] + scope) ?? "")
            .split(separator: "\n").map(String.init)
        let diff = git.attempt(["diff", "--stat", current, target] + scope)?
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) }

        // Label the target by its release tag when it has one, else by short commit.
        let toTag = ReleaseVersion(tag: targetRef) != nil ? targetRef : Pins.releaseTag(at: target, git: git)
        let plugin = source.isFirstPartyUpstream ? source.path.split(separator: "/").dropFirst().first.map(String.init) : nil
        return UpgradePlan(
            source: source, fromCommit: current, fromLabel: currentTag ?? String(current.prefix(7)),
            toCommit: target, toLabel: toTag ?? String(target.prefix(7)),
            skills: fromSource.map(\.name), plugin: plugin, log: log, diffSummary: diff
        )
    }

    /// Checks out the new pin in the submodule and stages it.
    public static func apply(_ plan: UpgradePlan, repo: URL) throws {
        try Git(repo.appendingPathComponent(plan.source.path)).run("checkout", "--quiet", plan.toCommit)
        try Git(repo).run("add", plan.source.path)
    }

    /// Turns command-line targets (skill names or submodule paths) into sources.
    public static func sources(for targets: [String], repo: Repository, submodules: [Submodule],
                               skills: [ResolvedSkill]) throws -> [Submodule] {
        var result: [Submodule] = []
        for target in targets {
            let path: String
            if let entry = repo.manifest.skills[target] {
                guard entry.source != SkillEntry.firstParty else {
                    throw UpgradeError.firstPartySkill(target, skills.first { $0.name == target }?.plugin)
                }
                path = entry.source
            } else {
                path = target.hasSuffix("/") ? String(target.dropLast()) : target
            }
            guard let submodule = submodules.first(where: { $0.path == path }) else { throw UpgradeError.unknownTarget(target) }
            if !result.contains(submodule) { result.append(submodule) }
        }
        return result
    }
}
