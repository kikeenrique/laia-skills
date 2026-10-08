import Foundation

/// One commit `laiaskills commit` will make.
public struct CommitGroup: Sendable {
    public let subject: String
    public let body: String
    /// Paths committed (pathspec); other staged changes stay staged.
    public let paths: [String]
    /// First-party plugin whose `version` is bumped in this commit.
    public let plugin: String?
    /// The pending changes this commit covers.
    public let changes: [PendingChange]
    /// Skills to reinstall after committing (first-party content is installed from HEAD).
    public let skillsToSync: [String]
}

public enum VersionBump: String, CaseIterable, Sendable {
    case patch, minor, major

    public func apply(to version: String) -> String {
        var parts = version.split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        switch self {
        case .patch: parts[2] += 1
        case .minor: parts[1] += 1; parts[2] = 0
        case .major: parts[0] += 1; parts[1] = 0; parts[2] = 0
        }
        return parts.map(String.init).joined(separator: ".")
    }
}

public enum CommitError: Error, CustomStringConvertible {
    case nothingPending
    case versionNotFound(String)

    public var description: String {
        switch self {
        case .nothingPending: return "nothing to commit: no pending laiaskills changes"
        case let .versionNotFound(file): return "no \"version\" field found in \(file)"
        }
    }
}

public enum Committer {
    /// Groups pending changes into commits: skills.json edits, third-party bumps, and one commit per
    /// first-party plugin whose upstream moved (matching how this repo writes history).
    public static func plan(_ pending: PendingChanges, upstreamNames: [String: String]) -> [CommitGroup] {
        var groups: [CommitGroup] = []
        let edits = pending.changes.filter { $0.kind == .add || $0.kind == .remove }
        let upgrades = pending.changes.filter { $0.kind == .upgrade }
        let patches = pending.changes.filter { $0.kind == .patch }

        if !edits.isEmpty {
            let added = edits.filter { $0.kind == .add }.flatMap(\.skills)
            let removed = edits.filter { $0.kind == .remove }.flatMap(\.skills)
            let subject: String
            switch (added.isEmpty, removed.isEmpty) {
            case (false, true): subject = "feat(skills): add \(list(added))"
            case (true, false): subject = "chore(skills): remove \(list(removed))"
            default: subject = "chore(skills): add \(list(added)); remove \(list(removed))"
            }
            let body = edits.map { change in
                let verb = change.kind == .add ? "Add" : "Remove"
                return "- \(verb) \(change.skills.joined(separator: ", "))" + (change.source.map { " (\($0)\(change.to.map { " \($0)" } ?? ""))" } ?? "")
            }.joined(separator: "\n")
            let sources = edits.compactMap(\.source).filter { $0.hasPrefix("third-party/") }
            groups.append(CommitGroup(subject: subject, body: body, paths: ["skills.json", ".gitmodules"] + sources,
                                      plugin: nil, changes: edits, skillsToSync: []))
        }

        let thirdParty = upgrades.filter { $0.plugin == nil }
        if !thirdParty.isEmpty {
            let parts = thirdParty.map { "\(($0.source ?? "").replacingOccurrences(of: "third-party/", with: "")) to \($0.to ?? "?")" }
            let full = "chore(third-party): bump \(parts.joined(separator: ", "))"
            let subject = full.count <= 72 ? full : "chore(third-party): bump \(thirdParty.count) sources"
            let body = thirdParty.map { "- \($0.source ?? ""): \($0.from ?? "?") → \($0.to ?? "?") (skills: \($0.skills.joined(separator: ", ")))" }
                .joined(separator: "\n") + droppedLines(thirdParty)
            // When `upgrade` stops on a patch that no longer applies, the fix is to edit or delete it by
            // hand: include the upgraded skills' patch folders so that fix lands in the bump. Skills
            // with a pending `patch` keep it for their own commit below.
            let patchedSeparately = Set(patches.flatMap(\.skills))
            let patchFolders = thirdParty.flatMap(\.skills).filter { !patchedSeparately.contains($0) }.map(Patches.path(for:))
            groups.append(CommitGroup(subject: subject, body: body,
                                      paths: thirdParty.compactMap(\.source) + thirdParty.flatMap { $0.droppedPatches ?? [] }
                                          + patchFolders,
                                      plugin: nil, changes: thirdParty, skillsToSync: []))
        }

        for change in upgrades where change.plugin != nil {
            let plugin = change.plugin!
            let upstream = change.source.flatMap { upstreamNames[$0] } ?? plugin
            let recheck: String
            switch change.recheck {
            case .changed?: recheck = "Skill updated by an automated re-check against \(upstream) \(change.to ?? "")."
            case .unchanged?: recheck = "Re-checked against \(upstream) \(change.to ?? "") by an automated re-check; no changes needed."
            default: recheck = "The skill was not re-checked automatically."
            }
            var body = "Re-pins \(change.source ?? "upstream") from \(change.from ?? "?") to \(change.to ?? "?"). \(recheck)"
            let extra = change.skills.filter { $0 != plugin }
            if !extra.isEmpty { body += "\nAlso updates skills taken from the pin: \(extra.joined(separator: ", "))." }
            body += droppedLines([change])
            groups.append(CommitGroup(
                subject: "docs(\(plugin)): refresh guidance for \(upstream) \(change.to ?? "")",
                body: body,
                paths: [change.source, "first-party/\(plugin)/skills", "first-party/\(plugin)/.claude-plugin/plugin.json",
                        ".claude-plugin/marketplace.json"].compactMap { $0 } + (change.droppedPatches ?? []),
                plugin: plugin, changes: [change], skillsToSync: change.skills
            ))
        }

        // One commit per patch, scoped to the skill it fixes.
        for change in patches {
            let skill = change.skills.first ?? "skills"
            let full = "fix(\(skill)): \(change.reason ?? "patch the installed copy")"
            groups.append(CommitGroup(
                subject: full.count <= 72 ? full : "fix(\(skill)): patch the installed copy",
                body: "Adds \(change.patch ?? Patches.path(for: skill)), applied to the installed copy on top of "
                    + "\(change.source ?? "the pinned source")\(change.to.map { " \($0)" } ?? "")."
                    + (full.count <= 72 ? "" : "\n\nReason: \(change.reason ?? "")"),
                paths: [change.patch ?? Patches.path(for: skill)],
                plugin: nil, changes: [change], skillsToSync: []
            ))
        }
        return groups
    }

    static func droppedLines(_ changes: [PendingChange]) -> String {
        let dropped = changes.flatMap { $0.droppedPatches ?? [] }
        return dropped.isEmpty ? "" : "\n\nDrops patches the new version already contains:\n"
            + dropped.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Bumps `version` in the plugin's plugin.json and its marketplace.json entry, editing the text so
    /// formatting is preserved. Returns the old and new version.
    @discardableResult
    public static func bumpVersion(plugin: String, bump: VersionBump, repo: URL) throws -> (String, String) {
        let manifest = repo.appendingPathComponent("first-party/\(plugin)/.claude-plugin/plugin.json")
        var text = try String(contentsOf: manifest, encoding: .utf8)
        guard let range = versionRange(in: text, after: text.startIndex) else { throw CommitError.versionNotFound(manifest.path) }
        let old = String(text[range])
        let new = bump.apply(to: old)
        text.replaceSubrange(range, with: new)
        try text.write(to: manifest, atomically: true, encoding: .utf8)

        let marketplace = repo.appendingPathComponent(".claude-plugin/marketplace.json")
        var market = try String(contentsOf: marketplace, encoding: .utf8)
        if let name = market.range(of: "\"name\": \"\(plugin)\""), let range = versionRange(in: market, after: name.upperBound) {
            market.replaceSubrange(range, with: new)
            try market.write(to: marketplace, atomically: true, encoding: .utf8)
        }
        return (old, new)
    }

    /// Range of the value of the first `"version": "…"` at or after `start`.
    static func versionRange(in text: String, after start: String.Index) -> Range<String.Index>? {
        guard let key = text.range(of: "\"version\"", range: start..<text.endIndex),
              let open = text.range(of: "\"", range: text.index(after: text[key.upperBound...].firstIndex(of: ":") ?? key.upperBound)..<text.endIndex),
              let close = text.range(of: "\"", range: open.upperBound..<text.endIndex) else { return nil }
        return open.upperBound..<close.lowerBound
    }

    /// Commits one group with a pathspec, so unrelated staged changes are left alone.
    public static func commit(_ group: CommitGroup, repo: URL) throws -> String {
        let git = Git(repo)
        let existing = group.paths.filter {
            FileManager.default.fileExists(atPath: repo.appendingPathComponent($0).path)
                || git.attempt("ls-files", "--error-unmatch", "--", $0) != nil
                || (git.attempt("diff", "--cached", "--name-only", "--", $0) ?? "").isEmpty == false
        }
        try git.run(["add", "--all", "--"] + existing.filter { FileManager.default.fileExists(atPath: repo.appendingPathComponent($0).path) })
        try git.run(["commit", "--quiet", "-m", group.subject, "-m", group.body, "--"] + existing)
        return try git.run("rev-parse", "--short", "HEAD")
    }

    static func list(_ names: [String]) -> String {
        names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
    }
}
