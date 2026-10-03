import Foundation

/// `~/.agents/.laiaskills.json`: what laiaskills installed into the hub, and from which pin.
/// Machine-local; never stored in the repo.
public struct InstallState: Codable, Sendable {
    public struct Record: Codable, Sendable, Equatable {
        /// `first-party`, or the submodule path the skill came from.
        public var source: String?
        /// Folder of the skill inside the git repo it was exported from.
        public var path: String?
        /// Commit the files were exported from (nil for `--working-tree` installs).
        public var commit: String?
        public var tag: String?
        /// Git tree id of the skill folder at `commit`: equal trees mean identical content.
        public var tree: String?
        /// Relative file path → git blob id, used to detect edits to the installed copy.
        public var files: [String: String]?
        public var installedAt: String?
        /// Installed from uncommitted first-party edits, for testing.
        public var workingTree: Bool?

        public init(source: String?, path: String?, commit: String?, tag: String?, tree: String?,
                    files: [String: String], installedAt: String, workingTree: Bool) {
            self.source = source
            self.path = path
            self.commit = commit
            self.tag = tag
            self.tree = tree
            self.files = files
            self.installedAt = installedAt
            self.workingTree = workingTree ? true : nil
        }
    }

    public var version: Int?
    public var skills: [String: Record]

    public init(skills: [String: Record] = [:]) {
        version = 1
        self.skills = skills
    }

    public static func load(_ environment: Environment) -> InstallState? {
        guard let data = try? Data(contentsOf: environment.stateFile) else { return nil }
        return try? JSONDecoder().decode(InstallState.self, from: data)
    }

    /// Writes atomically, so a crash never leaves a half-written state file.
    public func save(_ environment: Environment) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: environment.stateFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoder.encode(self).write(to: environment.stateFile, options: .atomic)
    }
}

/// Exactly which committed content a skill installs from.
public struct Pin: Sendable, Equatable {
    /// The git repo holding the files: this repo for first-party skills, else the submodule checkout.
    public let gitDirectory: URL
    public let commit: String
    /// Skill folder relative to `gitDirectory`.
    public let path: String
    public let tree: String
    public let tag: String?
}

public enum PinError: Error, CustomStringConvertible {
    case unresolved(String, String)
    case notCommitted(String, String)
    case noPin(String)

    public var description: String {
        switch self {
        case let .unresolved(name, problem): return "\(name): \(problem)"
        case let .notCommitted(name, path):
            return "\(name): `\(path)` is not in the last commit. Commit it first, or use --working-tree to test it."
        case let .noPin(path): return "no submodule pin recorded for `\(path)`"
        }
    }
}

public enum Pins {
    /// The pin a skill installs from. First-party skills come from the repo's `HEAD` commit; submodule
    /// skills from the submodule commit recorded in this repo's index (so a staged upgrade counts).
    public static func pin(for skill: ResolvedSkill, repo: URL) throws -> Pin {
        guard let folder = skill.folder else { throw PinError.unresolved(skill.name, skill.problem ?? "unresolved") }
        let gitDirectory = skill.submodulePath.map { repo.appendingPathComponent($0) } ?? repo
        let git = Git(gitDirectory)
        let commit = try skill.submodulePath.map { try indexCommit(of: $0, repo: repo) } ?? git.run("rev-parse", "HEAD")
        let path = relativePath(of: folder, to: gitDirectory)
        guard let tree = git.attempt("rev-parse", "\(commit):\(path)") else {
            throw PinError.notCommitted(skill.name, relativePath(of: folder, to: repo))
        }
        return Pin(gitDirectory: gitDirectory, commit: commit, path: path, tree: tree, tag: releaseTag(at: commit, git: git))
    }

    /// The submodule commit recorded in the index (`git ls-files -s`), i.e. the pin including staged moves.
    public static func indexCommit(of submodulePath: String, repo: URL) throws -> String {
        let line = try Git(repo).run("ls-files", "--stage", "--", submodulePath)
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2, fields[0] == "160000" else { throw PinError.noPin(submodulePath) }
        return String(fields[1])
    }

    /// The newest stable release tag pointing at `commit`, if any.
    static func releaseTag(at commit: String, git: Git) -> String? {
        (git.attempt("tag", "--points-at", commit) ?? "")
            .split(separator: "\n").compactMap { ReleaseVersion(tag: String($0)) }.max()?.tag
    }
}

/// Writes a skill folder's committed files out of git, and fingerprints installed copies.
public enum Exporter {
    struct Entry {
        let mode: String
        let blob: String
        let path: String
    }

    /// Writes the files of `pin` into `destination`; returns relative path → blob id.
    public static func export(_ pin: Pin, to destination: URL) throws -> [String: String] {
        let git = Git(pin.gitDirectory)
        let listing = try git.data(["ls-tree", "-r", "-z", pin.commit, "--", pin.path + "/"])
        var files: [String: String] = [:]
        for entry in parseTree(listing, prefix: pin.path + "/") {
            let target = destination.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch entry.mode {
            case "120000":
                let linkTarget = String(decoding: try git.data(["cat-file", "blob", entry.blob]), as: UTF8.self)
                try FileManager.default.createSymbolicLink(atPath: target.path, withDestinationPath: linkTarget)
            case "100644", "100755":
                try git.data(["cat-file", "blob", entry.blob]).write(to: target)
                if entry.mode == "100755" {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                }
            default:
                continue // nested submodules (160000) have no files to export
            }
            files[entry.path] = entry.blob
        }
        return files
    }

    static func parseTree(_ data: Data, prefix: String) -> [Entry] {
        String(decoding: data, as: UTF8.self).split(separator: "\0").compactMap { record in
            guard let tab = record.firstIndex(of: "\t") else { return nil }
            let meta = record[..<tab].split(separator: " ")
            let path = String(record[record.index(after: tab)...])
            guard meta.count == 3, path.hasPrefix(prefix) else { return nil }
            return Entry(mode: String(meta[0]), blob: String(meta[2]), path: String(path.dropFirst(prefix.count)))
        }
    }

    /// Relative path → git blob id for every file and symlink under `folder`.
    /// Uses `git hash-object`, so ids match the ones in git trees without needing a repo.
    public static func fingerprint(_ folder: URL) throws -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [:] }
        var regular: [String] = []
        var links: [(String, String)] = []
        for case let url as URL in enumerator {
            let path = relativePath(of: url, to: folder)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink?:
                // The enumerator never follows symlinks, so there is nothing below this entry to skip.
                links.append((path, try FileManager.default.destinationOfSymbolicLink(atPath: url.path)))
            case .typeRegular?:
                regular.append(path)
            default:
                continue
            }
        }
        var files: [String: String] = [:]
        let git = Git(folder)
        if !regular.isEmpty {
            let ids = try git.run(["hash-object", "--no-filters", "--"] + regular).split(separator: "\n")
            for (path, id) in zip(regular, ids) { files[path] = String(id) }
        }
        for (path, target) in links {
            files[path] = try git.run(["hash-object", "--no-filters", "--stdin"], input: Data(target.utf8))
        }
        return files
    }

    /// Copies a folder as it is on disk (for `--working-tree` installs).
    public static func copyWorkingTree(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
