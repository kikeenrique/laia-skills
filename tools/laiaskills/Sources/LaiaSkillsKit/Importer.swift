import Foundation

/// One skill from `~/.agents/.skill-lock.json`, mapped to where it should come from here.
public struct ImportItem: Codable, Sendable {
    public enum Disposition: String, Codable, Sendable {
        /// Add `source` as a third-party submodule and take the skill from it.
        case thirdParty = "third-party"
        /// Already in skills.json.
        case managed
        /// Comes from this repo; listed under first-party.
        case firstParty = "first-party"
        /// No usable source recorded.
        case unknown
    }

    public let name: String
    public let disposition: Disposition
    /// `owner/repo` (or a git URL) for third-party items.
    public let source: String?
    public let note: String?
}

public enum Importer {
    /// Reads the `npx skills` lock (also used by other skill managers) and plans each entry.
    public static func plan(environment: Environment, repo: Repository) -> [ImportItem] {
        guard let data = try? Data(contentsOf: environment.skillsCLILock),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = json["skills"] as? [String: [String: Any]] else { return [] }
        let ownRepo = (try? Git(repo.root).run("remote", "get-url", "origin")).flatMap { try? SourceSpec($0) }

        return skills.keys.sorted().map { name in
            if repo.manifest.skills[name] != nil {
                return ImportItem(name: name, disposition: .managed, source: nil, note: nil)
            }
            let entry = skills[name]!
            switch entry["sourceType"] as? String {
            case "github":
                guard let source = entry["source"] as? String, let spec = try? SourceSpec(source) else {
                    return ImportItem(name: name, disposition: .unknown, source: nil, note: "unreadable GitHub source")
                }
                return item(name: name, spec: spec, ownRepo: ownRepo)
            case "local":
                guard let path = entry["sourceUrl"] as? String else {
                    return ImportItem(name: name, disposition: .unknown, source: nil, note: "no source path")
                }
                let folder = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: folder.path) else {
                    return ImportItem(name: name, disposition: .unknown, source: nil, note: "source folder no longer exists")
                }
                guard let origin = Git(folder).attempt("remote", "get-url", "origin"), let spec = try? SourceSpec(origin) else {
                    return ImportItem(name: name, disposition: .unknown, source: nil, note: "source folder is not a git clone")
                }
                return item(name: name, spec: spec, ownRepo: ownRepo)
            default:
                return ImportItem(name: name, disposition: .unknown, source: nil, note: "unsupported source type")
            }
        }
    }

    static func item(name: String, spec: SourceSpec, ownRepo: SourceSpec?) -> ImportItem {
        if let ownRepo, ownRepo.owner.lowercased() == spec.owner.lowercased(),
           ownRepo.repository.lowercased() == spec.repository.lowercased() {
            return ImportItem(name: name, disposition: .firstParty, source: nil, note: "comes from this repo")
        }
        return ImportItem(name: name, disposition: .thirdParty, source: "\(spec.owner)/\(spec.repository)", note: nil)
    }
}

/// A `.skill-lock.json` entry that `import --prune` removes.
public struct PruneItem: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        /// In skills.json and installed by laiaskills: the other tool must stop updating it.
        case managed
        /// Nothing is installed under that name any more.
        case notInstalled = "not installed"
    }

    public let name: String
    public let reason: Reason
}

/// Removes entries from the `npx skills` lock once laiaskills owns the skill, or nothing is installed.
/// Entries for skills another tool still installs (not managed here, or not yet synced) are left alone.
public enum LockPruner {
    public static func plan(repo: Repository, inspector: InstallInspector, environment: Environment) -> [PruneItem] {
        guard let skills = try? lockSkills(environment).skills else { return [] }
        return skills.keys.sorted().compactMap { name in
            switch inspector.hubState(name) {
            case .missing, .brokenLink:
                return PruneItem(name: name, reason: .notInstalled)
            case .managed where repo.manifest.skills[name] != nil:
                return PruneItem(name: name, reason: .managed)
            default:
                return nil
            }
        }
    }

    /// Copies the lock file to the backups folder, then removes `names` from it, keeping everything else.
    /// Returns the backup.
    @discardableResult
    public static func apply(_ names: [String], environment: Environment) throws -> URL {
        var (json, skills) = try lockSkills(environment)
        for name in names { skills[name] = nil }
        json["skills"] = skills

        let backup = environment.backups.appendingPathComponent("skill-lock-\(Installer.timestamp(compact: true)).json")
        try FileManager.default.createDirectory(at: environment.backups, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: environment.skillsCLILock, to: backup)
        // Pretty-printed with sorted keys: the layout the lock file already has.
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: environment.skillsCLILock, options: .atomic)
        return backup
    }

    static func lockSkills(_ environment: Environment) throws -> (json: [String: Any], skills: [String: Any]) {
        let data = try Data(contentsOf: environment.skillsCLILock)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.unreadable(environment.skillsCLILock, CocoaError(.fileReadCorruptFile))
        }
        return (json, json["skills"] as? [String: Any] ?? [:])
    }
}
