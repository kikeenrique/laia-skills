import Foundation

/// Where a browsed skill stands relative to `skills.json` and the agent folders.
public enum BrowseStatus: String, Codable, Sendable {
    /// In `skills.json` from this source and installed.
    case installed
    /// In `skills.json` from this source but not installed (run `sync`).
    case listed = "in skills.json"
    /// A managed skill with the same name comes from another source.
    case nameTaken = "name taken"
    /// The hub or a mirror has an entry with this name that laiaskills does not manage.
    case otherTool = "other tool"
    case available = "—"

    /// Whether `browse` lets you mark the skill to add. `otherTool` can be added: `sync` then asks
    /// before replacing the other copy.
    public var canAdd: Bool { self == .available || self == .otherTool }
}

/// One skill of a browsed source.
public struct BrowseRow: Codable, Sendable, Equatable {
    public let name: String
    /// Folder relative to the source: the copy `add` would pick when there are several.
    public let path: String
    public let copies: Int
    public let description: String?
    public let status: BrowseStatus
    /// Install detail for `installed` rows, e.g. `not synced`.
    public let detail: String?

    public var statusLabel: String {
        detail.map { "\(status.rawValue) (\($0))" } ?? status.rawValue
    }
}

/// A file inside a skill folder, read from git without downloading it.
public struct SkillFile: Codable, Sendable, Equatable {
    public let path: String
    public let executable: Bool

    /// Files an audit should read first: anything executable or under `scripts/`.
    public var needsAudit: Bool { executable || path.hasPrefix("scripts/") || path.contains("/scripts/") }
}

public enum Browser {
    /// One row per skill name in the checkout at `root`. `source` is the submodule path the skills
    /// would be (or are) added under, e.g. `third-party/owner__repo`.
    public static func rows(under root: URL, source: String, skills: [ResolvedSkill],
                            installer: Installer, inspector: InstallInspector) -> [BrowseRow] {
        let available = Adder.skills(under: root)
        var seen = Set<String>()
        return available.compactMap { skill -> BrowseRow? in
            let key = skill.name.lowercased()
            guard seen.insert(key).inserted, let chosen = Adder.find(skill.name, in: available) else { return nil }
            let text = try? String(contentsOf: root.appendingPathComponent(chosen.path).appendingPathComponent("SKILL.md"),
                                   encoding: .utf8)
            let (status, detail) = Self.status(of: key, source: source, skills: skills,
                                               installer: installer, inspector: inspector)
            return BrowseRow(
                name: key,
                path: chosen.path,
                copies: available.filter { SkillDiscovery.matches($0.name, key) }.count,
                description: text.flatMap { SkillDiscovery.frontmatterValue("description", in: $0) },
                status: status,
                detail: detail
            )
        }.sorted { $0.name < $1.name }
    }

    static func status(of name: String, source: String, skills: [ResolvedSkill],
                       installer: Installer, inspector: InstallInspector) -> (BrowseStatus, String?) {
        if let managed = skills.first(where: { $0.name.lowercased() == name }) {
            guard managed.entry.source.lowercased() == source.lowercased() else { return (.nameTaken, nil) }
            let install = installer.status(of: managed)
            switch install {
            case .notInstalled: return (.listed, nil)
            case .upToDate: return (.installed, nil)
            default: return (.installed, install.label)
            }
        }
        let elsewhere = inspector.hubState(name) != .missing
            || inspector.mirrors.contains { inspector.mirrorState(name, in: $0.url) != .missing }
        return (elsewhere ? .otherTool : .available, nil)
    }

    /// Files of the skill at `path` (relative to the checkout), from `git ls-tree`, so a preview clone
    /// lists them without downloading them.
    public static func files(of path: String, in checkout: URL) throws -> [SkillFile] {
        let prefix = path.isEmpty ? "" : path + "/"
        let output = try Git(checkout).run(["ls-tree", "-r", "--full-tree", "HEAD"] + (prefix.isEmpty ? [] : ["--", prefix]))
        return output.split(separator: "\n").compactMap { line in
            // `<mode> <type> <object>\t<path>`; only files (no nested submodules).
            let parts = line.split(separator: "\t", maxSplits: 1)
            let meta = parts.first?.split(separator: " ") ?? []
            guard parts.count == 2, meta.count == 3, meta[1] == "blob" else { return nil }
            return SkillFile(path: String(parts[1].dropFirst(prefix.count)), executable: meta[0] == "100755")
        }
    }

    /// The repository page's canonical `owner/repo` spelling (GitHub's `og:url` meta tag), so a source
    /// typed in another case, or lowercased by skills.sh, is stored as the host spells it. Falls back to
    /// `spec` for other hosts or when the page can't be read.
    public static func canonical(_ spec: SourceSpec) -> SourceSpec {
        guard spec.url.hasPrefix("https://github.com/"),
              let page = RenameDetector.webURL(spec.url),
              let result = try? Shell.run(["curl", "-sL", "--max-time", "10", page]), result.succeeded,
              let canonical = ogURL(in: result.stdout),
              let found = try? SourceSpec(canonical) else { return spec }
        guard found.owner.lowercased() == spec.owner.lowercased(),
              found.repository.lowercased() == spec.repository.lowercased() else { return spec }
        return SourceSpec(owner: found.owner, repository: found.repository,
                          url: "https://github.com/\(found.owner)/\(found.repository).git", skill: spec.skill)
    }

    /// `https://github.com/<owner>/<repo>` from an `og:url` meta tag.
    static func ogURL(in html: String) -> String? {
        guard let tag = html.range(of: #"<meta property="og:url" content=""#) else { return nil }
        let rest = html[tag.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let url = String(rest[..<end])
        return url.split(separator: "/").count == 4 ? url : nil
    }
}

/// A throwaway checkout of a source that isn't a submodule yet: a blobless, depth-1 clone with only the
/// `SKILL.md` files checked out, under the repo's `tmp/laiaskills-browse/`. Deleted with `remove()`;
/// leftovers from a crashed run are deleted by the next `cleanLeftovers`.
public struct PreviewClone: Sendable {
    public let folder: URL
    /// The release tag it was cloned at, or nil for the default branch head.
    public let tag: String?
    public let commit: String

    public var versionLabel: String { "\(tag ?? String(commit.prefix(7))) (preview)" }

    public static func root(repo: URL) -> URL {
        repo.appendingPathComponent("tmp/laiaskills-browse")
    }

    public static func make(_ spec: SourceSpec, repo: URL) throws -> PreviewClone {
        let root = Self.root(repo: repo)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A per-run folder, so two browses of the same repo don't delete each other's clone.
        let folder = root.appendingPathComponent("\(spec.owner)__\(spec.repository)-\(UUID().uuidString.prefix(8))")
        let tag = try Adder.remoteReleaseTags(Git(root), remote: spec.url).max()?.tag
        do {
            try Git(root).run(["clone", "--quiet", "--depth", "1", "--filter=blob:none", "--no-checkout"]
                + (tag.map { ["--branch", $0] } ?? []) + ["--", spec.url, folder.path])
            let git = Git(folder)
            // Non-cone patterns match like .gitignore: a bare name matches at any depth.
            try git.run("sparse-checkout", "set", "--no-cone", "SKILL.md")
            try git.run("checkout", "--quiet")
            return PreviewClone(folder: folder, tag: tag, commit: try git.run("rev-parse", "HEAD"))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public func remove() {
        try? FileManager.default.removeItem(at: folder)
        let root = folder.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Deletes clones left by runs that ended without cleaning up (a crash or Ctrl-C). Only folders older
    /// than `age` go, so a browse running in another terminal keeps its clone.
    public static func cleanLeftovers(repo: URL, olderThan age: TimeInterval = 3600, now: Date = Date()) {
        let root = Self.root(repo: repo)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? FileManager.default.removeItem(at: entry) }
        }
    }
}
